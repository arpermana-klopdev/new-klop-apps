using KLOP.Platform.Application;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class SystemConfigurationServiceTests
{
    [Theory]
    [InlineData("unclassified.secret", 30)]
    [InlineData("smtp.password", 30)]
    [InlineData("database.command_timeout_seconds", 0)]
    [InlineData("database.command_timeout_seconds", 121)]
    public async Task DraftRejectsUnclassifiedKeysAndOutOfRangeValues(string key, int value)
    {
        var repository = new FakeConfigurationRepository();
        var permissions = new FakePlatformPermissionRepository();
        var service = new SystemConfigurationService(repository, permissions);

        await Assert.ThrowsAsync<ArgumentException>(() => service.CreateDraft(
            new SystemConfigurationDraftRequest(key, value, 1, "AQIDBAUGBwg=", "ROUTINE_MAINTENANCE"),
            12, Guid.NewGuid(), new RequestMetadata("request", Guid.NewGuid()), CancellationToken.None));

        Assert.Equal(0, repository.CreateDraftCalls);
        Assert.Empty(permissions.Validated);
    }

    [Fact]
    public async Task DraftRejectsMalformedConcurrencyBeforeRepositoryAccess()
    {
        var repository = new FakeConfigurationRepository();
        var permissions = new FakePlatformPermissionRepository();
        var service = new SystemConfigurationService(repository, permissions);

        await Assert.ThrowsAsync<ArgumentException>(() => service.CreateDraft(
            new SystemConfigurationDraftRequest("database.command_timeout_seconds", 60, 1, "not-a-rowversion",
                "CAPACITY_ADJUSTMENT"),
            12, Guid.NewGuid(), new RequestMetadata("request", Guid.NewGuid()), CancellationToken.None));

        Assert.Equal(0, repository.CreateDraftCalls);
    }

    [Fact]
    public async Task ValidTypedCandidateIsPassedWithVerifiedActorAndDecodedVersion()
    {
        var repository = new FakeConfigurationRepository();
        var permissions = new FakePlatformPermissionRepository();
        var service = new SystemConfigurationService(repository, permissions);
        var session = Guid.NewGuid();

        var result = await service.CreateDraft(
            new SystemConfigurationDraftRequest("database.command_timeout_seconds", 120, 4,
                "AQIDBAUGBwg=", "INCIDENT_FOLLOWUP"),
            12, session, new RequestMetadata("request", Guid.NewGuid()), CancellationToken.None);

        Assert.NotEqual(Guid.Empty, result.RequestId);
        Assert.Equal(1, repository.CreateDraftCalls);
        Assert.Equal(120, repository.LastDraft?.ProposedInteger);
        Assert.Equal(12, repository.LastActorUserId);
        Assert.Equal(session, repository.LastSessionId);
        Assert.Equal("platform.configurations.request.create", Assert.Single(permissions.Validated));
        Assert.Equal(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 }, repository.LastTargetRowVersion);
    }

    [Fact]
    public async Task ApprovalQueueRequiresReadAndIndependentApprovePermission()
    {
        var repository = new FakeConfigurationRepository();
        var permissions = new FakePlatformPermissionRepository
        {
            DeniedPermission = SystemConfigurationPermissions.Approve
        };
        var service = new SystemConfigurationService(repository, permissions);

        await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            service.Approvals(1, 25, 12, Guid.NewGuid(), CancellationToken.None));

        Assert.Equal(
            [SystemConfigurationPermissions.Read, SystemConfigurationPermissions.Approve],
            permissions.Validated);
        Assert.Equal(0, repository.GetRequestsCalls);
    }

    private sealed class FakePlatformPermissionRepository : IPlatformPermissionRepository
    {
        public List<string> Validated { get; } = [];
        public string? DeniedPermission { get; init; }

        public Task ValidatePlatformPermission(long userId, Guid sessionId, string permissionCode,
            CancellationToken cancellationToken)
        {
            Validated.Add(permissionCode);
            return permissionCode == DeniedPermission
                ? Task.FromException(new UnauthorizedAccessException("denied"))
                : Task.CompletedTask;
        }

        public Task<IReadOnlyList<string>> GetPlatformPermissions(long userId, Guid sessionId,
            CancellationToken cancellationToken) => Task.FromResult<IReadOnlyList<string>>([]);
    }

    private sealed class FakeConfigurationRepository : ISystemConfigurationRepository
    {
        public int CreateDraftCalls { get; private set; }
        public int GetRequestsCalls { get; private set; }
        public SystemConfigurationDraftRequest? LastDraft { get; private set; }
        public byte[]? LastTargetRowVersion { get; private set; }
        public long LastActorUserId { get; private set; }
        public Guid LastSessionId { get; private set; }

        public Task<SystemConfigurationCatalogPage> GetCatalog(string? category, int pageNumber, int pageSize,
            long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
            Task.FromResult(new SystemConfigurationCatalogPage([], pageNumber, pageSize, 0, 0));

        public Task<SystemConfigurationRequestPage> GetRequests(string status, int pageNumber, int pageSize,
            long actorUserId, Guid sessionId, CancellationToken cancellationToken)
        {
            GetRequestsCalls++;
            return Task.FromResult(new SystemConfigurationRequestPage([], pageNumber, pageSize, 0));
        }

        public Task<SystemConfigurationHistoryPage> GetHistory(int pageNumber, int pageSize,
            long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
            Task.FromResult(new SystemConfigurationHistoryPage([], pageNumber, pageSize, 0));

        public Task<SystemConfigurationDraftResult> CreateDraft(SystemConfigurationDraftRequest request,
            byte[] targetConcurrencyVersion, long actorUserId, Guid sessionId, RequestMetadata metadata,
            CancellationToken cancellationToken)
        {
            CreateDraftCalls++;
            LastDraft = request;
            LastTargetRowVersion = targetConcurrencyVersion;
            LastActorUserId = actorUserId;
            LastSessionId = sessionId;
            return Task.FromResult(new SystemConfigurationDraftResult(Guid.NewGuid(), "AQIDBAUGBwg="));
        }

        public Task<SystemConfigurationDraftResult> UpdateDraft(Guid requestId,
            SystemConfigurationDraftUpdate request, byte[] requestConcurrencyVersion, long actorUserId,
            Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) =>
            Task.FromResult(new SystemConfigurationDraftResult(requestId, "AQIDBAUGBwg="));

        public Task<SystemConfigurationDraftResult> Transition(Guid requestId, string action, string? decision,
            byte[] requestConcurrencyVersion, long actorUserId, Guid sessionId, RequestMetadata metadata,
            CancellationToken cancellationToken) =>
            Task.FromResult(new SystemConfigurationDraftResult(requestId, "AQIDBAUGBwg="));

        public Task<SystemConfigurationDraftResult> Apply(Guid requestId, byte[] requestConcurrencyVersion,
            long actorUserId, Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken) =>
            Task.FromResult(new SystemConfigurationDraftResult(requestId, "AQIDBAUGBwg="));
    }
}
