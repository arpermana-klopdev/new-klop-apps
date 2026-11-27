using System.Data;
using Dapper;
using KLOP.Platform.Application;

namespace KLOP.Platform.Infrastructure;

public sealed partial class KlopRepository
{
    public Task<IReadOnlyList<NotificationTemplateSummary>> ListTemplates(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
        Many<NotificationTemplateSummary>("ntf.usp_ListTemplates",
            NotificationActorParameters(actorUserId, sessionId), cancellationToken);

    public Task<IReadOnlyList<NotificationTemplateVersion>> ListTemplateVersions(
        Guid templateId, long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
        Many<NotificationTemplateVersion>("ntf.usp_GetTemplate",
            NotificationParameters(actorUserId, sessionId, ("TemplateId", templateId, DbType.Guid)),
            cancellationToken);

    public Task<IReadOnlyList<NotificationTemplateVersion>> ListTemplateVersionsForPreview(
        Guid versionId, long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
        Many<NotificationTemplateVersion>("ntf.usp_GetTemplateVersionForPreview",
            NotificationVersionActorParameters(versionId, actorUserId, sessionId), cancellationToken);

    public Task<IReadOnlyList<NotificationChannelStatus>> ListChannels(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
        Many<NotificationChannelStatus>("ntf.usp_ListChannels",
            NotificationActorParameters(actorUserId, sessionId), cancellationToken);

    public Task<IReadOnlyList<NotificationDeliveryHistoryRow>> ListDeliveryHistory(
        int pageNumber, int pageSize, long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
        Many<NotificationDeliveryHistoryRow>("ntf.usp_ListDeliveryHistory",
            NotificationParameters(actorUserId, sessionId,
                ("PageNumber", pageNumber, DbType.Int32),
                ("PageSize", pageSize, DbType.Int32)), cancellationToken);

    public async Task<NotificationTemplateDraftResult> CreateDraft(
        string templateCode, string displayName, string channelCode, string localeCode,
        string subject, string body, long actorUserId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken)
    {
        var result = await One<NotificationTemplateDraftResult>("ntf.usp_CreateTemplateDraft",
            NotificationMetadataParameters(actorUserId, sessionId, metadata,
                ("TemplateCode", templateCode, DbType.AnsiString, 50),
                ("DisplayName", displayName, DbType.String, 200),
                ("ChannelCode", channelCode, DbType.AnsiString, 30),
                ("LocaleCode", localeCode, DbType.AnsiString, 20),
                ("Subject", subject, DbType.String, 300),
                ("Body", body, DbType.String, 20_000)), cancellationToken);
        return result ?? throw new InvalidOperationException("The notification draft procedure returned no result.");
    }

    public async Task<NotificationTemplateDraftResult> UpdateDraft(
        Guid versionId, string subject, string body, byte[] expectedVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var result = await One<NotificationTemplateDraftResult>("ntf.usp_UpdateTemplateDraft",
            NotificationMetadataParameters(actorUserId, sessionId, metadata,
                ("TemplateVersionId", versionId, DbType.Guid, 0),
                ("Subject", subject, DbType.String, 300),
                ("Body", body, DbType.String, 20_000),
                ("ExpectedVersion", expectedVersion, DbType.Binary, 8)), cancellationToken);
        return result ?? throw new InvalidOperationException("The notification draft procedure returned no result.");
    }

    public Task<IReadOnlyList<NotificationTemplateVersion>> TransitionVersion(
        Guid versionId, string action, string? decision, string? note, byte[] expectedVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) =>
        Many<NotificationTemplateVersion>("ntf.usp_TransitionTemplateVersion",
            NotificationMetadataParameters(actorUserId, sessionId, metadata,
                ("TemplateVersionId", versionId, DbType.Guid, 0),
                ("ActionCode", action, DbType.AnsiString, 20),
                ("DecisionCode", decision, DbType.AnsiString, 20),
                ("DecisionNote", note, DbType.String, 1000),
                ("ExpectedVersion", expectedVersion, DbType.Binary, 8)), cancellationToken);

    public async Task<NotificationTemplateVersion?> GetActiveVerificationVersion(
        CancellationToken cancellationToken)
    {
        using var connection = factory.Open();
        return await connection.QuerySingleOrDefaultAsync<NotificationTemplateVersion>(
            new CommandDefinition("ntf.usp_GetActiveVerificationTemplate", commandType: CommandType.StoredProcedure,
                commandTimeout: settings.CommandTimeoutSeconds, cancellationToken: cancellationToken));
    }

    public Task RecordDeliveryAttempt(
        Guid? templateVersionId, string templateCode, int? versionNumber, Guid correlationId,
        bool accepted, string? safeErrorCategory,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("TemplateVersionId", templateVersionId, DbType.Guid);
        parameters.Add("TemplateCodeSnapshot", templateCode, DbType.AnsiString, size: 50);
        parameters.Add("TemplateVersionSnapshot", versionNumber, DbType.Int32);
        parameters.Add("CorrelationId", correlationId, DbType.Guid);
        parameters.Add("ProviderAccepted", accepted, DbType.Boolean);
        parameters.Add("SafeErrorCategory", safeErrorCategory, DbType.AnsiString, size: 40);
        return Execute("ntf.usp_RecordDeliveryAttempt", parameters, cancellationToken);
    }

    private static DynamicParameters NotificationActorParameters(long actorUserId, Guid sessionId) =>
        NotificationParameters(actorUserId, sessionId);

    private static DynamicParameters NotificationParameters(long actorUserId, Guid sessionId,
        params (string Name, object? Value, DbType Type)[] values)
    {
        var parameters = new DynamicParameters();
        parameters.Add("ActorUserId", actorUserId, DbType.Int64);
        parameters.Add("PublicSessionId", sessionId, DbType.Guid);
        foreach (var (name, value, type) in values)
            parameters.Add(name, value, type);
        return parameters;
    }

    private static DynamicParameters NotificationMetadataParameters(
        long actorUserId, Guid sessionId, RequestMetadata metadata,
        params (string Name, object? Value, DbType Type, int Size)[] values)
    {
        var parameters = NotificationParameters(actorUserId, sessionId);
        foreach (var (name, value, type, size) in values)
            parameters.Add(name, value, type, size: size);
        parameters.Add("RequestId", metadata.RequestId, DbType.AnsiString, size: 100);
        parameters.Add("CorrelationId", metadata.CorrelationId, DbType.Guid);
        return parameters;
    }

    private static DynamicParameters NotificationVersionActorParameters(
        Guid versionId, long actorUserId, Guid sessionId)
    {
        var parameters = NotificationParameters(actorUserId, sessionId);
        parameters.Add("TemplateVersionId", versionId, DbType.Guid);
        return parameters;
    }
}
