namespace KLOP.Platform.Domain;

public sealed class LoginCandidate
{
    public long UserId { get; set; }
    public string DisplayName { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public bool IsActive { get; set; }
    public DateTime? EmailVerifiedAtUtc { get; set; }
    public DateTime? LockoutUntilUtc { get; set; }
}
public sealed class Profile
{
    public long UserId { get; set; }
    public string Email { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public DateTime? EmailVerifiedAtUtc { get; set; }
}
public sealed class TenantSummary
{
    public long TenantId { get; set; }
    public string TenantCode { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string TenantTypeCode { get; set; } = "";
    public string TenantStatusCode { get; set; } = "";
    public long MembershipId { get; set; }
    public string MembershipStatusCode { get; set; } = "";
}
public sealed class OrganizationType
{
    public long OrganizationTypeId { get; set; }
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public string CountryCode { get; set; } = "";
}
