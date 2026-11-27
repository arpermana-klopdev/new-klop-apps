namespace KLOP.Platform.Application;

public static class NotificationPermissions
{
    public const string Read = "platform.notifications.read";
    public const string DraftCreate = "platform.notifications.draft.create";
    public const string DraftEdit = "platform.notifications.draft.edit";
    public const string Preview = "platform.notifications.draft.preview";
    public const string Submit = "platform.notifications.submit";
    public const string Approve = "platform.notifications.approve";
    public const string Activate = "platform.notifications.activate";
    public const string Archive = "platform.notifications.archive";
    public const string History = "platform.notifications.history";
    public const string SettingsRead = "platform.notifications.settings.read";

    public static readonly string[] All =
    [
        Read, DraftCreate, DraftEdit, Preview, Submit, Approve, Activate, Archive, History, SettingsRead
    ];
}

public sealed record NotificationPermissionsResponse(IReadOnlyList<string> Permissions);

public sealed record NotificationTemplateSummary(
    Guid TemplateId,
    string TemplateCode,
    string DisplayName,
    string ChannelCode,
    string LocaleCode,
    Guid? ActiveVersionId,
    int? ActiveVersionNumber,
    string? ActiveVersionStatus,
    byte[] ConcurrencyVersion);

public sealed record NotificationTemplateVersion(
    Guid VersionId,
    string TemplateCode,
    string DisplayName,
    int VersionNumber,
    string Status,
    string Subject,
    string Body,
    string ChannelCode,
    string LocaleCode,
    DateTime CreatedAtUtc,
    byte[] ConcurrencyVersion);

public sealed record NotificationTemplateDetail(
    Guid TemplateId,
    string TemplateCode,
    string DisplayName,
    IReadOnlyList<NotificationTemplateVersion> Versions);

public sealed record NotificationTemplateDraftRequest(
    string Subject,
    string Body,
    string ConcurrencyVersion);

public sealed record NotificationTemplatePreviewResponse(string Subject, string Body);
public sealed record NotificationDecisionRequest(string Decision, string? Note, string ConcurrencyVersion);

public sealed record NotificationChannelStatus(
    string ChannelCode,
    string DisplayName,
    string Status,
    bool IsEnabled,
    string Readiness);

public sealed record NotificationSettingsReadiness(
    bool SmtpHostConfigured,
    bool SmtpPortConfigured,
    bool SenderConfigured,
    bool TlsRequired,
    bool CredentialsConfigured,
    bool TemplateRolloutEnabled,
    bool DeliveryAuditEnabled,
    string VerificationLifetimeStatus);

public sealed record NotificationDeliveryHistoryItem(
    long AttemptId,
    Guid DeliveryId,
    string TemplateCode,
    string TemplateVersion,
    string ChannelCode,
    string Outcome,
    string? SafeErrorCategory,
    DateTime OccurredAtUtc,
    Guid CorrelationId);

public sealed record NotificationDeliveryHistoryPage(
    IReadOnlyList<NotificationDeliveryHistoryItem> Items,
    int PageNumber,
    int PageSize,
    long TotalCount);

public sealed record NotificationTemplateDraftResult(Guid TemplateId, Guid VersionId);
public sealed record NotificationDeliveryHistoryRow(
    long AttemptId,
    Guid DeliveryId,
    string TemplateCode,
    string TemplateVersion,
    string ChannelCode,
    string Outcome,
    string? SafeErrorCategory,
    DateTime OccurredAtUtc,
    Guid CorrelationId);

public interface INotificationManagementRepository
{
    Task<IReadOnlyList<NotificationTemplateSummary>> ListTemplates(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken);
    Task<IReadOnlyList<NotificationTemplateVersion>> ListTemplateVersions(
        Guid templateId, long actorUserId, Guid sessionId, CancellationToken cancellationToken);
    Task<IReadOnlyList<NotificationTemplateVersion>> ListTemplateVersionsForPreview(
        Guid versionId, long actorUserId, Guid sessionId, CancellationToken cancellationToken);
    Task<IReadOnlyList<NotificationChannelStatus>> ListChannels(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken);
    Task<NotificationDeliveryHistoryPage> ListDeliveryHistory(
        int pageNumber, int pageSize, long actorUserId, Guid sessionId, CancellationToken cancellationToken);
    Task<NotificationTemplateDraftResult> CreateDraft(
        string templateCode, string displayName, string channelCode, string localeCode,
        string subject, string body, long actorUserId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken);
    Task<NotificationTemplateDraftResult> UpdateDraft(
        Guid versionId, string subject, string body, byte[] expectedVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken);
    Task<IReadOnlyList<NotificationTemplateVersion>> TransitionVersion(
        Guid versionId, string action, string? decision, string? note, byte[] expectedVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken);
    Task<NotificationTemplateVersion?> GetActiveVerificationVersion(CancellationToken cancellationToken);
    Task RecordDeliveryAttempt(
        Guid? templateVersionId, string templateCode, int? versionNumber, Guid correlationId,
        bool accepted, string? safeErrorCategory,
        CancellationToken cancellationToken);
}
