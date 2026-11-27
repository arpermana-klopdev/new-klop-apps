using KLOP.Platform.Api;
using KLOP.Platform.Application;
using Microsoft.AspNetCore.Http;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class RefreshCookieTests
{
    [Fact]
    public void SetWritesTheProtectedCookieAndReadReturnsItsSession()
    {
        var context = new DefaultHttpContext();
        var sessionId = Guid.NewGuid();
        const string refreshToken = "0123456789abcdef0123456789abcdef";
        var session = new AuthenticatedSession(new AccessResult("access-token", 600), sessionId, refreshToken, 30);

        RefreshCookies.Set(context.Response, session);

        var cookieHeader = context.Response.Headers.SetCookie.ToString();
        Assert.Contains($"{RefreshCookies.CookieName}={sessionId:D}.{refreshToken}", cookieHeader);
        Assert.Contains("path=/", cookieHeader, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("secure", cookieHeader, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("httponly", cookieHeader, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("samesite=strict", cookieHeader, StringComparison.OrdinalIgnoreCase);

        context.Request.Headers.Cookie = $"{RefreshCookies.CookieName}={sessionId:D}.{refreshToken}";
        var parsed = RefreshCookies.Read(context.Request);
        Assert.Equal(sessionId, parsed?.SessionId);
        Assert.Equal(refreshToken, parsed?.Token);
    }
}