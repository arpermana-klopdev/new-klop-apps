namespace KLOP.Platform.Application;

public sealed class NotificationManagementService(
    INotificationManagementRepository repository,
    IPlatformPermissionRepository permissionRepository,
    IPlatformRuntimeSettings settings)
{
    public async Task<NotificationPermissionsResponse> Permissions(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        var effective = await permissionRepository.GetPlatformPermissions(
            actorUserId, sessionId, cancellationToken);
        return new NotificationPermissionsResponse(NotificationPermissions.All
            .Where(effective.Contains).ToArray());
    }

    public Task<IReadOnlyList<NotificationTemplateSummary>> Templates(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
        repository.ListTemplates(actorUserId, sessionId, cancellationToken);

    public async Task<NotificationTemplateDetail?> Template(
        Guid templateId, long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        var rows = await repository.ListTemplateVersions(templateId, actorUserId, sessionId, cancellationToken);
        if (rows.Count == 0)
            return null;
        var first = rows[0];
        return new NotificationTemplateDetail(templateId, first.TemplateCode, first.DisplayName, rows);
    }

    public async Task<NotificationTemplatePreviewResponse?> Preview(
        Guid versionId, long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        var rows = await repository.ListTemplateVersionsForPreview(versionId, actorUserId, sessionId,
            cancellationToken);
        var version = rows.FirstOrDefault();
        if (version is null)
            return null;
        EnsureSupportedVerificationLocale(version.TemplateCode, version.ChannelCode, version.LocaleCode);
        var rendered = NotificationTemplateRenderer.Preview(version.Subject, version.Body);
        return new NotificationTemplatePreviewResponse(rendered.Subject, rendered.Body);
    }

    public Task<IReadOnlyList<NotificationChannelStatus>> Channels(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
        repository.ListChannels(actorUserId, sessionId, cancellationToken);

    public async Task<NotificationSettingsReadiness> SettingsReadiness(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        await permissionRepository.ValidatePlatformPermission(actorUserId, sessionId,
            NotificationPermissions.SettingsRead, cancellationToken);
        return new NotificationSettingsReadiness(
            !string.IsNullOrWhiteSpace(settings.SmtpHost),
            settings.SmtpPort is > 0 and <= 65535,
            !string.IsNullOrWhiteSpace(settings.SmtpFrom),
            settings.SmtpRequireTls,
            !string.IsNullOrWhiteSpace(settings.SmtpUsername) &&
                !string.IsNullOrWhiteSpace(settings.SmtpPasswordReference),
            settings.NotificationTemplatesEnabled,
            settings.NotificationDeliveryAuditEnabled,
            settings.EmailVerificationHours is >= 1 and <= 24 ? "VALID" : "INVALID");
    }

    public async Task<NotificationDeliveryHistoryPage> History(
        int pageNumber, int pageSize, long actorUserId, Guid sessionId,
        CancellationToken cancellationToken)
    {
        if (pageNumber is < 1 or > 100_000 || pageSize is < 1 or > 100)
            throw new ArgumentOutOfRangeException(nameof(pageNumber));
        var result = await repository.ListDeliveryHistory(pageNumber, pageSize, actorUserId, sessionId,
            cancellationToken);
        return result with
        {
            Items = result.Items.Select(item => item with
            {
                OccurredAtUtc = DateTime.SpecifyKind(item.OccurredAtUtc, DateTimeKind.Utc)
            }).ToArray(),
            PageNumber = pageNumber,
            PageSize = pageSize
        };
    }

    public Task<NotificationTemplateDraftResult> CreateDraft(
        string templateCode, string displayName, string channelCode, string localeCode,
        string subject, string body, long actorUserId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken)
    {
        _ = NotificationTemplateRenderer.Preview(subject, body);
        ValidateCode(templateCode, nameof(templateCode));
        ValidateCode(channelCode, nameof(channelCode));
        ValidateCode(localeCode, nameof(localeCode));
        EnsureSupportedVerificationLocale(templateCode, channelCode, localeCode);
        if (string.IsNullOrWhiteSpace(displayName) || displayName.Length > 200)
            throw new ArgumentException("The template display name is invalid.", nameof(displayName));
        return repository.CreateDraft(templateCode, displayName.Trim(), channelCode, localeCode,
            subject, body, actorUserId, sessionId, metadata, cancellationToken);
    }

    public Task<NotificationTemplateDraftResult> UpdateDraft(
        Guid versionId, NotificationTemplateDraftRequest request, long actorUserId, Guid sessionId,
        RequestMetadata metadata, CancellationToken cancellationToken)
    {
        _ = NotificationTemplateRenderer.Preview(request.Subject, request.Body);
        var expectedVersion = DecodeConcurrencyVersion(request.ConcurrencyVersion);
        return repository.UpdateDraft(versionId, request.Subject, request.Body, expectedVersion,
            actorUserId, sessionId, metadata, cancellationToken);
    }

    public Task<IReadOnlyList<NotificationTemplateVersion>> Transition(
        Guid versionId, string action, NotificationDecisionRequest request,
        long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var allowed = action switch
        {
            "submit" or "activate" or "archive" => new[] { "SUBMIT", "ACTIVATE", "ARCHIVE" },
            "approve" => new[] { "APPROVE", "REJECT" },
            _ => Array.Empty<string>()
        };
        var decision = request.Decision.Trim().ToUpperInvariant();
        if (!allowed.Contains(decision, StringComparer.Ordinal) ||
            (request.Note?.Length ?? 0) > 1000)
            throw new ArgumentException("The requested notification transition is invalid.");
        return repository.TransitionVersion(versionId, action, decision, request.Note,
            DecodeConcurrencyVersion(request.ConcurrencyVersion), actorUserId, sessionId,
            metadata, cancellationToken);
    }

    private static void ValidateCode(string value, string parameter)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > 50 ||
            value.Any(character => !char.IsAsciiLetterOrDigit(character) && character != '_' && character != '-'))
            throw new ArgumentException("A notification code is invalid.", parameter);
    }

    private static void EnsureSupportedVerificationLocale(string templateCode, string channelCode, string localeCode)
    {
        if (templateCode == "EMAIL_VERIFICATION" && (channelCode != "EMAIL" || localeCode != "en"))
            throw new ArgumentException("Email verification templates support only the EMAIL channel and en locale.");
    }

    private static byte[] DecodeConcurrencyVersion(string value)
    {
        var buffer = new byte[8];
        if (!Convert.TryFromBase64String(value, buffer, out var written) || written != 8)
            throw new ArgumentException("The notification concurrency version is invalid.", nameof(value));
        return buffer;
    }
}
