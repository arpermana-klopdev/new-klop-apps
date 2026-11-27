using KLOP.Platform.Application;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class PlatformRegistrationServiceTests
{
    [Fact]
    public async Task ListingNormalizesFiltersAndPreservesServerSidePaging()
    {
        var repository = new RegistrationRepositoryStub();
        var service = new PlatformRegistrationService(repository);
        var query = new PlatformRegistrationListQuery
        {
            RegistrationType = " personal ",
            Search = "  applicant@example.test  ",
            EmailVerificationStatus = " pending ",
            ApplicationStatus = " draft ",
            PageNumber = 3,
            PageSize = 25
        };

        var result = await service.List(query, 42, Guid.NewGuid(), CancellationToken.None);

        Assert.Equal("PERSONAL", repository.ListQuery?.RegistrationType);
        Assert.Equal("applicant@example.test", repository.ListQuery?.Search);
        Assert.Equal("PENDING", repository.ListQuery?.EmailVerificationStatus);
        Assert.Equal("DRAFT", repository.ListQuery?.ApplicationStatus);
        Assert.Equal(3, repository.ListQuery?.PageNumber);
        Assert.Equal(25, repository.ListQuery?.PageSize);
        Assert.Single(result.Items);
        Assert.Equal(3, result.PageNumber);
        Assert.Equal(25, result.PageSize);
        Assert.Equal(57, result.TotalCount);
        Assert.Equal(3, result.TotalPages);
        Assert.Equal(["DRAFT", "IN_REVIEW", "APPROVED"], result.ApplicationStatuses);
    }

    private sealed class RegistrationRepositoryStub : IPlatformRegistrationRepository
    {
        public PlatformRegistrationListQuery? ListQuery { get; private set; }

        public Task<PlatformRegistrationSummary?> GetPlatformRegistrationSummary(string registrationType,
            long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
            Task.FromResult<PlatformRegistrationSummary?>(null);

        public Task<PlatformRegistrationPage> ListPlatformRegistrations(PlatformRegistrationListQuery query,
            long actorUserId, Guid sessionId, CancellationToken cancellationToken)
        {
            ListQuery = new PlatformRegistrationListQuery
            {
                RegistrationType = query.RegistrationType,
                Search = query.Search,
                EmailVerificationStatus = query.EmailVerificationStatus,
                ApplicationStatus = query.ApplicationStatus,
                PageNumber = query.PageNumber,
                PageSize = query.PageSize
            };
            return Task.FromResult(new PlatformRegistrationPage(
                [
                    new PlatformRegistrationListItem(7, "Applicant", "applicant@example.test", null,
                        "DRAFT", "PERSONAL", DateTime.SpecifyKind(DateTime.UnixEpoch, DateTimeKind.Utc))
                ],
                3,
                25,
                57,
                3,
                ["DRAFT", "IN_REVIEW", "APPROVED"]));
        }

        public Task<PlatformRegistrationDetailRow?> GetPlatformRegistration(long registrationApplicationId,
            long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
            Task.FromResult<PlatformRegistrationDetailRow?>(null);

        public Task<IReadOnlyList<PlatformRegistrationTimelineEvent>> GetPlatformRegistrationTimeline(
            long registrationApplicationId, long actorUserId, Guid sessionId,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<PlatformRegistrationTimelineEvent>>([]);
    }
}
