using System.Data;
using Dapper;
using KLOP.Platform.Application;
using KLOP.Platform.Domain;
using Microsoft.Data.SqlClient;

namespace KLOP.Platform.Infrastructure;

public sealed partial class KlopRepository
{
    public async Task<(long UserId, long ChallengeId)> Register(string email, string displayName,
        string passwordHash, byte[] tokenHash, string requestId, Guid correlationId,
        string? registrationTypeCode, Guid? termsDocumentVersionId, bool? termsAccepted,
        bool developmentTermsBypassEnabled,
        CancellationToken cancellationToken)
    {
        var parameters = BuildRegistrationParameters(email, displayName, passwordHash, tokenHash,
            DateTime.UtcNow.AddHours(settings.EmailVerificationHours), requestId, correlationId,
            registrationTypeCode, termsDocumentVersionId, termsAccepted, developmentTermsBypassEnabled);
        try
        {
            await Execute("iam.usp_RegisterLocalUser", parameters, cancellationToken);
        }
        catch (SqlException exception) when (exception.Number == 52113)
        {
            throw new DuplicateRegistrationException();
        }
        return (parameters.Get<long>("UserId"), parameters.Get<long>("ChallengeId"));
    }

    internal static DynamicParameters BuildRegistrationParameters(
        string email,
        string displayName,
        string passwordHash,
        byte[] tokenHash,
        DateTime verificationExpiresAtUtc,
        string requestId,
        Guid correlationId,
        string? registrationTypeCode,
        Guid? termsDocumentVersionId,
        bool? termsAccepted,
        bool developmentTermsBypassEnabled)
    {
        var parameters = new DynamicParameters();
        parameters.Add("Email", email, DbType.String, size: 320);
        parameters.Add("DisplayName", displayName, DbType.String, size: 150);
        parameters.Add("PasswordHash", passwordHash, DbType.String, size: 1024);
        parameters.Add("VerificationTokenHash", tokenHash, DbType.Binary, size: 32);
        parameters.Add("VerificationExpiresAtUtc", verificationExpiresAtUtc, DbType.DateTime2);
        parameters.Add("RequestId", requestId, DbType.AnsiString, size: 100);
        parameters.Add("CorrelationId", correlationId, DbType.Guid);
        parameters.Add("UserId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        parameters.Add("ChallengeId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        parameters.Add("DevelopmentTermsBypassEnabled", developmentTermsBypassEnabled, DbType.Boolean);
        if (registrationTypeCode is not null)
        {
            parameters.Add("RegistrationTypeCode", registrationTypeCode, DbType.AnsiString, size: 50);
            parameters.Add("TermsDocumentVersionId", termsDocumentVersionId, DbType.Guid);
            parameters.Add("TermsAccepted", termsAccepted, DbType.Boolean);
            parameters.Add("RegistrationApplicationId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        }
        return parameters;
    }

    public Task ConfirmEmail(long userId, byte[] tokenHash, string requestId, Guid correlationId,
        CancellationToken cancellationToken) =>
        Execute("iam.usp_ConfirmEmail", Params(("UserId", userId), ("VerificationTokenHash", tokenHash),
            ("RequestId", requestId), ("CorrelationId", correlationId)), cancellationToken);

    public async Task<long?> Resend(string email, byte[] hash, string requestId, Guid correlationId,
        CancellationToken cancellationToken)
    {
        var parameters = Params(("Email", email), ("TokenHash", hash),
            ("ExpiresAtUtc", DateTime.UtcNow.AddHours(settings.EmailVerificationHours)),
            ("RequestId", requestId), ("CorrelationId", correlationId));
        parameters.Add("UserId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        await Execute("iam.usp_IssueEmailVerificationChallenge", parameters, cancellationToken);
        return parameters.Get<long?>("UserId");
    }

    public Task<LoginCandidate?> GetLoginCandidate(string email, CancellationToken cancellationToken) =>
        One<LoginCandidate>("iam.usp_GetLocalLoginCandidate", Params(("NormalizedEmail", email)), cancellationToken);

    public Task RecordLoginFailure(long userId, Guid correlationId, CancellationToken cancellationToken) =>
        Execute("iam.usp_RecordLocalLoginFailure", Params(("UserId", userId), ("CorrelationId", correlationId)),
            cancellationToken);

    public async Task<Guid> CreateSession(long userId, byte[] refreshHash, Guid correlationId, string requestId,
        CancellationToken cancellationToken)
    {
        var lifetimeEnd = DateTime.UtcNow.AddDays(settings.RefreshDays);
        var parameters = Params(("UserId", userId), ("SessionExpiresAtUtc", lifetimeEnd),
            ("RefreshTokenHash", refreshHash), ("RefreshExpiresAtUtc", lifetimeEnd),
            ("RequestId", requestId), ("CorrelationId", correlationId));
        parameters.Add("PublicSessionId", dbType: DbType.Guid, direction: ParameterDirection.Output);
        await Execute("iam.usp_CreateAuthSession", parameters, cancellationToken);
        return parameters.Get<Guid>("PublicSessionId");
    }

    public Task ValidateSession(long userId, Guid sessionId, long? tenantId, string? permission,
        CancellationToken cancellationToken) =>
        Execute("iam.usp_ValidateSessionAccess", Params(("UserId", userId), ("PublicSessionId", sessionId),
            ("TenantId", tenantId), ("PermissionCode", permission)), cancellationToken);

    public async Task<long> RotateRefresh(Guid sessionId, byte[] oldHash, byte[] newHash, Guid correlationId,
        CancellationToken cancellationToken)
    {
        var parameters = Params(("PublicSessionId", sessionId), ("OldTokenHash", oldHash),
            ("NewTokenHash", newHash), ("NewExpiresAtUtc", DateTime.UtcNow.AddDays(settings.RefreshDays)),
            ("CorrelationId", correlationId));
        parameters.Add("UserId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        await Execute("iam.usp_RotateRefreshToken", parameters, cancellationToken);
        return parameters.Get<long>("UserId");
    }

    public Task RevokeSession(long userId, Guid sessionId, Guid correlationId, CancellationToken cancellationToken) =>
        Execute("iam.usp_RevokeAuthSession", Params(("UserId", userId), ("PublicSessionId", sessionId),
            ("CorrelationId", correlationId)), cancellationToken);

    public Task<Profile?> GetProfile(long userId, CancellationToken cancellationToken) =>
        One<Profile>("iam.usp_GetUserProfile", Params(("UserId", userId)), cancellationToken);
}