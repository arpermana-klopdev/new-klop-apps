using System.Text.Json;

namespace KLOP.Platform.Application;

public sealed class RolePermissionMatrixService(
    IRolePermissionMatrixRepository repository,
    IPlatformPermissionRepository permissionRepository)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<RolePermissionMatrixResponse> Get(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        var rows = await repository.GetRolePermissionMatrix(actorUserId, sessionId, cancellationToken);
        var columns = rows
            .Where(row => row.RoleId.HasValue && row.RoleCode is not null && row.RoleName is not null &&
                          row.RoleScopeCode is not null)
            .Select(row => new RolePermissionMatrixColumn(
                row.RoleId!.Value, row.RoleCode!, row.RoleName!, row.RoleScopeCode!,
                row.TenantTypeId, row.TenantTypeCode, row.IsAssignable ?? false))
            .Distinct()
            .OrderBy(column => ScopeOrder(column.ScopeCode))
            .ThenBy(column => column.TenantTypeCode, StringComparer.Ordinal)
            .ThenBy(column => column.RoleId)
            .ToArray();

        var permissions = rows
            .GroupBy(row => row.PermissionCode, StringComparer.Ordinal)
            .Select(group =>
            {
                var first = group.First();
                var accountPolicy = first.IsAccountPolicy
                    ? new AccountPermissionPolicy(first.PublicAllowed ?? false,
                        first.UnverifiedAllowed ?? false, first.VerifiedAllowed ?? false)
                    : null;
                var cells = group
                    .Where(row => row.RoleId.HasValue && row.RoleCode is not null &&
                                  row.RoleScopeCode is not null)
                    .Select(row => new RolePermissionMatrixCell(
                        row.RoleId!.Value,
                        row.RoleCode!,
                        row.RoleScopeCode!,
                        row.TenantTypeId,
                        row.TenantTypeCode,
                        row.ConfiguredGrant ?? false,
                        row.EffectiveAllowed,
                        row.IsEditable ?? false,
                        row.RestrictionReason,
                        row.ConcurrencyVersion is null ? null : Convert.ToBase64String(row.ConcurrencyVersion)))
                    .ToArray();

                return new RolePermissionMatrixRow(first.PermissionId, first.Module, first.Resource,
                    first.Action, first.PermissionCode, first.PermissionName, first.PermissionDescription,
                    first.ScopeCode, first.ReadinessStatus, first.IsAccountPolicy, accountPolicy, cells);
            })
            .OrderBy(row => row.Module, StringComparer.Ordinal)
            .ThenBy(row => row.Resource, StringComparer.Ordinal)
            .ThenBy(row => row.PermissionCode, StringComparer.Ordinal)
            .ToArray();

        return new RolePermissionMatrixResponse(columns, permissions);
    }

    public async Task<RolePermissionMatrixAccessResponse> GetAccess(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        var permissions = await permissionRepository.GetPlatformPermissions(
            actorUserId, sessionId, cancellationToken);
        return new RolePermissionMatrixAccessResponse(
            permissions.Contains(RolePermissionMatrixPermissions.Read, StringComparer.Ordinal),
            permissions.Contains(RolePermissionMatrixPermissions.Update, StringComparer.Ordinal));
    }

    public async Task<RolePermissionMatrixValidationResponse> Validate(
        long actorUserId, Guid sessionId, RolePermissionMatrixBatchRequest request,
        CancellationToken cancellationToken)
    {
        ValidateRequest(request);
        var json = SerializeChanges(request.Changes);
        var issues = await repository.ValidateRolePermissionBatch(actorUserId, sessionId,
            request.Reason.Trim(), json, cancellationToken);
        return new RolePermissionMatrixValidationResponse(
            issues.Count == 0,
            issues.Select(issue => new RolePermissionMatrixValidationIssue(
                issue.ChangeIndex, issue.PermissionCode, issue.Code, issue.Message)).ToArray());
    }

    public async Task<RolePermissionMatrixSaveResponse> Save(
        long actorUserId, Guid sessionId, RolePermissionMatrixBatchRequest request,
        RequestMetadata metadata, CancellationToken cancellationToken)
    {
        ValidateRequest(request);
        var json = SerializeChanges(request.Changes);
        var result = await repository.SaveRolePermissionBatch(actorUserId, sessionId,
            request.Reason.Trim(), json, metadata, cancellationToken);
        return result is null
            ? throw new InvalidOperationException("The permission batch save returned no result.")
            : new RolePermissionMatrixSaveResponse(result.ChangedCount,
                DateTime.SpecifyKind(result.SavedAtUtc, DateTimeKind.Utc));
    }

    public async Task<IReadOnlyList<RolePermissionMatrixHistoryEntry>> History(
        long actorUserId, Guid sessionId, int pageNumber, int pageSize,
        CancellationToken cancellationToken)
    {
        if (pageNumber is < 1 or > 100_000 || pageSize is < 1 or > 100)
            throw new ArgumentOutOfRangeException(nameof(pageNumber), "The history page request is invalid.");

        var rows = await repository.GetRolePermissionHistory(actorUserId, sessionId,
            pageNumber, pageSize, cancellationToken);
        return rows.Select(row => new RolePermissionMatrixHistoryEntry(
            row.AuditEventId, row.PermissionCode, row.RoleCode, row.ScopeCode, row.TenantTypeCode,
            row.PreviousGrant, row.NewGrant, row.ChangeReason, row.ActorDisplayName,
            DateTime.SpecifyKind(row.OccurredAtUtc, DateTimeKind.Utc), row.CorrelationId, row.Outcome))
            .ToArray();
    }

    private static int ScopeOrder(string scopeCode) => scopeCode switch
    {
        "PLATFORM" => 0,
        "TENANT" => 1,
        _ => 2
    };

    private static string SerializeChanges(IReadOnlyList<RolePermissionMatrixChange> changes) =>
        JsonSerializer.Serialize(changes.Select(change => new
        {
            change.PermissionId,
            change.RoleId,
            change.TenantTypeId,
            change.IsGranted,
            ConcurrencyVersion = change.ConcurrencyVersion is null
                ? null
                : $"0x{Convert.ToHexString(Convert.FromBase64String(change.ConcurrencyVersion))}"
        }), JsonOptions);

    private static void ValidateRequest(RolePermissionMatrixBatchRequest request)
    {
        if (request is null)
            throw new ArgumentNullException(nameof(request));
        if (string.IsNullOrWhiteSpace(request.Reason) || request.Reason.Trim().Length is < 10 or > 500)
            throw new ArgumentException("A change reason between 10 and 500 characters is required.", nameof(request));
        if (request.Changes is null || request.Changes.Count is < 1 or > 100)
            throw new ArgumentException("A batch must contain between 1 and 100 changes.", nameof(request));
        if (request.Changes.Any(change =>
                change.PermissionId <= 0 || change.RoleId <= 0 ||
                change.TenantTypeId is <= 0 ||
                (change.ConcurrencyVersion is not null &&
                 !IsValidConcurrencyVersion(change.ConcurrencyVersion))))
            throw new ArgumentException("One or more permission changes are invalid.", nameof(request));
        if (request.Changes
            .Select(change => (change.PermissionId, change.RoleId, change.TenantTypeId))
            .Distinct()
            .Count() != request.Changes.Count)
            throw new ArgumentException("A permission cell may occur only once in a batch.", nameof(request));
    }

    private static bool IsValidConcurrencyVersion(string value)
    {
        var buffer = new byte[8];
        return Convert.TryFromBase64String(value, buffer, out var bytesWritten) && bytesWritten == buffer.Length;
    }
}
