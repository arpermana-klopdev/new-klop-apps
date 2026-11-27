using KLOP.Platform.Application;

namespace KLOP.Platform.Api;

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
