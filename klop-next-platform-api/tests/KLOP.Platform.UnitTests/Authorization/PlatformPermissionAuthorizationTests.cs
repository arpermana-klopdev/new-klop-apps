using System.Security.Claims;
using KLOP.Platform.Api;
using KLOP.Platform.Application;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class PlatformPermissionAuthorizationTests
{
    [Fact]
    public async Task RegistrationPermissionDiscoveryReturnsOnlyTheEffectiveRegistrationCapability()
    {
        var repository = new TestPlatformPermissionRepository
        {
            EffectivePermissions =
            [
                PlatformRegistrationPermissions.Read,
                PlatformLegalDocumentPermissions.Read,
                PlatformRegistrationPermissions.Read
            ]
        };
        var service = new PlatformRegistrationPermissionService(repository);

        var result = await service.Get(41, Guid.NewGuid(), CancellationToken.None);

        Assert.Equal([PlatformRegistrationPermissions.Read], result.Permissions);
    }

    [Fact]
    public async Task PlatformPermissionRequiresRepositoryValidationForAuthenticatedUserAndSession()
    {
        var sessionId = Guid.NewGuid();
        var repository = new TestPlatformPermissionRepository();
        var services = new ServiceCollection()
            .AddLogging()
            .AddAuthorization()
            .AddSingleton<IPlatformPermissionRepository>(repository)
            .AddSingleton<IAuthorizationHandler, PlatformPermissionHandler>()
            .BuildServiceProvider();
        var principal = Principal("41", sessionId.ToString("D"));
        var authorization = services.GetRequiredService<IAuthorizationService>();
        var result = await authorization.AuthorizeAsync(
            principal,
            new DefaultHttpContext { User = principal },
            new PlatformPermissionRequirement(PlatformLegalDocumentPermissions.Publish));

        Assert.True(result.Succeeded);
        Assert.Equal((41L, sessionId, PlatformLegalDocumentPermissions.Publish),
            repository.ValidatedPermission);
    }

    [Fact]
    public async Task RegistrationReadPermissionIsValidatedAgainstTheActivePlatformSession()
    {
        var sessionId = Guid.NewGuid();
        var repository = new TestPlatformPermissionRepository();
        var services = new ServiceCollection()
            .AddLogging()
            .AddAuthorization()
            .AddSingleton<IPlatformPermissionRepository>(repository)
            .AddSingleton<IAuthorizationHandler, PlatformPermissionHandler>()
            .BuildServiceProvider();
        var principal = Principal("41", sessionId.ToString("D"));
        var authorization = services.GetRequiredService<IAuthorizationService>();

        var result = await authorization.AuthorizeAsync(
            principal,
            new DefaultHttpContext { User = principal },
            new PlatformPermissionRequirement(PlatformRegistrationPermissions.Read));

        Assert.True(result.Succeeded);
        Assert.Equal((41L, sessionId, PlatformRegistrationPermissions.Read),
            repository.ValidatedPermission);
    }

    [Fact]
    public async Task PlatformPermissionFailsClosedWhenAuthenticatedIdentityIsIncomplete()
    {
        var repository = new TestPlatformPermissionRepository();
        var services = new ServiceCollection()
            .AddLogging()
            .AddAuthorization()
            .AddSingleton<IPlatformPermissionRepository>(repository)
            .AddSingleton<IAuthorizationHandler, PlatformPermissionHandler>()
            .BuildServiceProvider();
        var principal = Principal("41", "invalid-session");
        var authorization = services.GetRequiredService<IAuthorizationService>();

        var result = await authorization.AuthorizeAsync(
            principal,
            new DefaultHttpContext { User = principal },
            new PlatformPermissionRequirement(PlatformLegalDocumentPermissions.Read));

        Assert.False(result.Succeeded);
        Assert.Null(repository.ValidatedPermission);
    }

    private static ClaimsPrincipal Principal(string userId, string sessionId) =>
        new(new ClaimsIdentity(
        [
            new Claim("sub", userId),
            new Claim("sid", sessionId)
        ], "Bearer"));

    private sealed class TestPlatformPermissionRepository : IPlatformPermissionRepository
    {
        public (long UserId, Guid SessionId, string PermissionCode)? ValidatedPermission { get; private set; }
        public IReadOnlyList<string> EffectivePermissions { get; init; } = [];

        public Task ValidatePlatformPermission(long userId, Guid sessionId, string permissionCode,
            CancellationToken cancellationToken)
        {
            ValidatedPermission = (userId, sessionId, permissionCode);
            return Task.CompletedTask;
        }

        public Task<IReadOnlyList<string>> GetPlatformPermissions(long userId, Guid sessionId,
            CancellationToken cancellationToken) => Task.FromResult(EffectivePermissions);
    }
}
