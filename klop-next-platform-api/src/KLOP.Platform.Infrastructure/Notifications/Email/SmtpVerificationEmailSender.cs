using System.Net;
using System.Net.Mail;
using KLOP.Platform.Application;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace KLOP.Platform.Infrastructure;

public interface ISmtpMailTransport
{
    Task Send(string host, int port, bool requireTls, string from, string to, string subject, string body,
        NetworkCredential? credentials, CancellationToken cancellationToken);
}

public sealed class SmtpMailTransport : ISmtpMailTransport
{
    public async Task Send(string host, int port, bool requireTls, string from, string to,
        string subject, string body, NetworkCredential? credentials, CancellationToken cancellationToken)
    {
        using var message = new MailMessage(from, to) { Subject = subject, Body = body };
        using var smtp = new SmtpClient(host, port)
        {
            EnableSsl = requireTls,
            DeliveryMethod = SmtpDeliveryMethod.Network,
            Timeout = 15_000,
            Credentials = credentials
        };
        await smtp.SendMailAsync(message, cancellationToken);
    }
}

public sealed class SmtpVerificationEmailSender(
    IHostEnvironment environment,
    IPlatformRuntimeSettings settings,
    IKeyVaultSecrets secrets,
    INotificationManagementRepository notificationRepository,
    ISmtpMailTransport transport,
    ILogger<SmtpVerificationEmailSender> logger) : IVerificationEmailSender
{
    public async Task Send(string email, long userId, string verificationCode, Guid correlationId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(settings.SmtpHost) || string.IsNullOrWhiteSpace(settings.SmtpFrom))
        {
            await RecordAttemptSafely(null, "EMAIL_VERIFICATION", null, correlationId, false,
                "SMTP_CONFIGURATION", cancellationToken);
            throw new InvalidOperationException("SMTP delivery is not configured.");
        }
        if (!environment.IsDevelopment() && !settings.SmtpRequireTls)
        {
            await RecordAttemptSafely(null, "EMAIL_VERIFICATION", null, correlationId, false,
                "SMTP_CONFIGURATION", cancellationToken);
            throw new InvalidOperationException("Production SMTP requires TLS.");
        }

        var verificationUrl = VerificationEmailLink.Build(settings.AllowedOrigin, userId, verificationCode);
        var subject = "KLOP - Email verification";
        var body = $"Complete email verification using this single-use link:\n{verificationUrl}\n" +
            $"The link expires in {settings.EmailVerificationHours} hour(s). Never share it.";
        NotificationTemplateVersion? template = null;
        if (settings.NotificationTemplatesEnabled)
        {
            try
            {
                template = await notificationRepository.GetActiveVerificationVersion(cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                await RecordAttemptSafely(null, "EMAIL_VERIFICATION", null, correlationId, false,
                    "TEMPLATE_UNAVAILABLE", cancellationToken);
                throw new InvalidOperationException("The enabled verification template is unavailable.");
            }

            if (template is null || template.LocaleCode != "en")
            {
                await RecordAttemptSafely(template?.VersionId, template?.TemplateCode ?? "EMAIL_VERIFICATION",
                    template?.VersionNumber, correlationId, false, "TEMPLATE_UNAVAILABLE", cancellationToken);
                throw new InvalidOperationException("The enabled verification template is unavailable.");
            }

            try
            {
                var rendered = NotificationTemplateRenderer.RenderVerification(template.Subject, template.Body,
                    verificationUrl, settings.EmailVerificationHours);
                subject = rendered.Subject;
                body = rendered.Body;
            }
            catch (ArgumentException)
            {
                await RecordAttemptSafely(template.VersionId, template.TemplateCode, template.VersionNumber,
                    correlationId, false, "TEMPLATE_UNAVAILABLE", cancellationToken);
                throw new InvalidOperationException("The enabled verification template is invalid.");
            }
        }

        NetworkCredential? credentials = null;
        try
        {
            if (!string.IsNullOrWhiteSpace(settings.SmtpUsername))
            {
                var reference = settings.SmtpPasswordReference ??
                    throw new InvalidOperationException("SMTP credentials must come from Key Vault.");
                var secret = await secrets.Get(reference, cancellationToken);
                credentials = new NetworkCredential(settings.SmtpUsername, secret.Value);
            }
            await transport.Send(settings.SmtpHost, settings.SmtpPort, settings.SmtpRequireTls,
                settings.SmtpFrom, email, subject, body, credentials, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            await RecordAttemptSafely(template?.VersionId, template?.TemplateCode ?? "EMAIL_VERIFICATION",
                template?.VersionNumber, correlationId, false, "SMTP_FAILURE", cancellationToken);
            throw;
        }

        await RecordAttemptSafely(template?.VersionId, template?.TemplateCode ?? "EMAIL_VERIFICATION",
            template?.VersionNumber, correlationId, true, null, cancellationToken);
    }

    private async Task RecordAttemptSafely(Guid? versionId, string templateCode, int? versionNumber,
        Guid correlationId, bool accepted, string? errorCategory, CancellationToken cancellationToken)
    {
        if (!settings.NotificationDeliveryAuditEnabled)
            return;

        try
        {
            await notificationRepository.RecordDeliveryAttempt(versionId, templateCode, versionNumber,
                correlationId, accepted, errorCategory, cancellationToken);
        }
        catch
        {
            logger.LogWarning("Notification delivery audit persistence failed for category {ErrorCategory}.",
                errorCategory ?? "PROVIDER_ACCEPTED");
        }
    }
}

internal static class VerificationEmailLink
{
    public static string Build(string frontendOrigin, long userId, string token)
    {
        if (userId <= 0)
            throw new ArgumentOutOfRangeException(nameof(userId));
        if (string.IsNullOrWhiteSpace(token))
            throw new ArgumentException("A verification token is required.", nameof(token));
        if (!Uri.TryCreate(frontendOrigin, UriKind.Absolute, out var origin) ||
            origin.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(origin.UserInfo) ||
            origin.AbsolutePath != "/" || !string.IsNullOrEmpty(origin.Query) ||
            !string.IsNullOrEmpty(origin.Fragment))
            throw new InvalidOperationException("The configured frontend address must be an HTTPS origin.");

        var link = new UriBuilder(origin)
        {
            Path = "/verify-email",
            Fragment = $"userId={userId.ToString(System.Globalization.CultureInfo.InvariantCulture)}&token={Uri.EscapeDataString(token)}"
        };
        return link.Uri.AbsoluteUri;
    }
}
