using KLOP.Platform.Domain;
using Microsoft.Extensions.Logging;

namespace KLOP.Platform.Application;

public sealed class AuthenticationService(
    IPlatformRepository repository,
    PasswordCodec passwordCodec,
    IAccessTokenIssuer tokenIssuer,
    IVerificationEmailSender emailSender,
    IPlatformRuntimeSettings settings,
    ILogger<AuthenticationService> logger)
{
    private static readonly Lazy<string> DummyHash =
        new(() => new PasswordCodec().Hash("DummyPasswordRandomForTimingOnly2026!"));

    public async Task Register(RegistrationRequest request, RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var rawToken = SecretTokens.NewToken();
        (long UserId, long ChallengeId) result;
        try
        {
            result = await repository.Register(request.Email.Trim(), request.DisplayName.Trim(),
                passwordCodec.Hash(request.Password, settings.MinPasswordLength), SecretTokens.Sha256(rawToken),
                metadata.RequestId, metadata.CorrelationId, cancellationToken);
        }
        catch (DuplicateRegistrationException)
        {
            // Registration intentionally stays indistinguishable for existing addresses.
            return;
        }
        await SendVerificationSafely(request.Email.Trim(), result.UserId, rawToken, cancellationToken);
    }

    public async Task ResendVerification(ResendVerificationRequest request, RequestMetadata metadata,
        CancellationToken cancellationToken)
    {
        var rawToken = SecretTokens.NewToken();
        var userId = await repository.Resend(request.Email.Trim(), SecretTokens.Sha256(rawToken),
            metadata.RequestId, metadata.CorrelationId, cancellationToken);
        if (userId.HasValue)
            await SendVerificationSafely(request.Email.Trim(), userId.Value, rawToken, cancellationToken);
    }

    public Task ConfirmEmail(VerifyEmailRequest request, RequestMetadata metadata, CancellationToken cancellationToken) =>
        repository.ConfirmEmail(request.UserId, SecretTokens.Sha256(request.Token), metadata.RequestId,
            metadata.CorrelationId, cancellationToken);

    public async Task<AuthenticatedSession?> Login(LoginRequest request, RequestMetadata metadata,
        CancellationToken cancellationToken)
    {
        var candidate = await repository.GetLoginCandidate(SecretTokens.NormalizeEmail(request.Email), cancellationToken);
        var passwordMatches = passwordCodec.Verify(request.Password, candidate?.PasswordHash ?? DummyHash.Value);
        var now = DateTime.UtcNow;
        var allowed = candidate is not null && passwordMatches && candidate.IsActive &&
            candidate.EmailVerifiedAtUtc.HasValue &&
            (!candidate.LockoutUntilUtc.HasValue || candidate.LockoutUntilUtc.Value <= now);

        if (!allowed)
        {
            if (candidate is not null && !passwordMatches)
                await repository.RecordLoginFailure(candidate.UserId, metadata.CorrelationId, cancellationToken);
            return null;
        }

        var refreshToken = SecretTokens.NewToken();
        var sessionId = await repository.CreateSession(candidate!.UserId, SecretTokens.Sha256(refreshToken),
            metadata.CorrelationId, metadata.RequestId, cancellationToken);
        return new AuthenticatedSession(tokenIssuer.Issue(candidate.UserId, sessionId), sessionId, refreshToken,
            settings.RefreshDays);
    }

    public async Task<AuthenticatedSession> Refresh(Guid sessionId, string oldRefreshToken,
        RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var newRefreshToken = SecretTokens.NewToken();
        var userId = await repository.RotateRefresh(sessionId, SecretTokens.Sha256(oldRefreshToken),
            SecretTokens.Sha256(newRefreshToken), metadata.CorrelationId, cancellationToken);
        return new AuthenticatedSession(tokenIssuer.Issue(userId, sessionId), sessionId, newRefreshToken,
            settings.RefreshDays);
    }

    public Task Logout(long userId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) =>
        repository.RevokeSession(userId, sessionId, metadata.CorrelationId, cancellationToken);

    public Task<Profile?> GetProfile(long userId, CancellationToken cancellationToken) =>
        repository.GetProfile(userId, cancellationToken);

    private async Task SendVerificationSafely(string email, long userId, string token, CancellationToken cancellationToken)
    {
        try
        {
            await emailSender.Send(email, userId, token, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            logger.LogWarning("Verification email delivery failed after the database operation committed. FailureType={FailureType}",
                exception.GetType().Name);
        }
    }
}

public sealed class TenantManagementService(IPlatformRepository repository)
{
    public async Task<(long TenantId, long MembershipId)> CreateTenant(long userId, TenantCreateRequest request,
        RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var types = await repository.TenantTypes(cancellationToken);
        var tenantType = types.FirstOrDefault(x =>
            string.Equals(x.Code, request.TenantTypeCode.Trim(), StringComparison.OrdinalIgnoreCase));
        if (tenantType is null)
            throw new UnknownTenantTypeException();

        var settingKey = $"registration.{tenantType.Code.ToLowerInvariant()}.enabled";
        var setting = await repository.GetConfiguration(settingKey, cancellationToken);
        if (setting is null || setting.StorageType != "PLAIN" || setting.ValueType != "BOOLEAN" ||
            !bool.TryParse(setting.ConfigurationValue, out var enabled))
            throw new InvalidOperationException($"Required SQL setting '{settingKey}' is missing or invalid.");
        if (!enabled)
            throw new TenantRegistrationDisabledException();

        return await repository.CreateTenant(userId, request.TenantCode.Trim(), tenantType.Code,
            request.DisplayName.Trim(), request.OrganizationTypeId, request.RegisteredName?.Trim(),
            metadata.RequestId, metadata.CorrelationId, cancellationToken);
    }

    public Task<IReadOnlyList<TenantSummary>> MyTenants(long userId, CancellationToken cancellationToken) =>
        repository.MyTenants(userId, cancellationToken);

    public Task<long> Invite(long tenantId, long actorUserId, long inviteeUserId, RequestMetadata metadata,
        CancellationToken cancellationToken) =>
        repository.Invite(tenantId, actorUserId, inviteeUserId, metadata.RequestId, metadata.CorrelationId,
            cancellationToken);

    public Task Accept(long membershipId, long actorUserId, RequestMetadata metadata,
        CancellationToken cancellationToken) =>
        repository.Accept(membershipId, actorUserId, metadata.RequestId, metadata.CorrelationId, cancellationToken);

    public Task Remove(long membershipId, long actorUserId, RequestMetadata metadata,
        CancellationToken cancellationToken) =>
        repository.Remove(membershipId, actorUserId, metadata.RequestId, metadata.CorrelationId, cancellationToken);

    public Task AssignRole(long membershipId, long actorUserId, string roleCode, RequestMetadata metadata,
        CancellationToken cancellationToken) =>
        repository.AssignRole(membershipId, actorUserId, roleCode.Trim(), metadata.RequestId,
            metadata.CorrelationId, cancellationToken);

    public Task RevokeRole(long membershipId, long actorUserId, string roleCode, RequestMetadata metadata,
        CancellationToken cancellationToken) =>
        repository.RevokeRole(membershipId, actorUserId, roleCode.Trim(), metadata.RequestId,
            metadata.CorrelationId, cancellationToken);
}
