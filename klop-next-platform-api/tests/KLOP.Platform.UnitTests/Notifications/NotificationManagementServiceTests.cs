using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class NotificationManagementServiceTests
{
    [Fact]
    public async Task PermissionsExposeOnlyKnownDatabaseBackedNotificationCapabilities()
    {
        var permissionRepository = new FakePlatformPermissionRepository(
            ["platform.notifications.read", "platform.notifications.activate", "platform.tenants.write"]);
        var service = CreateService(new FakeNotificationRepository(), permissionRepository);

        var response = await service.Permissions(4, Guid.NewGuid(), CancellationToken.None);

        Assert.Equal(["platform.notifications.read", "platform.notifications.activate"], response.Permissions);
    }

    [Fact]
    public async Task DraftUpdateRejectsInvalidConcurrencyBeforeCallingStoredProcedureRepository()
    {
        var repository = new FakeNotificationRepository();
        var service = CreateService(repository, new FakePlatformPermissionRepository([]));
        var request = new NotificationTemplateDraftRequest(
            "Verify", "{{verification_link}} {{expiry_hours}}", "not-a-rowversion");

        await Assert.ThrowsAsync<ArgumentException>(() => service.UpdateDraft(
            Guid.NewGuid(), request, 4, Guid.NewGuid(),
            new RequestMetadata("request", Guid.NewGuid()), CancellationToken.None));

        Assert.False(repository.UpdateDraftCalled);
    }

    [Fact]
    public async Task SettingsReadinessValidatesTheExactSettingsPermission()
    {
        var permissions = new FakePlatformPermissionRepository([]);
        var service = CreateService(new FakeNotificationRepository(), permissions);

        await service.SettingsReadiness(4, Guid.NewGuid(), CancellationToken.None);

        Assert.Equal([NotificationPermissions.SettingsRead], permissions.ValidatedPermissions);
    }

    [Fact]
    public async Task SettingsReadinessDoesNotReturnMetadataWhenExactPermissionIsDenied()
    {
        var permissions = new FakePlatformPermissionRepository([])
        {
            ValidationFailure = new UnauthorizedAccessException()
        };
        var service = CreateService(new FakeNotificationRepository(), permissions);

        await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            service.SettingsReadiness(4, Guid.NewGuid(), CancellationToken.None));
    }

    [Theory]
    [InlineData("EMAIL_VERIFICATION", "EMAIL", "fr")]
    [InlineData("EMAIL_VERIFICATION", "SMS", "en")]
    public async Task DraftCreationRejectsUnsupportedVerificationChannelOrLocale(
        string templateCode, string channelCode, string localeCode)
    {
        var repository = new FakeNotificationRepository();
        var service = CreateService(repository, new FakePlatformPermissionRepository([]));

        await Assert.ThrowsAsync<ArgumentException>(() => service.CreateDraft(
            templateCode, "Verification", channelCode, localeCode, "Verify",
            "{{verification_link}} {{expiry_hours}}", 4, Guid.NewGuid(),
            new RequestMetadata("request", Guid.NewGuid()), CancellationToken.None));

        Assert.False(repository.CreateDraftCalled);
    }

    [Fact]
    public async Task PreviewRejectsVerificationTemplatesOutsideTheSeededLocale()
    {
        var repository = new FakeNotificationRepository
        {
            PreviewVersion = new NotificationTemplateVersion(
                Guid.NewGuid(), "EMAIL_VERIFICATION", "Verification", 1, "DRAFT",
                "Verify", "{{verification_link}} {{expiry_hours}}", "EMAIL", "fr",
                DateTime.UtcNow, new byte[8])
        };
        var service = CreateService(repository, new FakePlatformPermissionRepository([]));

        await Assert.ThrowsAsync<ArgumentException>(() => service.Preview(
            repository.PreviewVersion.VersionId, 4, Guid.NewGuid(), CancellationToken.None));
    }

    private static NotificationManagementService CreateService(
        INotificationManagementRepository repository, IPlatformPermissionRepository permissionRepository) =>
        new(repository, permissionRepository, new RuntimeSettings(
            "https://issuer.example.test", "audience", "https://app.example.test", 15, 7,
            5, 12, 24, 30, 8, "smtp.invalid", 587, "sender@example.test", true,
            null, null, null));

    private sealed class FakePlatformPermissionRepository(IReadOnlyList<string> permissions)
        : IPlatformPermissionRepository
    {
        public List<string> ValidatedPermissions { get; } = [];
        public Exception? ValidationFailure { get; init; }

        public Task ValidatePlatformPermission(long userId, Guid sessionId, string permissionCode,
            CancellationToken cancellationToken)
        {
            ValidatedPermissions.Add(permissionCode);
            return ValidationFailure is null ? Task.CompletedTask : Task.FromException(ValidationFailure);
        }

        public Task<IReadOnlyList<string>> GetPlatformPermissions(
            long userId, Guid sessionId, CancellationToken cancellationToken) =>
            Task.FromResult(permissions);
    }

    private sealed class FakeNotificationRepository : INotificationManagementRepository
    {
        public bool UpdateDraftCalled { get; private set; }
        public bool CreateDraftCalled { get; private set; }
        public NotificationTemplateVersion? PreviewVersion { get; init; }

        public Task<IReadOnlyList<NotificationTemplateSummary>> ListTemplates(
            long actorUserId, Guid sessionId, CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<IReadOnlyList<NotificationTemplateVersion>> ListTemplateVersions(
            Guid templateId, long actorUserId, Guid sessionId, CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<IReadOnlyList<NotificationTemplateVersion>> ListTemplateVersionsForPreview(
            Guid versionId, long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<NotificationTemplateVersion>>(
                PreviewVersion is null ? [] : [PreviewVersion]);
        public Task<IReadOnlyList<NotificationChannelStatus>> ListChannels(
            long actorUserId, Guid sessionId, CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<NotificationDeliveryHistoryPage> ListDeliveryHistory(
            int pageNumber, int pageSize, long actorUserId, Guid sessionId, CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<NotificationTemplateDraftResult> CreateDraft(
            string templateCode, string displayName, string channelCode, string localeCode, string subject,
            string body, long actorUserId, Guid sessionId, RequestMetadata metadata,
            CancellationToken cancellationToken)
        {
            CreateDraftCalled = true;
            throw new NotImplementedException();
        }
        public Task<NotificationTemplateDraftResult> UpdateDraft(
            Guid versionId, string subject, string body, byte[] expectedVersion, long actorUserId, Guid sessionId,
            RequestMetadata metadata, CancellationToken cancellationToken)
        {
            UpdateDraftCalled = true;
            throw new NotImplementedException();
        }
        public Task<IReadOnlyList<NotificationTemplateVersion>> TransitionVersion(
            Guid versionId, string action, string? decision, string? note, byte[] expectedVersion,
            long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) =>
            throw new NotImplementedException();
        public Task<NotificationTemplateVersion?> GetActiveVerificationVersion(
            CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task RecordDeliveryAttempt(
            Guid? templateVersionId, string templateCode, int? versionNumber, Guid correlationId,
            bool accepted, string? safeErrorCategory, CancellationToken cancellationToken) =>
            throw new NotImplementedException();
    }
}
