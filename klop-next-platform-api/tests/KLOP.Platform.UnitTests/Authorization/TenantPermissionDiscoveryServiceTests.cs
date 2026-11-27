using KLOP.Platform.Application;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class TenantPermissionDiscoveryServiceTests
{
    [Fact]
    public async Task ReturnsDistinctPermissionsForTheAuthenticatedSessionAndSelectedTenant()
    {
        var userId = 41L;
        var sessionId = Guid.NewGuid();
        var repository = new TestTenantPermissionRepository(
        [
            "tenant.members.remove",
            "tenant.members.invite",
            "tenant.members.invite"
        ]);
        var service = new TenantPermissionDiscoveryService(repository);

        var response = await service.Get(userId, sessionId, 73, CancellationToken.None);

        Assert.Equal((userId, sessionId, 73L), repository.Request);
        Assert.Equal(["tenant.members.invite", "tenant.members.remove"], response.Permissions);
    }

    private sealed class TestTenantPermissionRepository(IReadOnlyList<string> permissions)
        : ITenantPermissionRepository
    {
        public (long UserId, Guid SessionId, long TenantId) Request { get; private set; }

        public Task<IReadOnlyList<string>> GetTenantPermissions(long userId, Guid sessionId, long tenantId,
            CancellationToken cancellationToken)
        {
            Request = (userId, sessionId, tenantId);
            return Task.FromResult(permissions);
        }
    }
}
