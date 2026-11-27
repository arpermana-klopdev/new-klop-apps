namespace KLOP.Platform.Application;

public static class PlatformRegistrationPermissions
{
    public const string Read = "platform.registrations.read";
}

public sealed record PlatformRegistrationPermissionsResponse(IReadOnlyList<string> Permissions);

public sealed class PlatformRegistrationSummary
{
    public string RegistrationType { get; set; } = "";
    public long TotalRegistrations { get; set; }
    public long PendingEmailVerification { get; set; }
    public long EmailVerified { get; set; }
    public long PendingReview { get; set; }
}

public sealed class PlatformRegistrationListQuery
{
    public string RegistrationType { get; set; } = "";
    public string? Search { get; set; }
    public string? EmailVerificationStatus { get; set; }
    public string? ApplicationStatus { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 20;
}

public sealed class PlatformRegistrationListRow
{
    public long TotalCount { get; set; }
    public int TotalPages { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public string ApplicationStatusesJson { get; set; } = "[]";
    public long? RegistrationApplicationId { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public DateTime? EmailVerifiedAtUtc { get; set; }
    public string? ApplicationStatus { get; set; }
    public string? RegistrationType { get; set; }
    public DateTime? RegisteredAtUtc { get; set; }
}

public sealed record PlatformRegistrationListItem(
    long RegistrationApplicationId,
    string DisplayName,
    string Email,
    DateTime? EmailVerifiedAtUtc,
    string ApplicationStatus,
    string RegistrationType,
    DateTime RegisteredAtUtc);

public sealed record PlatformRegistrationPage(
    IReadOnlyList<PlatformRegistrationListItem> Items,
    int PageNumber,
    int PageSize,
    long TotalCount,
    int TotalPages,
    IReadOnlyList<string> ApplicationStatuses);

public sealed class PlatformRegistrationDetailRow
{
    public long RegistrationApplicationId { get; set; }
    public string DisplayName { get; set; } = "";
    public string Email { get; set; } = "";
    public bool IsActive { get; set; }
    public DateTime UserRegisteredAtUtc { get; set; }
    public DateTime? EmailVerifiedAtUtc { get; set; }
    public string RegistrationType { get; set; } = "";
    public string ApplicationStatus { get; set; } = "";
    public DateTime ApplicationCreatedAtUtc { get; set; }
    public DateTime ApplicationUpdatedAtUtc { get; set; }
    public long? TenantId { get; set; }
    public string? PersonalPhoneNumber { get; set; }
    public string? PersonalCountryCode { get; set; }
    public string? PersonalRegion { get; set; }
    public string? PersonalCity { get; set; }
    public string? PersonalPostalCode { get; set; }
    public string? PersonalAddressLine { get; set; }
    public string? OrganizationType { get; set; }
    public string? OrganizationCountryCode { get; set; }
    public string? OrganizationRegisteredName { get; set; }
    public string? OrganizationContactEmail { get; set; }
    public string? OrganizationContactPhone { get; set; }
    public string? OrganizationRegion { get; set; }
    public string? OrganizationCity { get; set; }
    public string? OrganizationPostalCode { get; set; }
    public string? OrganizationAddressLine { get; set; }
    public DateTime? LatestChallengeIssuedAtUtc { get; set; }
    public DateTime? LatestChallengeExpiresAtUtc { get; set; }
    public string? TenantCode { get; set; }
    public string? TenantType { get; set; }
    public string? TenantDisplayName { get; set; }
    public string? TenantStatus { get; set; }
}

public sealed record PlatformPersonalRegistrationProfile(
    string? PhoneNumber,
    string? CountryCode,
    string? Region,
    string? City,
    string? PostalCode,
    string? AddressLine);

public sealed record PlatformOrganizationRegistrationProfile(
    string? OrganizationType,
    string? CountryCode,
    string? RegisteredName,
    string? ContactEmail,
    string? ContactPhone,
    string? Region,
    string? City,
    string? PostalCode,
    string? AddressLine);

public sealed record PlatformRegistrationProfile(
    string? CompletionStatus,
    PlatformPersonalRegistrationProfile? Personal,
    PlatformOrganizationRegistrationProfile? Organization);

public sealed record PlatformRegistrationUser(
    string DisplayName,
    string Email,
    string AccountStatus,
    DateTime RegisteredAtUtc,
    DateTime? EmailVerifiedAtUtc);

public sealed record PlatformRegistrationApplication(
    string RegistrationType,
    string ApplicationStatus,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    long? TenantId);

public sealed record PlatformRegistrationChallenge(
    DateTime? IssuedAtUtc,
    DateTime? ExpiresAtUtc);

public sealed record PlatformRegistrationTenant(
    long TenantId,
    string TenantCode,
    string TenantType,
    string DisplayName,
    string Status);

public sealed record PlatformRegistrationDetail(
    long RegistrationApplicationId,
    PlatformRegistrationUser User,
    PlatformRegistrationApplication Application,
    PlatformRegistrationProfile Profile,
    PlatformRegistrationChallenge? LatestVerificationChallenge,
    PlatformRegistrationTenant? Tenant);

public sealed class PlatformRegistrationTimelineRow
{
    public DateTime OccurredAtUtc { get; set; }
    public string EventCode { get; set; } = "";
    public string? FromStatus { get; set; }
    public string? ToStatus { get; set; }
    public string? ActorDisplayName { get; set; }
}

public sealed record PlatformRegistrationTimelineEvent(
    DateTime OccurredAtUtc,
    string EventCode,
    string? FromStatus,
    string? ToStatus,
    string? ActorDisplayName);

public interface IPlatformRegistrationRepository
{
    Task<PlatformRegistrationSummary?> GetPlatformRegistrationSummary(
        string registrationType, long actorUserId, Guid sessionId, CancellationToken cancellationToken);

    Task<PlatformRegistrationPage> ListPlatformRegistrations(
        PlatformRegistrationListQuery query, long actorUserId, Guid sessionId,
        CancellationToken cancellationToken);

    Task<PlatformRegistrationDetailRow?> GetPlatformRegistration(
        long registrationApplicationId, long actorUserId, Guid sessionId,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<PlatformRegistrationTimelineEvent>> GetPlatformRegistrationTimeline(
        long registrationApplicationId, long actorUserId, Guid sessionId,
        CancellationToken cancellationToken);
}
