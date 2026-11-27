using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Mail;
using System.Security.Claims;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using KLOP.Platform.Application;
using Microsoft.IdentityModel.Tokens;
using KLOP.Platform.Infrastructure;

namespace KLOP.Platform.Api;

public sealed class TokenIssuer(KeyMaterial key, RuntimeSettings settings)
{
    public int LifetimeSeconds => settings.AccessMinutes * 60;
    public AccessResult Issue(long userId, Guid sid)
    {
        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken(
            issuer: settings.JwtIssuer, audience: settings.JwtAudience,
            claims: new[] {new Claim(JwtRegisteredClaimNames.Sub,userId.ToString()),
                           new Claim("sid",sid.ToString("D")),
                           new Claim(JwtRegisteredClaimNames.Jti,Guid.NewGuid().ToString("D"))},
            notBefore: now, expires: now.AddSeconds(LifetimeSeconds),
            signingCredentials: new SigningCredentials(key.SigningKey,SecurityAlgorithms.RsaSha256));
        return new AccessResult(new JwtSecurityTokenHandler().WriteToken(token),LifetimeSeconds);
    }
}
public interface IVerificationEmailSender
{
    Task Send(string email, long userId, string verificationCode, CancellationToken ct);
}
public sealed class SmtpVerificationEmailSender(IConfiguration cfg, IHostEnvironment env,RuntimeSettings settings) : IVerificationEmailSender
{
    public async Task Send(string email,long userId,string verificationCode,CancellationToken ct)
    {
        var host = settings.SmtpHost;
        var from = settings.SmtpFrom;
        if (string.IsNullOrWhiteSpace(host) || string.IsNullOrWhiteSpace(from))
            throw new InvalidOperationException("SMTP delivery is not configured.");
        var tls = settings.SmtpRequireTls;
        if (!env.IsDevelopment() && !tls) throw new InvalidOperationException("Production SMTP requires TLS.");
        using var msg=new MailMessage(from,email)
        {
            Subject = "KLOP - Email verification",
            Body = $"User ID: {userId}\nVerification code: {verificationCode}\nValid for 1 hour. Enter the code in KLOP.\nNever share this code."
        };
        using var smtp = new SmtpClient(host,settings.SmtpPort)
        {
            EnableSsl=tls, DeliveryMethod=SmtpDeliveryMethod.Network,
            Timeout=15_000
        };
        var user=settings.SmtpUsername;
        if (!string.IsNullOrWhiteSpace(user))
        {
            var vault=cfg["KeyVault:VaultUri"];
            var passName=settings.SmtpPasswordReference;
            if (string.IsNullOrWhiteSpace(vault)||string.IsNullOrWhiteSpace(passName))
                throw new InvalidOperationException("SMTP credentials must come from Key Vault.");
            var client = new SecretClient(new Uri(vault),new DefaultAzureCredential());
            var secret=(await client.GetSecretAsync(passName, cancellationToken:ct)).Value;
            smtp.Credentials=new NetworkCredential(user,secret.Value);
        }
        // SMTP send is after SQL commit; delivery failure must be retried via resend endpoint.
        await smtp.SendMailAsync(msg,ct);
    }
}
public static class RefreshCookies
{
    public const string CookieName = "__Host-klop_refresh";
    public static void Set(HttpResponse resp, Guid sid, string raw, int refreshDays)
    {
        resp.Cookies.Append(CookieName,$"{sid:D}.{raw}",new CookieOptions {
            HttpOnly=true,Secure=true,SameSite=SameSiteMode.Strict,Path="/",IsEssential=true,
            Expires=DateTimeOffset.UtcNow.AddDays(refreshDays)
        });
    }
    public static void Clear(HttpResponse resp) => resp.Cookies.Delete(CookieName,new CookieOptions{Path="/",Secure=true,SameSite=SameSiteMode.Strict});
    public static (Guid Sid,string Token)? Read(HttpRequest req)
    {
        if (!req.Cookies.TryGetValue(CookieName,out var value) || string.IsNullOrWhiteSpace(value)) return null;
        var dot=value.IndexOf('.');
        if(dot<0 || !Guid.TryParse(value[..dot],out var sid) || value.Length-dot-1<32 || value.Length>150) return null;
        return(sid,value[(dot+1)..]);
    }
}
