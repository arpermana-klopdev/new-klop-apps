namespace KLOP.Platform.Application;

public static class SystemConfigurationPermissions
{
    public const string Read = "platform.configurations.read";
    public const string RequestCreate = "platform.configurations.request.create";
    public const string RequestEdit = "platform.configurations.request.edit";
    public const string Submit = "platform.configurations.request.submit";
    public const string Cancel = "platform.configurations.request.cancel";
    public const string Approve = "platform.configurations.approve";
    public const string Apply = "platform.configurations.apply";
    public const string History = "platform.configurations.history";

    public static readonly string[] All =
    [
        Read, RequestCreate, RequestEdit, Submit, Cancel, Approve, Apply, History
    ];
}

public sealed record SystemConfigurationCatalogItem(
    string ConfigurationKey,
    string Category,
    string ValueType,
    string StorageType,
    string Readiness,
    string ManagementStatus,
    bool IsEditable,
    bool RequiresApproval,
    bool RequiresRestart,
    int? VersionNumber,
    string? ConcurrencyVersion,
    DateTime? CreatedAtUtc,
    DateTime? UpdatedAtUtc,
    decimal? Minimum,
    decimal? Maximum);

public sealed record SystemConfigurationCatalogPage(
    IReadOnlyList<SystemConfigurationCatalogItem> Items,
    int PageNumber,
    int PageSize,
    long TotalCount,
    long UnclassifiedCount);

public sealed record SystemConfigurationRequestItem(
    Guid RequestId,
    string ConfigurationKey,
    string Status,
    int? ProposedInteger,
    int? ExpectedVersionNumber,
    string ReasonCode,
    DateTime CreatedAtUtc,
    DateTime? UpdatedAtUtc,
    string? RequestConcurrencyVersion);

public sealed record SystemConfigurationRequestPage(
    IReadOnlyList<SystemConfigurationRequestItem> Items,
    int PageNumber,
    int PageSize,
    long TotalCount);

public sealed record SystemConfigurationHistoryItem(
    long HistoryId,
    string ConfigurationKey,
    int VersionNumber,
    string ChangeType,
    int? AppliedInteger,
    string ReasonCode,
    DateTime OccurredAtUtc,
    long ActorUserId);

public sealed record SystemConfigurationHistoryPage(
    IReadOnlyList<SystemConfigurationHistoryItem> Items,
    int PageNumber,
    int PageSize,
    long TotalCount);

public sealed record SystemConfigurationDraftRequest(
    string ConfigurationKey,
    int ProposedInteger,
    int ExpectedVersionNumber,
    string TargetConcurrencyVersion,
    string ReasonCode);

public sealed record SystemConfigurationDraftUpdate(
    int ProposedInteger,
    string ReasonCode,
    string RequestConcurrencyVersion);

public sealed record SystemConfigurationTransitionRequest(string RequestConcurrencyVersion);
public sealed record SystemConfigurationDecisionRequest(string Decision, string RequestConcurrencyVersion);
public sealed record SystemConfigurationDraftResult(Guid RequestId, string RequestConcurrencyVersion);

public interface ISystemConfigurationRepository
{
    Task<SystemConfigurationCatalogPage> GetCatalog(
        string? category, int pageNumber, int pageSize,
        long actorUserId, Guid sessionId, CancellationToken cancellationToken);

    Task<SystemConfigurationRequestPage> GetRequests(
        string status, int pageNumber, int pageSize,
        long actorUserId, Guid sessionId, CancellationToken cancellationToken);

    Task<SystemConfigurationHistoryPage> GetHistory(
        int pageNumber, int pageSize, long actorUserId, Guid sessionId, CancellationToken cancellationToken);

    Task<SystemConfigurationDraftResult> CreateDraft(
        SystemConfigurationDraftRequest request, byte[] targetConcurrencyVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken);

    Task<SystemConfigurationDraftResult> UpdateDraft(
        Guid requestId, SystemConfigurationDraftUpdate request, byte[] requestConcurrencyVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken);

    Task<SystemConfigurationDraftResult> Transition(
        Guid requestId, string action, string? decision, byte[] requestConcurrencyVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken);

    Task<SystemConfigurationDraftResult> Apply(
        Guid requestId, byte[] requestConcurrencyVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken);
}

public sealed class SystemConfigurationCatalogRow
{
    public string ConfigurationKey { get; set; } = "";
    public string Category { get; set; } = "";
    public string ValueType { get; set; } = "";
    public string StorageType { get; set; } = "";
    public string Readiness { get; set; } = "";
    public string ManagementStatus { get; set; } = "";
    public bool IsEditable { get; set; }
    public bool RequiresApproval { get; set; }
    public bool RequiresRestart { get; set; }
    public int? VersionNumber { get; set; }
    public byte[]? ConcurrencyVersion { get; set; }
    public DateTime? CreatedAtUtc { get; set; }
    public DateTime? UpdatedAtUtc { get; set; }
    public decimal? Minimum { get; set; }
    public decimal? Maximum { get; set; }
}

public sealed class SystemConfigurationRequestRow
{
    public Guid RequestId { get; set; }
    public string ConfigurationKey { get; set; } = "";
    public string Status { get; set; } = "";
    public int? ProposedInteger { get; set; }
    public int? ExpectedVersionNumber { get; set; }
    public string ReasonCode { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; }
    public DateTime? UpdatedAtUtc { get; set; }
    public byte[]? RequestConcurrencyVersion { get; set; }
}

public sealed class SystemConfigurationHistoryRow
{
    public long HistoryId { get; set; }
    public string ConfigurationKey { get; set; } = "";
    public int VersionNumber { get; set; }
    public string ChangeType { get; set; } = "";
    public int? AppliedInteger { get; set; }
    public string ReasonCode { get; set; } = "";
    public DateTime OccurredAtUtc { get; set; }
    public long ActorUserId { get; set; }
}

public sealed class SystemConfigurationDraftDbRow
{
    public Guid RequestId { get; set; }
    public byte[] RequestConcurrencyVersion { get; set; } = [];
}
