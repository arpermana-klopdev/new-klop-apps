using Xunit;

namespace KLOP.Platform.IntegrationTests;

public sealed class SqlServerFactAttribute : FactAttribute
{
    public SqlServerFactAttribute()
    {
        var explicitlyAllowed =
            Environment.GetEnvironmentVariable("KLOP_TEST_ALLOW_MUTATION") ==
            "I_UNDERSTAND_TEST_DATA_IS_PERSISTENT";
        var server = Environment.GetEnvironmentVariable("KLOP_TEST_SQL_SERVER");
        var database = Environment.GetEnvironmentVariable("KLOP_TEST_SQL_DATABASE");
        var approvalTicket = Environment.GetEnvironmentVariable("KLOP_TEST_APPROVAL_TICKET");
        if (!explicitlyAllowed ||
            !string.Equals(server, "DEV-PC\\SQLEXPRESS", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(database, "KlopPlatformDB_TEST", StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(approvalTicket))
        {
            Skip = "NOT RUN: explicit approval, the exact _TEST database, and its dedicated SQL identity are required.";
        }
    }
}
