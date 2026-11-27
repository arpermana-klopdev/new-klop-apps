using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Mail;
using System.Security.Claims;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Microsoft.IdentityModel.Tokens;

namespace KLOP.Platform.Api;

public sealed class TokenIssuer(KeyMaterial key, IPlatformRuntimeSettings settings) : IAccessTokenIssuer
{
    public AccessResult Issue(long userId, Guid sessionId)
    {
        var now = DateTime.UtcNow;
        var lifetime = TimeSpan.FromMinutes(settings.AccessMinutes);
        var token = new JwtSecurityToken(
            issuer: settings.JwtIssuer,
            audience: settings.JwtAudience,
            claims:
            [
                new Claim(JwtRegisteredClaimNames.Sub, userId.ToString(System.Globalization.CultureInfo.InvariantCulture)),
                new Claim("sid", sessionId.ToString("D")),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString("D"))
            ],
            notBefore: now,
            expires: now.Add(lifetime),
            signingCredentials: new SigningCredentials(key.SigningKey, SecurityAlgorithms.RsaSha256));
        return new AccessResult(new JwtSecurityTokenHandler().WriteToken(token), (int)lifetime.TotalSeconds);
    }
}

public sealed class SmtpVerificationEmailSender(
    IHostEnvironment environment,
    IPlatformRuntimeSettings settings,
    IKeyVaultSecrets secrets) : IVerificationEmailSender
{
    public async Task Send(string email, long userId, string verificationCode, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(settings.SmtpHost) || string.IsNullOrWhiteSpace(settings.SmtpFrom))
            throw new InvalidOperationException("SMTP delivery is not configured.");
        if (!environment.IsDevelopment() && !settings.SmtpRequireTls)
            throw new InvalidOperationException("Production SMTP requires TLS.");

        using var message = new MailMessage(settings.SmtpFrom, email)
        {
            Subject = "KLOP - Email verification",
            Body = $"User ID: {userId}\nVerification code: {verificationCode}\n" +
                $"Valid for {settings.EmailVerificationHours} hour(s). Enter the code in KLOP.\nNever share this code."
        };
        using var smtp = new SmtpClient(settings.SmtpHost, settings.SmtpPort)
        {
            EnableSsl = settings.SmtpRequireTls,
            DeliveryMethod = SmtpDeliveryMethod.Network,
            Timeout = 15_000
        };

        if (!string.IsNullOrWhiteSpace(settings.SmtpUsername))
        {
            var reference = settings.SmtpPasswordReference ??
                throw new InvalidOperationException("SMTP credentials must come from Key Vault.");
            var secret = await secrets.Get(reference, cancellationToken);
            smtp.Credentials = new NetworkCredential(settings.SmtpUsername, secret.Value);
        }

        await smtp.SendMailAsync(message, cancellationToken);
    }
}

public static class RefreshCookies
{
    public const string CookieName = "__Host-klop_refresh";

    public static void Set(HttpResponse response, AuthenticatedSession session)
    {
        response.Cookies.Append(CookieName, $"{session.SessionId:D}.{session.RefreshToken}", new CookieOptions
        {
            HttpOnly = true,
            Secure = true,
            SameSite = SameSiteMode.Strict,
            Path = "/",
            IsEssential = true,
            Expires = DateTimeOffset.UtcNow.AddDays(session.RefreshDays)
        });
    }

    public static void Clear(HttpResponse response) =>
        response.Cookies.Delete(CookieName, new CookieOptions
        {
            Path = "/",
            Secure = true,
            SameSite = SameSiteMode.Strict
        });

    public static (Guid SessionId, string Token)? Read(HttpRequest request)
    {
        if (!request.Cookies.TryGetValue(CookieName, out var value) || string.IsNullOrWhiteSpace(value))
            return null;
        var separator = value.IndexOf('.');
        if (separator < 0 || !Guid.TryParse(value[..separator], out var sessionId) ||
            value.Length - separator - 1 < 32 || value.Length > 150)
            return null;
        return (sessionId, value[(separator + 1)..]);
    }
}
