using KLOP.Platform.Application;
using System.Text.Json;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class RolePermissionMatrixServiceTests
{
    [Fact]
    public async Task AccountPolicyIsReturnedAsReadOnlyInformationWithoutRoleColumns()
    {
        var repository = new TestRolePermissionMatrixRepository
        {
            Rows =
            [
                new RolePermissionMatrixDbRow
                {
                    PermissionId = 7,
                    Module = "account",
                    Resource = "self_service.profile",
                    Action = "read",
                    PermissionCode = "account.self_service.profile.read",
                    PermissionName = "View own account",
                    PermissionDescription = "Read the authenticated account profile.",
                    ScopeCode = "ACCOUNT",
                    ReadinessStatus = "ACTIVE",
                    IsAccountPolicy = true,
                    PublicAllowed = false,
                    UnverifiedAllowed = false,
                    VerifiedAllowed = true
                }
            ]
        };
        var service = new RolePermissionMatrixService(repository, new TestPlatformPermissionRepository());

        var response = await service.Get(41, Guid.NewGuid(), CancellationToken.None);

        var row = Assert.Single(response.Rows);
        Assert.Empty(response.Columns);
        Assert.Empty(row.Cells);
        Assert.Equal(new AccountPermissionPolicy(false, false, true), row.AccountPolicy);
    }

    [Fact]
    public async Task ValidationRejectsMalformedConcurrencyVersionBeforeCallingRepository()
    {
        var repository = new TestRolePermissionMatrixRepository();
        var service = new RolePermissionMatrixService(repository, new TestPlatformPermissionRepository());
        var request = new RolePermissionMatrixBatchRequest(
            "Approved change reason",
            [new RolePermissionMatrixChange(7, 2, null, true, "not-base64!")]);

        await Assert.ThrowsAsync<ArgumentException>(() =>
            service.Validate(41, Guid.NewGuid(), request, CancellationToken.None));

        Assert.False(repository.ValidationCalled);
    }

    [Fact]
    public async Task ValidationEncodesConcurrencyVersionForSqlBinaryComparison()
    {
        var repository = new TestRolePermissionMatrixRepository();
        var service = new RolePermissionMatrixService(repository, new TestPlatformPermissionRepository());
        var version = Convert.ToBase64String([0, 1, 2, 3, 4, 5, 6, 7]);
        var request = new RolePermissionMatrixBatchRequest(
            "Approved change reason",
            [new RolePermissionMatrixChange(7, 2, null, true, version)]);

        await service.Validate(41, Guid.NewGuid(), request, CancellationToken.None);

        using var document = JsonDocument.Parse(repository.ChangesJson!);
        Assert.Equal("0x0001020304050607",
            document.RootElement[0].GetProperty("concurrencyVersion").GetString());
    }

    [Fact]
    public async Task ValidationRejectsNullBatchEntryBeforeCallingRepository()
    {
        var repository = new TestRolePermissionMatrixRepository();
        var service = new RolePermissionMatrixService(repository, new TestPlatformPermissionRepository());
        var request = new RolePermissionMatrixBatchRequest("Approved change reason", [null!]);

        await Assert.ThrowsAsync<ArgumentException>(() =>
            service.Validate(41, Guid.NewGuid(), request, CancellationToken.None));

        Assert.False(repository.ValidationCalled);
    }

    [Fact]
    public async Task MatrixColumnsFollowPlatformPersonalOrganizationOrder()
    {
        var repository = new TestRolePermissionMatrixRepository
        {
            Rows =
            [
                new RolePermissionMatrixDbRow { PermissionCode = "tenant.example", RoleId = 3,
                    RoleCode = "OWNER", RoleName = "Owner", RoleScopeCode = "TENANT",
                    TenantTypeId = 2, TenantTypeCode = "ORGANIZATION" },
                new RolePermissionMatrixDbRow { PermissionCode = "tenant.example", RoleId = 3,
                    RoleCode = "OWNER", RoleName = "Owner", RoleScopeCode = "TENANT",
                    TenantTypeId = 1, TenantTypeCode = "PERSONAL" },
                new RolePermissionMatrixDbRow { PermissionCode = "platform.example", RoleId = 1,
                    RoleCode = "SUPER_ADMIN", RoleName = "Super Administrator", RoleScopeCode = "PLATFORM" }
            ]
        };
        var service = new RolePermissionMatrixService(repository, new TestPlatformPermissionRepository());

        var response = await service.Get(41, Guid.NewGuid(), CancellationToken.None);

        Assert.Equal(new[] { "PLATFORM", "PERSONAL", "ORGANIZATION" },
            response.Columns.Select(column => column.TenantTypeCode ?? column.ScopeCode).ToArray());
    }

    private sealed class TestRolePermissionMatrixRepository : IRolePermissionMatrixRepository
    {
        public IReadOnlyList<RolePermissionMatrixDbRow> Rows { get; init; } = [];
        public bool ValidationCalled { get; private set; }
        public string? ChangesJson { get; private set; }

        public Task<IReadOnlyList<RolePermissionMatrixDbRow>> GetRolePermissionMatrix(
            long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
            Task.FromResult(Rows);

        public Task<IReadOnlyList<RolePermissionMatrixValidationDbRow>> ValidateRolePermissionBatch(
            long actorUserId, Guid sessionId, string reason, string changesJson,
            CancellationToken cancellationToken)
        {
            ValidationCalled = true;
            ChangesJson = changesJson;
            return Task.FromResult<IReadOnlyList<RolePermissionMatrixValidationDbRow>>([]);
        }

        public Task<RolePermissionMatrixSaveDbRow?> SaveRolePermissionBatch(
            long actorUserId, Guid sessionId, string reason, string changesJson,
            RequestMetadata metadata, CancellationToken cancellationToken) =>
            Task.FromResult<RolePermissionMatrixSaveDbRow?>(new RolePermissionMatrixSaveDbRow());

        public Task<IReadOnlyList<RolePermissionMatrixHistoryDbRow>> GetRolePermissionHistory(
            long actorUserId, Guid sessionId, int pageNumber, int pageSize,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<RolePermissionMatrixHistoryDbRow>>([]);
    }

    private sealed class TestPlatformPermissionRepository : IPlatformPermissionRepository
    {
        public Task ValidatePlatformPermission(long userId, Guid sessionId, string permissionCode,
            CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<IReadOnlyList<string>> GetPlatformPermissions(long userId, Guid sessionId,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<string>>([]);
    }
}
