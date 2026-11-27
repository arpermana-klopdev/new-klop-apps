using KLOP.Platform.Application;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class NotificationSqlContractTests
{
    [Fact]
    public void NotificationCapabilitiesAreIntegratedIntoBothV110AuthorizationProcedures()
    {
        var delta = ReadMigration("v1.11/006_notification_authorization_delta_APPROVAL_TEMPLATE.sql");
        var expected = new[]
        {
            "platform.notifications.read",
            "platform.notifications.draft.create",
            "platform.notifications.draft.edit",
            "platform.notifications.draft.preview",
            "platform.notifications.submit",
            "platform.notifications.approve",
            "platform.notifications.activate",
            "platform.notifications.archive",
            "platform.notifications.history",
            "platform.notifications.settings.read"
        };

        Assert.Equal(expected.Order(), NotificationPermissions.All.Order());
        foreach (var permission in expected)
            Assert.True(CountOccurrences(delta, $"'{permission}'") >= 3, $"{permission} is absent from one SQL contract.");

        Assert.Contains("iam.usp_ValidateSessionAccess", delta, StringComparison.Ordinal);
        Assert.Contains("readiness.AllowsEffective=1", delta, StringComparison.Ordinal);
        Assert.Contains("matrix.ReadinessCode<>'HOLD'", delta, StringComparison.Ordinal);
        Assert.DoesNotContain("INSERT mst.RolePermissions", delta, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void NotificationLifecycleSqlRetainsConcurrencyAndAuditInvariants()
    {
        var procedures = ReadMigration("v1.11/002_notification_procedures_APPROVAL_TEMPLATE.sql");
        var schema = ReadMigration("v1.11/001_notification_schema_APPROVAL_TEMPLATE.sql");

        Assert.Contains("WHERE TemplateVersionId=@TemplateVersionId AND StatusCode='DRAFT'", procedures, StringComparison.Ordinal);
        Assert.Contains("AND RowVersion=@ExpectedVersion", procedures, StringComparison.Ordinal);
        Assert.Contains("WITH(UPDLOCK,HOLDLOCK)", procedures, StringComparison.Ordinal);
        Assert.Contains("AUTO_ARCHIVED_BY_ACTIVATION", procedures, StringComparison.Ordinal);
        Assert.Contains("UX_NotificationTemplateVersions_OneActive", schema, StringComparison.Ordinal);
        Assert.Contains("FK_NotificationTemplateVersionVariables_Version", schema, StringComparison.Ordinal);
        Assert.Contains("FK_NotificationTemplateApprovals_Actor", schema, StringComparison.Ordinal);
        Assert.Contains("CK_NotificationDeliveryAttempts_Outcome", schema, StringComparison.Ordinal);
        Assert.DoesNotContain("RecipientMetadata", schema, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("RecipientMetadata", procedures, StringComparison.OrdinalIgnoreCase);
    }

    private static string ReadMigration(string relativePath)
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var candidate = Path.Combine(directory.FullName, "klop-next-platform-api", "database", "migrations", relativePath);
            if (File.Exists(candidate))
                return File.ReadAllText(candidate);
        }

        throw new FileNotFoundException($"Could not locate SQL migration {relativePath}.");
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
