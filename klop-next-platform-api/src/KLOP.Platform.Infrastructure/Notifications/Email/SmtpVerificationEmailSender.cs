using System.Net;
using System.Net.Mail;
using KLOP.Platform.Application;
using Microsoft.Extensions.Hosting;

namespace KLOP.Platform.Infrastructure;

public sealed class SmtpVerificationEmailSender(
    IHostEnvironment environment,
    IPlatformRuntimeSettings settings,
    IKeyVaultSecrets secrets,
    INotificationManagementRepository notificationRepository) : IVerificationEmailSender
{
    public async Task Send(string email, long userId, string verificationCode, Guid correlationId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(settings.SmtpHost) || string.IsNullOrWhiteSpace(settings.SmtpFrom))
            throw new InvalidOperationException("SMTP delivery is not configured.");
        if (!environment.IsDevelopment() && !settings.SmtpRequireTls)
            throw new InvalidOperationException("Production SMTP requires TLS.");

        var verificationUrl = VerificationEmailLink.Build(settings.AllowedOrigin, userId, verificationCode);
        var subject = "KLOP - Email verification";
        var body = $"Complete email verification using this single-use link:\n{verificationUrl}\n" +
            $"The link expires in {settings.EmailVerificationHours} hour(s). Never share it.";
        NotificationTemplateVersion? template = null;
        if (settings.NotificationTemplatesEnabled)
        {
            template = await notificationRepository.GetActiveVerificationVersion(cancellationToken);
            if (template is null)
            {
                await notificationRepository.RecordDeliveryAttempt(null, "EMAIL_VERIFICATION", null,
                    correlationId, false, "TEMPLATE_UNAVAILABLE", cancellationToken);
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
                await notificationRepository.RecordDeliveryAttempt(template.VersionId, template.TemplateCode,
                    template.VersionNumber, correlationId, false, "TEMPLATE_UNAVAILABLE", cancellationToken);
                throw;
            }
        }
        using var message = new MailMessage(settings.SmtpFrom, email)
        {
            Subject = subject,
            Body = body
        };
        using var smtp = new SmtpClient(settings.SmtpHost, settings.SmtpPort)
        {
            EnableSsl = settings.SmtpRequireTls,
            DeliveryMethod = SmtpDeliveryMethod.Network,
            Timeout = 15_000
        };

        try
        {
            if (!string.IsNullOrWhiteSpace(settings.SmtpUsername))
            {
                var reference = settings.SmtpPasswordReference ??
                    throw new InvalidOperationException("SMTP credentials must come from Key Vault.");
                var secret = await secrets.Get(reference, cancellationToken);
                smtp.Credentials = new NetworkCredential(settings.SmtpUsername, secret.Value);
            }
            await smtp.SendMailAsync(message, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            await notificationRepository.RecordDeliveryAttempt(template?.VersionId,
                template?.TemplateCode ?? "EMAIL_VERIFICATION",
                template?.VersionNumber, correlationId, false, "SMTP_FAILURE", cancellationToken);
            throw;
        }
        await notificationRepository.RecordDeliveryAttempt(template?.VersionId,
            template?.TemplateCode ?? "EMAIL_VERIFICATION", template?.VersionNumber,
            correlationId, true, null, cancellationToken);
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
