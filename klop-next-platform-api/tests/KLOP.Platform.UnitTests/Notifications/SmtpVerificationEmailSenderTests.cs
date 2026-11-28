using System.Net;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class SmtpVerificationEmailSenderTests
{
    [Fact]
    public async Task LegacyDeliveryDoesNotTouchNotificationRepositoryWhenBothGatesAreOff()
    {
        var repository = new FakeNotificationRepository();
        var transport = new FakeTransport();
        var sender = CreateSender(repository, transport, templatesEnabled: false, auditEnabled: false);

        await sender.Send("person@example.test", 7, "token-value", Guid.NewGuid(), CancellationToken.None);

        Assert.Equal(1, transport.SendCount);
        Assert.Equal(0, repository.TemplateLookupCount);
        Assert.Equal(0, repository.AttemptCount);
        Assert.Contains("token-value", transport.Body);
    }

    [Fact]
    public async Task ProviderAcceptanceIsNotTurnedIntoFailureWhenAuditPersistenceFails()
    {
        var repository = new FakeNotificationRepository { ThrowWhenRecording = true };
        var transport = new FakeTransport();
        var logger = new RecordingLogger<SmtpVerificationEmailSender>();
        var sender = CreateSender(repository, transport, templatesEnabled: false, auditEnabled: true, logger: logger);

        await sender.Send("person@example.test", 7, "token-value", Guid.NewGuid(), CancellationToken.None);

        Assert.Equal(1, transport.SendCount);
        Assert.True(repository.LastAccepted);
        Assert.Equal("PROVIDER_ACCEPTED", repository.LastErrorCategory);
        var telemetry = string.Join(Environment.NewLine, logger.Messages);
        Assert.Contains("PROVIDER_ACCEPTED", telemetry, StringComparison.Ordinal);
        Assert.DoesNotContain("database details must not escape", telemetry, StringComparison.Ordinal);
        Assert.DoesNotContain("token-value", telemetry, StringComparison.Ordinal);
    }

    [Fact]
    public async Task SmtpFailureIsPreservedWhenFailureAuditAlsoFails()
    {
        var providerFailure = new InvalidOperationException("provider rejected");
        var repository = new FakeNotificationRepository { ThrowWhenRecording = true };
        var transport = new FakeTransport { Failure = providerFailure };
        var sender = CreateSender(repository, transport, templatesEnabled: false, auditEnabled: true);

        var thrown = await Assert.ThrowsAsync<InvalidOperationException>(() => sender.Send(
            "person@example.test", 7, "token-value", Guid.NewGuid(), CancellationToken.None));

        Assert.Same(providerFailure, thrown);
        Assert.False(repository.LastAccepted);
        Assert.Equal("SMTP_FAILURE", repository.LastErrorCategory);
    }

    [Fact]
    public async Task EnabledTemplateRequiresAnEnglishActiveVersionAndFailsSafelyWhenUnavailable()
    {
        var repository = new FakeNotificationRepository { ThrowWhenRecording = true };
        var sender = CreateSender(repository, new FakeTransport(), templatesEnabled: true, auditEnabled: true);

        var thrown = await Assert.ThrowsAsync<InvalidOperationException>(() => sender.Send(
            "person@example.test", 7, "token-value", Guid.NewGuid(), CancellationToken.None));

        Assert.Equal("The enabled verification template is unavailable.", thrown.Message);
        Assert.Equal(1, repository.TemplateLookupCount);
        Assert.Equal("TEMPLATE_UNAVAILABLE", repository.LastErrorCategory);
    }

    [Fact]
    public async Task TemplateLookupFailureIsSanitizedAndAuditFailureDoesNotMaskIt()
    {
        var repository = new FakeNotificationRepository
        {
            ThrowWhenLookingUpTemplate = true,
            ThrowWhenRecording = true
        };
        var sender = CreateSender(repository, new FakeTransport(), templatesEnabled: true, auditEnabled: true);

        var thrown = await Assert.ThrowsAsync<InvalidOperationException>(() => sender.Send(
            "person@example.test", 7, "token-value", Guid.NewGuid(), CancellationToken.None));

        Assert.Equal("The enabled verification template is unavailable.", thrown.Message);
    }

    [Fact]
    public async Task SenderNeverSelectsOrSendsAnUnsupportedVerificationLocale()
    {
        var repository = new FakeNotificationRepository
        {
            ActiveVersion = new NotificationTemplateVersion(
                Guid.NewGuid(), "EMAIL_VERIFICATION", "Verification", 1, "ACTIVE",
                "Verify", "{{verification_link}} {{expiry_hours}}", "EMAIL", "fr",
                DateTime.UtcNow, new byte[8])
        };
        var transport = new FakeTransport();
        var sender = CreateSender(repository, transport, templatesEnabled: true, auditEnabled: false);

        await Assert.ThrowsAsync<InvalidOperationException>(() => sender.Send(
            "person@example.test", 7, "token-value", Guid.NewGuid(), CancellationToken.None));

        Assert.Equal(0, transport.SendCount);
    }

    [Fact]
    public async Task CancellationFromTransportIsPreservedWithoutDeliveryAudit()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        var repository = new FakeNotificationRepository();
        var transport = new FakeTransport { Failure = new OperationCanceledException(cancellation.Token) };
        var sender = CreateSender(repository, transport, templatesEnabled: false, auditEnabled: true);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => sender.Send(
            "person@example.test", 7, "token-value", Guid.NewGuid(), cancellation.Token));

        Assert.Equal(0, repository.AttemptCount);
    }

    [Fact]
    public async Task InvalidSmtpConfigurationUsesSafeFailureAndBestEffortAudit()
    {
        var repository = new FakeNotificationRepository { ThrowWhenRecording = true };
        var sender = CreateSender(repository, new FakeTransport(), templatesEnabled: false,
            auditEnabled: true, smtpHost: "");

        var thrown = await Assert.ThrowsAsync<InvalidOperationException>(() => sender.Send(
            "person@example.test", 7, "token-value", Guid.NewGuid(), CancellationToken.None));

        Assert.Equal("SMTP delivery is not configured.", thrown.Message);
        Assert.Equal("SMTP_CONFIGURATION", repository.LastErrorCategory);
    }

    [Fact]
    public async Task KeyVaultFailureIsReportedAsSafeConfigurationFailureWithoutSending()
    {
        var repository = new FakeNotificationRepository { ThrowWhenRecording = true };
        var transport = new FakeTransport();
        var sender = CreateSender(repository, transport, templatesEnabled: false, auditEnabled: true,
            failSecretLookup: true);

        var thrown = await Assert.ThrowsAsync<InvalidOperationException>(() => sender.Send(
            "person@example.test", 7, "token-value", Guid.NewGuid(), CancellationToken.None));

        Assert.Equal("SMTP credentials are unavailable.", thrown.Message);
        Assert.Equal(0, transport.SendCount);
        Assert.Equal("SMTP_CONFIGURATION", repository.LastErrorCategory);
    }

    private static SmtpVerificationEmailSender CreateSender(
        FakeNotificationRepository repository,
        FakeTransport transport,
        bool templatesEnabled,
        bool auditEnabled,
        string smtpHost = "smtp.invalid",
        bool failSecretLookup = false,
        ILogger<SmtpVerificationEmailSender>? logger = null)
    {
        var settings = new RuntimeSettings(
            "https://issuer.example.test", "audience", "https://app.example.test", 15, 7,
            5, 12, 24, 30, 8, smtpHost, 587, "sender@example.test", true,
            failSecretLookup ? "smtp-user" : null, null, failSecretLookup ? "smtp-password-ref" : null,
            NotificationTemplatesEnabled: templatesEnabled,
            NotificationDeliveryAuditEnabled: auditEnabled);
        return new SmtpVerificationEmailSender(
            new TestHostEnvironment(), settings, new FakeSecrets(failSecretLookup), repository, transport,
            logger ?? NullLogger<SmtpVerificationEmailSender>.Instance);
    }

    private sealed class TestHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = Environments.Development;
        public string ApplicationName { get; set; } = "KLOP.Platform.UnitTests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private sealed class FakeSecrets(bool failLookup) : IKeyVaultSecrets
    {
        public Task<KeyVaultSecretValue> Get(string secretName, CancellationToken cancellationToken) =>
            failLookup
                ? Task.FromException<KeyVaultSecretValue>(new InvalidOperationException("secret details must not escape"))
                : Task.FromResult(new KeyVaultSecretValue("test-secret", null));
    }

    private sealed class RecordingLogger<T> : ILogger<T>
    {
        public List<string> Messages { get; } = [];
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => true;
        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter) => Messages.Add(formatter(state, exception));
    }

    private sealed class FakeTransport : ISmtpMailTransport
    {
        public int SendCount { get; private set; }
        public string Body { get; private set; } = "";
        public Exception? Failure { get; init; }

        public Task Send(string host, int port, bool requireTls, string from, string to,
            string subject, string body, NetworkCredential? credentials, CancellationToken cancellationToken)
        {
            SendCount++;
            Body = body;
            return Failure is null ? Task.CompletedTask : Task.FromException(Failure);
        }
    }

    private sealed class FakeNotificationRepository : INotificationManagementRepository
    {
        public int TemplateLookupCount { get; private set; }
        public int AttemptCount { get; private set; }
        public bool LastAccepted { get; private set; }
        public string? LastErrorCategory { get; private set; }
        public bool ThrowWhenRecording { get; init; }
        public bool ThrowWhenLookingUpTemplate { get; init; }
        public NotificationTemplateVersion? ActiveVersion { get; init; }

        public Task<NotificationTemplateVersion?> GetActiveVerificationVersion(CancellationToken cancellationToken)
        {
            TemplateLookupCount++;
            if (ThrowWhenLookingUpTemplate)
                return Task.FromException<NotificationTemplateVersion?>(
                    new InvalidOperationException("database details must not escape"));
            return Task.FromResult(ActiveVersion);
        }

        public Task RecordDeliveryAttempt(Guid? templateVersionId, string templateCode, int? versionNumber,
            Guid correlationId, bool accepted, string? safeErrorCategory, CancellationToken cancellationToken)
        {
            AttemptCount++;
            LastAccepted = accepted;
            LastErrorCategory = safeErrorCategory ?? "PROVIDER_ACCEPTED";
            return ThrowWhenRecording
                ? Task.FromException(new InvalidOperationException("database details must not escape"))
                : Task.CompletedTask;
        }

        public Task<IReadOnlyList<NotificationTemplateSummary>> ListTemplates(
            long actorUserId, Guid sessionId, CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<IReadOnlyList<NotificationTemplateVersion>> ListTemplateVersions(
            Guid templateId, long actorUserId, Guid sessionId, CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<IReadOnlyList<NotificationTemplateVersion>> ListTemplateVersionsForPreview(
            Guid versionId, long actorUserId, Guid sessionId, CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<IReadOnlyList<NotificationChannelStatus>> ListChannels(
            long actorUserId, Guid sessionId, CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<NotificationDeliveryHistoryPage> ListDeliveryHistory(
            int pageNumber, int pageSize, long actorUserId, Guid sessionId, CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<NotificationTemplateDraftResult> CreateDraft(
            string templateCode, string displayName, string channelCode, string localeCode,
            string subject, string body, long actorUserId, Guid sessionId, RequestMetadata metadata,
            CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<NotificationTemplateDraftResult> UpdateDraft(
            Guid versionId, string subject, string body, byte[] expectedVersion, long actorUserId,
            Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) => throw new NotImplementedException();
        public Task<IReadOnlyList<NotificationTemplateVersion>> TransitionVersion(
            Guid versionId, string action, string? decision, string? note, byte[] expectedVersion,
            long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) => throw new NotImplementedException();
    }
}
