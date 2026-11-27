-- Read-only preflight proposal for Notification Management v1.11.
-- Run only against an owner-selected environment. This script makes no changes.
SET NOCOUNT ON;

SELECT @@SERVERNAME AS ServerName, DB_NAME() AS DatabaseName,
       N'READ ONLY - no v1.11 migration, seed, permission mapping, grant, or SMTP value is applied' AS Scope;

SELECT prerequisite.Name,
       CASE WHEN prerequisite.ObjectId IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS Status
FROM
(
    VALUES
        (N'cfg.SystemConfigurations', OBJECT_ID(N'cfg.SystemConfigurations', N'U')),
        (N'aud.AuditEvents', OBJECT_ID(N'aud.AuditEvents', N'U')),
        (N'mst.AuditActionTypes', OBJECT_ID(N'mst.AuditActionTypes', N'U')),
        (N'mst.AuditResultTypes', OBJECT_ID(N'mst.AuditResultTypes', N'U')),
        (N'mst.Permissions', OBJECT_ID(N'mst.Permissions', N'U')),
        (N'iam.usp_ValidatePlatformPermission', OBJECT_ID(N'iam.usp_ValidatePlatformPermission', N'P')),
        (N'cfg.usp_Configuration_GetByKey', OBJECT_ID(N'cfg.usp_Configuration_GetByKey', N'P'))
) prerequisite(Name, ObjectId)
ORDER BY prerequisite.Name;

SELECT N'ntf' AS ProposedSchema,
       CASE WHEN SCHEMA_ID(N'ntf') IS NULL THEN N'AVAILABLE' ELSE N'EXISTS - MANUAL RECONCILIATION REQUIRED' END AS Status;

IF OBJECT_ID(N'cfg.SystemConfigurations',N'U') IS NOT NULL
    SELECT Expected.ConfigurationKey,
           CASE WHEN Existing.ConfigurationId IS NULL THEN N'ABSENT - rollout remains disabled'
                WHEN Existing.ValueType <> 'BOOLEAN' OR Existing.StorageType <> 'PLAIN'
                    THEN N'PRESENT WITH INVALID TYPE - startup must fail closed'
                WHEN Existing.ConfigurationValue = N'true' THEN N'PRESENT - rollout enabled; owner approval required'
                WHEN Existing.ConfigurationValue = N'false' THEN N'PRESENT - rollout disabled'
                ELSE N'PRESENT WITH INVALID VALUE - startup must fail closed' END AS Status
    FROM (VALUES (N'notification.email_verification_templates.enabled')) Expected(ConfigurationKey)
    LEFT JOIN cfg.SystemConfigurations Existing
      ON Existing.ConfigurationKey = Expected.ConfigurationKey AND Existing.IsActive = 1;
GO
