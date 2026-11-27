using System.Security.Claims;
using KLOP.Platform.Api;
using Microsoft.AspNetCore.Http;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class ApiHelpersIdentityTests
{
    [Fact]
    public void IdentityReadsSubjectAndSessionFromPrincipal()
    {
        var sessionId = Guid.NewGuid();
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("sub", "7"),
            new Claim("sid", sessionId.ToString("D"))
        ], "Bearer"));

        Assert.Equal((7L, sessionId), ApiHelpers.Identity(principal));
    }

    [Fact]
    public void IdentityReturnsNullWhenEitherClaimIsInvalid()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("sub", "not-a-user-id"),
            new Claim("sid", "not-a-session-id")
        ], "Bearer"));

        Assert.Null(ApiHelpers.Identity(principal));
    }

    [Fact]
    public void IdentityFromHttpContextReadsItsUserPrincipal()
    {
        var sessionId = Guid.NewGuid();
        var context = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(
            [
                new Claim("sub", "7"),
                new Claim("sid", sessionId.ToString("D"))
            ], "Bearer"))
        };

        Assert.Equal((7L, sessionId), ApiHelpers.Identity(context));
    }
}