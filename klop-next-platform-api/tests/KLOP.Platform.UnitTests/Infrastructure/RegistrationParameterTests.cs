using KLOP.Platform.Infrastructure;
using Xunit;

namespace KLOP.Platform.UnitTests.Infrastructure;

public sealed class RegistrationParameterTests
{
    [Theory]
    [InlineData("PERSONAL")]
    [InlineData("ORGANIZATION")]
    public void RegistrationParametersUseDisplayNameForBothRegistrationTypes(string registrationType)
    {
        var parameters = KlopRepository.BuildRegistrationParameters(
            "user@example.com",
            "Test User",
            "password-hash",
            new byte[32],
            DateTime.UtcNow.AddHours(1),
            "request-id",
            Guid.NewGuid(),
            registrationType,
            null,
            null,
            developmentTermsBypassEnabled: true);

        var names = parameters.ParameterNames.ToArray();
        Assert.Contains("DisplayName", names);
        Assert.DoesNotContain("FullName", names);
        Assert.Equal("Test User", parameters.Get<string>("DisplayName"));
        Assert.Equal(registrationType, parameters.Get<string>("RegistrationTypeCode"));
    }
}
