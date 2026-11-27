namespace KLOP.Platform.Application;

public static class RolePermissionMatrixPermissions
{
    public const string Read = "platform.role_permissions.read";
    public const string Update = "platform.role_permissions.update";
}

public sealed record RolePermissionMatrixColumn(
    long RoleId,
    string RoleCode,
    string RoleName,
    string ScopeCode,
    long? TenantTypeId,
    string? TenantTypeCode,
    bool IsAssignable);

public sealed record RolePermissionMatrixCell(
    long RoleId,
    string RoleCode,
    string ScopeCode,
    long? TenantTypeId,
    string? TenantTypeCode,
    bool ConfiguredGrant,
    bool? EffectiveAllowed,
    bool IsEditable,
    string? RestrictionReason,
    string? ConcurrencyVersion);

public sealed record AccountPermissionPolicy(
    bool PublicAllowed,
    bool UnverifiedAllowed,
    bool VerifiedAllowed);

public sealed record RolePermissionMatrixRow(
    long? PermissionId,
    string Module,
    string Resource,
    string Action,
    string PermissionCode,
    string PermissionName,
    string PermissionDescription,
    string ScopeCode,
    string ReadinessStatus,
    bool IsAccountPolicy,
    AccountPermissionPolicy? AccountPolicy,
    IReadOnlyList<RolePermissionMatrixCell> Cells);

public sealed record RolePermissionMatrixResponse(
    IReadOnlyList<RolePermissionMatrixColumn> Columns,
    IReadOnlyList<RolePermissionMatrixRow> Rows);

public sealed record RolePermissionMatrixAccessResponse(bool CanRead, bool CanUpdate);

public sealed record RolePermissionMatrixChange(
    long PermissionId,
    long RoleId,
    long? TenantTypeId,
    bool IsGranted,
    string? ConcurrencyVersion);

public sealed record RolePermissionMatrixBatchRequest(
    string Reason,
    IReadOnlyList<RolePermissionMatrixChange> Changes);

public sealed record RolePermissionMatrixValidationIssue(
    int ChangeIndex,
    string? PermissionCode,
    string Code,
    string Message);

public sealed record RolePermissionMatrixValidationResponse(
    bool IsValid,
    IReadOnlyList<RolePermissionMatrixValidationIssue> Issues);

public sealed record RolePermissionMatrixSaveResponse(
    int ChangedCount,
    DateTime SavedAtUtc);

public sealed record RolePermissionMatrixHistoryEntry(
    long AuditEventId,
    string PermissionCode,
    string RoleCode,
    string ScopeCode,
    string? TenantTypeCode,
    bool PreviousGrant,
    bool NewGrant,
    string ChangeReason,
    string? ActorDisplayName,
    DateTime OccurredAtUtc,
    string? CorrelationId,
    string Outcome);

public interface IRolePermissionMatrixRepository
{
    Task<IReadOnlyList<RolePermissionMatrixDbRow>> GetRolePermissionMatrix(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken);

    Task<IReadOnlyList<RolePermissionMatrixValidationDbRow>> ValidateRolePermissionBatch(
        long actorUserId, Guid sessionId, string reason, string changesJson,
        CancellationToken cancellationToken);

    Task<RolePermissionMatrixSaveDbRow?> SaveRolePermissionBatch(
        long actorUserId, Guid sessionId, string reason, string changesJson,
        RequestMetadata metadata, CancellationToken cancellationToken);

    Task<IReadOnlyList<RolePermissionMatrixHistoryDbRow>> GetRolePermissionHistory(
        long actorUserId, Guid sessionId, int pageNumber, int pageSize,
        CancellationToken cancellationToken);
}

public sealed class RolePermissionMatrixDbRow
{
    public long? PermissionId { get; set; }
    public string Module { get; set; } = "";
    public string Resource { get; set; } = "";
    public string Action { get; set; } = "";
    public string PermissionCode { get; set; } = "";
    public string PermissionName { get; set; } = "";
    public string PermissionDescription { get; set; } = "";
    public string ScopeCode { get; set; } = "";
    public string ReadinessStatus { get; set; } = "";
    public bool IsAccountPolicy { get; set; }
    public bool? PublicAllowed { get; set; }
    public bool? UnverifiedAllowed { get; set; }
    public bool? VerifiedAllowed { get; set; }
    public long? RoleId { get; set; }
    public string? RoleCode { get; set; }
    public string? RoleName { get; set; }
    public string? RoleScopeCode { get; set; }
    public long? TenantTypeId { get; set; }
    public string? TenantTypeCode { get; set; }
    public bool? IsAssignable { get; set; }
    public bool? ConfiguredGrant { get; set; }
    public bool? EffectiveAllowed { get; set; }
    public bool? IsEditable { get; set; }
    public string? RestrictionReason { get; set; }
    public byte[]? ConcurrencyVersion { get; set; }
}

public sealed class RolePermissionMatrixValidationDbRow
{
    public int ChangeIndex { get; set; }
    public string? PermissionCode { get; set; }
    public string Code { get; set; } = "";
    public string Message { get; set; } = "";
}

public sealed class RolePermissionMatrixSaveDbRow
{
    public int ChangedCount { get; set; }
    public DateTime SavedAtUtc { get; set; }
}

public sealed class RolePermissionMatrixHistoryDbRow
{
    public long AuditEventId { get; set; }
    public string PermissionCode { get; set; } = "";
    public string RoleCode { get; set; } = "";
    public string ScopeCode { get; set; } = "";
    public string? TenantTypeCode { get; set; }
    public bool PreviousGrant { get; set; }
    public bool NewGrant { get; set; }
    public string ChangeReason { get; set; } = "";
    public string? ActorDisplayName { get; set; }
    public DateTime OccurredAtUtc { get; set; }
    public string? CorrelationId { get; set; }
    public string Outcome { get; set; } = "";
}
