namespace KLOP.Platform.Application;

public sealed class SystemConfigurationService(
    ISystemConfigurationRepository repository,
    IPlatformPermissionRepository permissions)
{
    public async Task<SystemConfigurationCatalogPage> Catalog(
        string? category, int pageNumber, int pageSize,
        long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        ValidatePage(pageNumber, pageSize);
        if (category is { Length: > 80 })
            throw new ArgumentException("The catalog filter is invalid.");
        await permissions.ValidatePlatformPermission(actorUserId, sessionId,
            SystemConfigurationPermissions.Read, cancellationToken);
        var page = await repository.GetCatalog(category?.Trim(), pageNumber, pageSize,
            actorUserId, sessionId, cancellationToken);
        return page with
        {
            Items = page.Items.Select(item => item with
            {
                CreatedAtUtc = item.CreatedAtUtc is null ? null : DateTime.SpecifyKind(item.CreatedAtUtc.Value, DateTimeKind.Utc),
                UpdatedAtUtc = item.UpdatedAtUtc is null ? null : DateTime.SpecifyKind(item.UpdatedAtUtc.Value, DateTimeKind.Utc)
            }).ToArray()
        };
    }

    public async Task<SystemConfigurationRequestPage> Requests(
        string status, int pageNumber, int pageSize,
        long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        ValidatePage(pageNumber, pageSize);
        var normalizedStatus = status.Trim().ToUpperInvariant();
        if (normalizedStatus is not ("ALL" or "DRAFT" or "SUBMITTED" or "APPROVED" or "REJECTED" or "CANCELED" or "APPLIED"))
            throw new ArgumentException("The request status filter is invalid.");
        await permissions.ValidatePlatformPermission(actorUserId, sessionId,
            SystemConfigurationPermissions.Read, cancellationToken);
        if (normalizedStatus == "SUBMITTED")
            await permissions.ValidatePlatformPermission(actorUserId, sessionId,
                SystemConfigurationPermissions.Approve, cancellationToken);
        var page = await repository.GetRequests(normalizedStatus, pageNumber, pageSize,
            actorUserId, sessionId, cancellationToken);
        return page with
        {
            Items = page.Items.Select(item => item with
            {
                CreatedAtUtc = DateTime.SpecifyKind(item.CreatedAtUtc, DateTimeKind.Utc),
                UpdatedAtUtc = item.UpdatedAtUtc is null ? null : DateTime.SpecifyKind(item.UpdatedAtUtc.Value, DateTimeKind.Utc)
            }).ToArray()
        };
    }

    public async Task<SystemConfigurationRequestPage> Approvals(
        int pageNumber, int pageSize, long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        ValidatePage(pageNumber, pageSize);
        await permissions.ValidatePlatformPermission(actorUserId, sessionId,
            SystemConfigurationPermissions.Read, cancellationToken);
        await permissions.ValidatePlatformPermission(actorUserId, sessionId,
            SystemConfigurationPermissions.Approve, cancellationToken);
        var page = await repository.GetRequests("SUBMITTED", pageNumber, pageSize,
            actorUserId, sessionId, cancellationToken);
        return page with
        {
            Items = page.Items.Select(item => item with
            {
                CreatedAtUtc = DateTime.SpecifyKind(item.CreatedAtUtc, DateTimeKind.Utc),
                UpdatedAtUtc = item.UpdatedAtUtc is null ? null : DateTime.SpecifyKind(item.UpdatedAtUtc.Value, DateTimeKind.Utc)
            }).ToArray()
        };
    }

    public async Task<SystemConfigurationHistoryPage> History(
        int pageNumber, int pageSize, long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        ValidatePage(pageNumber, pageSize);
        await permissions.ValidatePlatformPermission(actorUserId, sessionId,
            SystemConfigurationPermissions.History, cancellationToken);
        var page = await repository.GetHistory(pageNumber, pageSize, actorUserId, sessionId, cancellationToken);
        return page with
        {
            Items = page.Items.Select(item => item with
            {
                OccurredAtUtc = DateTime.SpecifyKind(item.OccurredAtUtc, DateTimeKind.Utc)
            }).ToArray()
        };
    }

    public Task<SystemConfigurationDraftResult> CreateDraft(
        SystemConfigurationDraftRequest request, long actorUserId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken)
    {
        ValidateCandidate(request.ConfigurationKey, request.ProposedInteger);
        ValidateReason(request.ReasonCode);
        if (request.ExpectedVersionNumber < 1)
            throw new ArgumentException("The expected configuration version is invalid.");
        var targetVersion = DecodeConcurrencyVersion(request.TargetConcurrencyVersion);
        return WithPermission(SystemConfigurationPermissions.RequestCreate,
            () => repository.CreateDraft(request, targetVersion, actorUserId, sessionId, metadata, cancellationToken),
            actorUserId, sessionId, cancellationToken);
    }

    public Task<SystemConfigurationDraftResult> UpdateDraft(
        Guid requestId, SystemConfigurationDraftUpdate request, long actorUserId, Guid sessionId,
        RequestMetadata metadata, CancellationToken cancellationToken)
    {
        ValidateCandidate("database.command_timeout_seconds", request.ProposedInteger);
        ValidateReason(request.ReasonCode);
        var requestVersion = DecodeConcurrencyVersion(request.RequestConcurrencyVersion);
        return WithPermission(SystemConfigurationPermissions.RequestEdit,
            () => repository.UpdateDraft(requestId, request, requestVersion, actorUserId, sessionId, metadata, cancellationToken),
            actorUserId, sessionId, cancellationToken);
    }

    public Task<SystemConfigurationDraftResult> Transition(
        Guid requestId, string action, SystemConfigurationDecisionRequest request,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var normalizedAction = action.Trim().ToUpperInvariant();
        var decision = request.Decision.Trim().ToUpperInvariant();
        var permission = normalizedAction switch
        {
            "SUBMIT" when decision == "SUBMIT" => SystemConfigurationPermissions.Submit,
            "CANCEL" when decision == "CANCEL" => SystemConfigurationPermissions.Cancel,
            "APPROVAL" when decision is "APPROVE" or "REJECT" => SystemConfigurationPermissions.Approve,
            _ => throw new ArgumentException("The requested configuration transition is invalid.")
        };
        var version = DecodeConcurrencyVersion(request.RequestConcurrencyVersion);
        return WithPermission(permission,
            () => repository.Transition(requestId, normalizedAction, decision, version,
                actorUserId, sessionId, metadata, cancellationToken),
            actorUserId, sessionId, cancellationToken);
    }

    public Task<SystemConfigurationDraftResult> Apply(
        Guid requestId, SystemConfigurationTransitionRequest request,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var version = DecodeConcurrencyVersion(request.RequestConcurrencyVersion);
        return WithPermission(SystemConfigurationPermissions.Apply,
            () => repository.Apply(requestId, version, actorUserId, sessionId, metadata, cancellationToken),
            actorUserId, sessionId, cancellationToken);
    }

    private async Task<T> WithPermission<T>(
        string permission, Func<Task<T>> action, long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        await permissions.ValidatePlatformPermission(actorUserId, sessionId, permission, cancellationToken);
        return await action();
    }

    private static void ValidateCandidate(string key, int value)
    {
        if (!string.Equals(key, "database.command_timeout_seconds", StringComparison.Ordinal) ||
            value is < 1 or > 120)
            throw new ArgumentException("The configuration request is not eligible under the current policy.");
    }

    private static void ValidateReason(string reasonCode)
    {
        if (reasonCode is not ("ROUTINE_MAINTENANCE" or "CAPACITY_ADJUSTMENT" or "INCIDENT_FOLLOWUP"))
            throw new ArgumentException("The configuration reason code is invalid.");
    }

    private static void ValidatePage(int pageNumber, int pageSize)
    {
        if (pageNumber is < 1 or > 100_000 || pageSize is < 1 or > 100)
            throw new ArgumentOutOfRangeException(nameof(pageNumber), "The page request is invalid.");
    }

    private static byte[] DecodeConcurrencyVersion(string value)
    {
        var buffer = new byte[8];
        if (value is null || !Convert.TryFromBase64String(value, buffer, out var written) || written != buffer.Length)
            throw new ArgumentException("The configuration concurrency version is invalid.");
        return buffer;
    }
}
