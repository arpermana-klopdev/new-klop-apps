using System.Data;
using Dapper;
using KLOP.Platform.Application;

namespace KLOP.Platform.Infrastructure;

public sealed partial class KlopRepository
{
    public async Task<SystemConfigurationCatalogPage> GetCatalog(
        string? category, int pageNumber, int pageSize,
        long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        using var connection = factory.Open();
        using var results = await connection.QueryMultipleAsync(new CommandDefinition(
            "cfg.usp_ConfigurationManagement_ListCatalog",
            ConfigurationParameters(actorUserId, sessionId,
                ("Category", category, DbType.AnsiString, 80),
                ("PageNumber", pageNumber, DbType.Int32, 0),
                ("PageSize", pageSize, DbType.Int32, 0)),
            commandType: CommandType.StoredProcedure,
            commandTimeout: settings.CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        var counts = await results.ReadSingleAsync<SystemConfigurationCatalogCountRow>();
        var rows = (await results.ReadAsync<SystemConfigurationCatalogRow>()).ToArray();
        return new SystemConfigurationCatalogPage(rows.Select(row => new SystemConfigurationCatalogItem(
            row.ConfigurationKey, row.Category, row.ValueType, row.StorageType, row.Readiness,
            row.ManagementStatus,
            row.IsEditable, row.RequiresApproval, row.RequiresRestart, row.VersionNumber,
            row.ConcurrencyVersion is null ? null : Convert.ToBase64String(row.ConcurrencyVersion),
            row.CreatedAtUtc, row.UpdatedAtUtc, row.Minimum, row.Maximum)).ToArray(),
            pageNumber, pageSize, counts.TotalCount, counts.UnclassifiedCount);
    }

    public async Task<SystemConfigurationRequestPage> GetRequests(
        string status, int pageNumber, int pageSize,
        long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        using var connection = factory.Open();
        using var results = await connection.QueryMultipleAsync(new CommandDefinition(
            "cfg.usp_ConfigurationManagement_ListRequests",
            ConfigurationParameters(actorUserId, sessionId,
                ("Status", status, DbType.AnsiString, 20),
                ("PageNumber", pageNumber, DbType.Int32, 0),
                ("PageSize", pageSize, DbType.Int32, 0)),
            commandType: CommandType.StoredProcedure,
            commandTimeout: settings.CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        var count = await results.ReadSingleAsync<long>();
        var rows = (await results.ReadAsync<SystemConfigurationRequestRow>()).ToArray();
        return new SystemConfigurationRequestPage(rows.Select(row => new SystemConfigurationRequestItem(
            row.RequestId, row.ConfigurationKey, row.Status, row.ProposedInteger, row.ExpectedVersionNumber,
            row.ReasonCode, row.CreatedAtUtc, row.UpdatedAtUtc,
            row.RequestConcurrencyVersion is null ? null : Convert.ToBase64String(row.RequestConcurrencyVersion)))
            .ToArray(), pageNumber, pageSize, count);
    }

    public async Task<SystemConfigurationHistoryPage> GetHistory(
        int pageNumber, int pageSize, long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        using var connection = factory.Open();
        using var results = await connection.QueryMultipleAsync(new CommandDefinition(
            "cfg.usp_ConfigurationManagement_ListHistory",
            ConfigurationParameters(actorUserId, sessionId,
                ("PageNumber", pageNumber, DbType.Int32, 0),
                ("PageSize", pageSize, DbType.Int32, 0)),
            commandType: CommandType.StoredProcedure,
            commandTimeout: settings.CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        var count = await results.ReadSingleAsync<long>();
        var rows = (await results.ReadAsync<SystemConfigurationHistoryRow>()).ToArray();
        return new SystemConfigurationHistoryPage(rows.Select(row => new SystemConfigurationHistoryItem(
            row.HistoryId, row.ConfigurationKey, row.VersionNumber, row.ChangeType, row.AppliedInteger,
            row.ReasonCode, row.OccurredAtUtc, row.ActorUserId)).ToArray(), pageNumber, pageSize, count);
    }

    public Task<SystemConfigurationDraftResult> CreateDraft(
        SystemConfigurationDraftRequest request, byte[] targetConcurrencyVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) =>
        ConfigurationMutation("cfg.usp_ConfigurationManagement_CreateDraft",
            ConfigurationMetadataParameters(actorUserId, sessionId, metadata,
                ("ConfigurationKey", request.ConfigurationKey, DbType.AnsiString, 150),
                ("ProposedInteger", request.ProposedInteger, DbType.Int32, 0),
                ("ExpectedVersionNumber", request.ExpectedVersionNumber, DbType.Int32, 0),
                ("ExpectedTargetRowVersion", targetConcurrencyVersion, DbType.Binary, 8),
                ("ReasonCode", request.ReasonCode, DbType.AnsiString, 40)),
            cancellationToken);

    public Task<SystemConfigurationDraftResult> UpdateDraft(
        Guid requestId, SystemConfigurationDraftUpdate request, byte[] requestConcurrencyVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) =>
        ConfigurationMutation("cfg.usp_ConfigurationManagement_UpdateDraft",
            ConfigurationMetadataParameters(actorUserId, sessionId, metadata,
                ("RequestId", requestId, DbType.Guid, 0),
                ("ProposedInteger", request.ProposedInteger, DbType.Int32, 0),
                ("ReasonCode", request.ReasonCode, DbType.AnsiString, 40),
                ("ExpectedRequestRowVersion", requestConcurrencyVersion, DbType.Binary, 8)),
            cancellationToken);

    public Task<SystemConfigurationDraftResult> Transition(
        Guid requestId, string action, string? decision, byte[] requestConcurrencyVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) =>
        ConfigurationMutation("cfg.usp_ConfigurationManagement_Transition",
            ConfigurationMetadataParameters(actorUserId, sessionId, metadata,
                ("RequestId", requestId, DbType.Guid, 0),
                ("ActionCode", action, DbType.AnsiString, 20),
                ("DecisionCode", decision, DbType.AnsiString, 20),
                ("ExpectedRequestRowVersion", requestConcurrencyVersion, DbType.Binary, 8)),
            cancellationToken);

    public Task<SystemConfigurationDraftResult> Apply(
        Guid requestId, byte[] requestConcurrencyVersion,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) =>
        ConfigurationMutation("cfg.usp_ConfigurationManagement_Apply",
            ConfigurationMetadataParameters(actorUserId, sessionId, metadata,
                ("RequestId", requestId, DbType.Guid, 0),
                ("ExpectedRequestRowVersion", requestConcurrencyVersion, DbType.Binary, 8)),
            cancellationToken);

    private async Task<SystemConfigurationDraftResult> ConfigurationMutation(
        string procedure, DynamicParameters parameters, CancellationToken cancellationToken)
    {
        var result = await One<SystemConfigurationDraftDbRow>(procedure, parameters, cancellationToken);
        return result is null
            ? throw new InvalidOperationException("The configuration procedure returned no result.")
            : new SystemConfigurationDraftResult(result.RequestId,
                Convert.ToBase64String(result.RequestConcurrencyVersion));
    }

    private static DynamicParameters ConfigurationParameters(
        long actorUserId, Guid sessionId, params (string Name, object? Value, DbType Type, int Size)[] values)
    {
        var parameters = new DynamicParameters();
        parameters.Add("ActorUserId", actorUserId, DbType.Int64);
        parameters.Add("PublicSessionId", sessionId, DbType.Guid);
        foreach (var (name, value, type, size) in values)
            parameters.Add(name, value, type, size: size == 0 ? null : size);
        return parameters;
    }

    private static DynamicParameters ConfigurationMetadataParameters(
        long actorUserId, Guid sessionId, RequestMetadata metadata,
        params (string Name, object? Value, DbType Type, int Size)[] values)
    {
        var parameters = ConfigurationParameters(actorUserId, sessionId, values);
        parameters.Add("RequestIdHeader", metadata.RequestId, DbType.AnsiString, size: 100);
        parameters.Add("CorrelationId", metadata.CorrelationId, DbType.Guid);
        return parameters;
    }

    private sealed class SystemConfigurationCatalogCountRow
    {
        public long TotalCount { get; set; }
        public long UnclassifiedCount { get; set; }
    }
}
