using KLOP.Platform.Application;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class SystemConfigurationSqlContractTests
{
    [Fact]
    public void AuthorizationDeltaAddsTheSameConfigurationPermissionSetToBothProcedures()
    {
        var delta = ReadMigration("v1.12/004_configuration_authorization_delta_APPROVAL_TEMPLATE.sql");
        foreach (var permission in SystemConfigurationPermissions.All)
            Assert.True(CountOccurrences(delta, $"'{permission}'") >= 3, $"{permission} is missing from the authorization delta.");

        Assert.Contains("iam.usp_ValidateSessionAccess", delta, StringComparison.Ordinal);
        Assert.Contains("readiness.AllowsEffective=1", delta, StringComparison.Ordinal);
        Assert.Contains("assignment.UserId=@ActorUserId", delta, StringComparison.Ordinal);
        Assert.DoesNotContain("INSERT mst.RolePermissions", delta, StringComparison.OrdinalIgnoreCase);
        foreach (var prior in new[]
                 {
                     "platform.legal_documents.read", "platform.role_permissions.read",
                     "platform.role_permissions.update", "platform.notifications.read",
                     "platform.notifications.settings.read", "platform.registrations.read"
                 })
            Assert.True(CountOccurrences(delta, $"'{prior}'") >= 2, $"{prior} was not preserved.");
    }

    [Fact]
    public void CandidatePolicyIsLockedAndOnlyItsBoundedIntegerValueCanBeWritten()
    {
        var schema = ReadMigration("v1.12/001_configuration_schema_APPROVAL_TEMPLATE.sql");
        var procedures = ReadMigration("v1.12/002_configuration_procedures_APPROVAL_TEMPLATE.sql");

        Assert.Contains("'database.command_timeout_seconds','Database','INTEGER','PLAIN',1,1,120", schema,
            StringComparison.Ordinal);
        Assert.Contains("MinimumInteger,MaximumInteger,IsManageable,ManagementStatus", schema,
            StringComparison.Ordinal);
        Assert.Contains("SELECT @TargetVersion=VersionNumber", procedures, StringComparison.Ordinal);
        Assert.Contains("@Manageable<>1 OR @PolicyStatus<>'ACTIVE'", procedures, StringComparison.Ordinal);
        Assert.Equal(4, CountOccurrences(procedures, "@ProposedInteger NOT BETWEEN 1 AND 120"));
        Assert.Equal(4, CountOccurrences(procedures, "ISNULL(@Minimum,0)<>1 OR ISNULL(@Maximum,0)<>120"));
        Assert.Contains("@ProposedInteger NOT BETWEEN @Minimum AND @Maximum", procedures,
            StringComparison.Ordinal);
        Assert.Contains("IsEditable=1 AND IsSensitive=0", procedures, StringComparison.Ordinal);
        Assert.Contains("VersionNumber=VersionNumber+1", procedures, StringComparison.Ordinal);
        Assert.DoesNotContain("UPDATE cfg.SystemConfigurations", schema, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void LifecycleUsesIndependentApprovalApplyConcurrencyAndTransactionalAudit()
    {
        var schema = ReadMigration("v1.12/001_configuration_schema_APPROVAL_TEMPLATE.sql");
        var procedures = ReadMigration("v1.12/002_configuration_procedures_APPROVAL_TEMPLATE.sql");

        Assert.Contains("RequestId UNIQUEIDENTIFIER", schema, StringComparison.Ordinal);
        Assert.Contains("UNIQUE(RequestId)", schema, StringComparison.Ordinal);
        Assert.Contains("trg_ConfigurationChangeRequests_Immutable", schema, StringComparison.Ordinal);
        Assert.Contains("trg_ConfigurationAppliedHistory_AppendOnly", schema, StringComparison.Ordinal);
        Assert.Contains("@Requester=@ActorUserId", procedures, StringComparison.Ordinal);
        Assert.Contains("@Requester=@ActorUserId OR @Approver IS NULL OR @Approver=@ActorUserId", procedures,
            StringComparison.Ordinal);
        Assert.Contains("WITH(UPDLOCK,HOLDLOCK)", procedures, StringComparison.Ordinal);
        Assert.Contains("INSERT cfg.ConfigurationAppliedHistory", procedures, StringComparison.Ordinal);
        Assert.Contains("INSERT aud.AuditEvents", procedures, StringComparison.Ordinal);
        Assert.Contains("IF XACT_STATE()<>0 ROLLBACK TRANSACTION", procedures, StringComparison.Ordinal);
        Assert.Contains("ORDER BY history.OccurredAtUtc DESC,history.HistoryId DESC", procedures,
            StringComparison.Ordinal);
    }

    [Fact]
    public void ReadProjectionUsesAnExplicitSafeAllowlistAndNeverReturnsRawConfigurationValues()
    {
        var procedures = ReadMigration("v1.12/002_configuration_procedures_APPROVAL_TEMPLATE.sql");
        var catalogProcedure = procedures[..procedures.IndexOf("CREATE OR ALTER PROCEDURE cfg.usp_ConfigurationManagement_ListRequests",
            StringComparison.Ordinal)];
        var schema = ReadMigration("v1.12/001_configuration_schema_APPROVAL_TEMPLATE.sql");

        Assert.Contains("@ApprovedCatalog", catalogProcedure, StringComparison.Ordinal);
        Assert.Contains("UnclassifiedCount", catalogProcedure, StringComparison.Ordinal);
        Assert.DoesNotContain("SELECT config.ConfigurationValue", catalogProcedure, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("smtp.", catalogProcedure, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("keyvault", catalogProcedure, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("jwt.", catalogProcedure, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("ConfigurationValue=CONVERT(NVARCHAR(20),@ProposedInteger)", procedures,
            StringComparison.Ordinal);
        Assert.DoesNotContain("GRANT SELECT", schema, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void PermissionSeedIsHoldOnlyAndRuntimeGrantProposalIsExecuteOnly()
    {
        var seed = ReadMigration("v1.12/003_configuration_permissions_APPROVAL_TEMPLATE.sql");
        var grants = ReadSecurityTemplate("v1.12_configuration_runtime_grants_APPROVAL_TEMPLATE.sql");
        var postdeploy = ReadMigration("v1.12/005_configuration_postdeploy_READONLY.sql");

        Assert.Contains("WHERE matrix.ReadinessCode<>'HOLD'", seed, StringComparison.Ordinal);
        Assert.DoesNotContain("INSERT mst.RolePermissions", seed, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("GRANT EXECUTE ON OBJECT::", grants, StringComparison.Ordinal);
        Assert.DoesNotContain("GRANT SELECT", grants, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("GRANT INSERT", grants, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("UNASSIGNED", postdeploy, StringComparison.Ordinal);
        Assert.Contains("policy.ManagementStatus,policy.IsManageable", postdeploy, StringComparison.Ordinal);
    }

    private static string ReadMigration(string relativePath) => ReadDatabaseFile("migrations/" + relativePath);

    private static string ReadSecurityTemplate(string fileName) => ReadDatabaseFile("security/" + fileName);

    private static string ReadDatabaseFile(string relativePath)
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var candidate = Path.Combine(directory.FullName, "klop-next-platform-api", "database", relativePath);
            if (File.Exists(candidate))
                return File.ReadAllText(candidate);
        }

        throw new FileNotFoundException($"Could not locate SQL contract {relativePath}.");
    }

    private static int CountOccurrences(string text, string value)
    {
        var count = 0;
        var index = 0;
        while ((index = text.IndexOf(value, index, StringComparison.Ordinal)) >= 0)
        {
            count++;
            index += value.Length;
        }

        return count;
    }
}
