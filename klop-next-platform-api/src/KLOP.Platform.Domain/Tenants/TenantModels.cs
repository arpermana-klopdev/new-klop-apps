namespace KLOP.Platform.Domain;

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

public sealed class TenantType
{
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public bool AllowMultipleMembers { get; set; }
    public bool IsActive { get; set; }
}