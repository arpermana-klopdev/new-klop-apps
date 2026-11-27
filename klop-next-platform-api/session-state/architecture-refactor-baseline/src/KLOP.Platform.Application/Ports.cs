using KLOP.Platform.Domain;

namespace KLOP.Platform.Application;

public interface IPasswordPolicy
{
    int MinPasswordLength { get; }
}

public interface IPlatformRuntimeSettings : IPasswordPolicy
{
    string JwtIssuer { get; }
    string JwtAudience { get; }
    string AllowedOrigin { get; }
    int AccessMinutes { get; }
    int RefreshDays { get; }
    int MaxLoginAttempts { get; }
    int EmailVerificationHours { get; }
    int CommandTimeoutSeconds { get; }
    int AuthRequestsPerMinute { get; }
    string SmtpHost { get; }
    int SmtpPort { get; }
    string SmtpFrom { get; }
    bool SmtpRequireTls { get; }
    string? SmtpUsername { get; }
    string? SigningKeyReference { get; }
    string? SmtpPasswordReference { get; }
}

public interface IPlatformRepository
{
    Task<(long UserId, long ChallengeId)> Register(string email, string displayName, string passwordHash,
        byte[] tokenHash, string requestId, Guid correlationId, CancellationToken cancellationToken);
    Task ConfirmEmail(long userId, byte[] tokenHash, string requestId, Guid correlationId,
        CancellationToken cancellationToken);
    Task<long?> Resend(string email, byte[] hash, string requestId, Guid correlationId,
        CancellationToken cancellationToken);
    Task<LoginCandidate?> GetLoginCandidate(string email, CancellationToken cancellationToken);
    Task RecordLoginFailure(long userId, Guid correlationId, CancellationToken cancellationToken);
    Task<Guid> CreateSession(long userId, byte[] refreshHash, Guid correlationId, string requestId,
        CancellationToken cancellationToken);
    Task ValidateSession(long userId, Guid sessionId, long? tenantId, string? permission,
        CancellationToken cancellationToken);
    Task<long> RotateRefresh(Guid sessionId, byte[] oldHash, byte[] newHash, Guid correlationId,
        CancellationToken cancellationToken);
    Task RevokeSession(long userId, Guid sessionId, Guid correlationId, CancellationToken cancellationToken);
    Task<Profile?> GetProfile(long userId, CancellationToken cancellationToken);
    Task<IReadOnlyList<TenantSummary>> MyTenants(long userId, CancellationToken cancellationToken);
    Task<IReadOnlyList<OrganizationType>> OrganizationTypes(CancellationToken cancellationToken);
    Task<IReadOnlyList<TenantType>> TenantTypes(CancellationToken cancellationToken);
    Task<ConfigurationEntry?> GetConfiguration(string key, CancellationToken cancellationToken);
    Task<(long TenantId, long MembershipId)> CreateTenant(long userId, string code, string type, string name,
        long? organizationTypeId, string? registeredName, string requestId, Guid correlationId,
        CancellationToken cancellationToken);
    Task<long> Invite(long tenantId, long actorUserId, long inviteeUserId, string requestId,
        Guid correlationId, CancellationToken cancellationToken);
    Task Accept(long membershipId, long actorUserId, string requestId, Guid correlationId,
        CancellationToken cancellationToken);
    Task Remove(long membershipId, long actorUserId, string requestId, Guid correlationId,
        CancellationToken cancellationToken);
    Task AssignRole(long membershipId, long actorUserId, string roleCode, string requestId,
        Guid correlationId, CancellationToken cancellationToken);
    Task RevokeRole(long membershipId, long actorUserId, string roleCode, string requestId,
        Guid correlationId, CancellationToken cancellationToken);
    Task CheckDatabase(CancellationToken cancellationToken);
}

public interface IVerificationEmailSender
{
    Task Send(string email, long userId, string verificationCode, CancellationToken cancellationToken);
}

public interface IAccessTokenIssuer
{
    AccessResult Issue(long userId, Guid sessionId);
}
