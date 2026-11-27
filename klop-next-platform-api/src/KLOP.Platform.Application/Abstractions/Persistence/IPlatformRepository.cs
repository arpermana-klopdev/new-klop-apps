using KLOP.Platform.Domain;

namespace KLOP.Platform.Application;

public interface IPlatformRepository : ITenantPermissionRepository
{
    Task<(long UserId, long ChallengeId)> Register(string email, string displayName, string passwordHash,
        byte[] tokenHash, string requestId, Guid correlationId, string? registrationTypeCode,
        Guid? termsDocumentVersionId, bool? termsAccepted, bool developmentTermsBypassEnabled,
        CancellationToken cancellationToken);
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