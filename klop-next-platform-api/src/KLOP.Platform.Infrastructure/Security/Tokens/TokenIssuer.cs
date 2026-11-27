using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using KLOP.Platform.Application;
using Microsoft.IdentityModel.Tokens;

namespace KLOP.Platform.Infrastructure;

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