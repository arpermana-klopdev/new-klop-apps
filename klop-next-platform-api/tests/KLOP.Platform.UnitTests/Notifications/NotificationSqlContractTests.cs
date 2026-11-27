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
        foreach (var existingPermission in new[]
                 {
                     "platform.legal_documents.read",
                     "platform.legal_documents.draft.create",
                     "platform.legal_documents.draft.edit",
                     "platform.legal_documents.draft.preview",
                     "platform.legal_documents.submit",
                     "platform.legal_documents.approve",
                     "platform.legal_documents.publish",
                     "platform.legal_documents.archive",
                     "platform.registrations.read",
                     "platform.role_permissions.read",
                     "platform.role_permissions.update"
                 })
            Assert.True(CountOccurrences(delta, $"'{existingPermission}'") >= 2,
                $"{existingPermission} was not preserved in both procedures.");
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
        Assert.Contains("a.AttemptId DESC", procedures, StringComparison.Ordinal);
        Assert.Contains("SELECT COUNT_BIG(*) AS TotalCount", procedures, StringComparison.Ordinal);
        Assert.Contains("t.LocaleCode COLLATE Latin1_General_100_BIN2=N'en'", procedures, StringComparison.Ordinal);
        Assert.DoesNotContain("RecipientMetadata", schema, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("RecipientMetadata", procedures, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ReadOnlyChecksCoverNotificationSchemaAuthorizationAndBothDefaultOffGates()
    {
        var preflight = ReadMigration("v1.11/000_notification_preflight_READONLY.sql");
        var postdeploy = ReadMigration("v1.11/005_notification_postdeploy_READONLY.sql");
        var expectedTables = new[]
        {
            "NotificationChannelStatuses", "NotificationChannels", "NotificationTemplateTypes",
            "NotificationTemplateStatuses", "NotificationVariableDefinitions", "NotificationTemplates",
            "NotificationTemplateVersions", "NotificationTemplateVersionVariables",
            "NotificationTemplateApprovals", "NotificationDeliveryOutcomes", "NotificationErrorCategories",
            "NotificationDeliveries", "NotificationDeliveryAttempts"
        };
        foreach (var table in expectedTables)
        {
            Assert.Contains($"ntf.{table}", preflight, StringComparison.Ordinal);
            Assert.Contains($"ntf.{table}", postdeploy, StringComparison.Ordinal);
        }

        foreach (var gate in new[]
                 {
                     "notification.email_verification_templates.enabled",
                     "notification.email_verification_delivery_audit.enabled"
                 })
        {
            Assert.Contains(gate, preflight, StringComparison.Ordinal);
            Assert.Contains(gate, postdeploy, StringComparison.Ordinal);
        }

        Assert.Contains("iam.usp_GetPlatformPermissions", preflight, StringComparison.Ordinal);
        Assert.Contains("RoleMapping", postdeploy, StringComparison.Ordinal);
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
