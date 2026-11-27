-- Read-only post-deployment checks for the owner-reviewed v1.11 proposal.
SET NOCOUNT ON;

SELECT N'ntf.NotificationChannels' AS ObjectName,
       CASE WHEN OBJECT_ID(N'ntf.NotificationChannels',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS Status
UNION ALL SELECT N'ntf.NotificationTemplates',
       CASE WHEN OBJECT_ID(N'ntf.NotificationTemplates',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationTemplateVersions',
       CASE WHEN OBJECT_ID(N'ntf.NotificationTemplateVersions',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationDeliveries',
       CASE WHEN OBJECT_ID(N'ntf.NotificationDeliveries',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.NotificationDeliveryAttempts',
       CASE WHEN OBJECT_ID(N'ntf.NotificationDeliveryAttempts',N'U') IS NULL THEN N'MISSING' ELSE N'PRESENT' END
UNION ALL SELECT N'ntf.trg_NotificationTemplateVersions_ActiveImmutable',
       CASE WHEN OBJECT_ID(N'ntf.trg_NotificationTemplateVersions_ActiveImmutable',N'TR') IS NULL
            THEN N'MISSING' ELSE N'PRESENT' END;

IF OBJECT_ID(N'ntf.NotificationChannels',N'U') IS NOT NULL
    SELECT ChannelCode,IsEnabled,StatusCode FROM ntf.NotificationChannels ORDER BY ChannelCode;
IF OBJECT_ID(N'ntf.NotificationTemplates',N'U') IS NOT NULL
    SELECT TemplateCode,LocaleCode,COUNT_BIG(*) AS VersionCount,
           SUM(CASE WHEN StatusCode='ACTIVE' THEN 1 ELSE 0 END) AS ActiveVersionCount
    FROM ntf.NotificationTemplates t
    LEFT JOIN ntf.NotificationTemplateVersions v ON v.TemplateId=t.TemplateId
    GROUP BY TemplateCode,LocaleCode
    ORDER BY TemplateCode,LocaleCode;

IF OBJECT_ID(N'cfg.SystemConfigurations',N'U') IS NOT NULL
    SELECT N'notification.email_verification_templates.enabled' AS ConfigurationKey,
           CASE WHEN ConfigurationId IS NULL THEN N'ABSENT - runtime default is disabled'
                WHEN ValueType='BOOLEAN' AND StorageType='PLAIN' AND ConfigurationValue=N'false'
                    THEN N'PRESENT - disabled'
                WHEN ValueType='BOOLEAN' AND StorageType='PLAIN' AND ConfigurationValue=N'true'
                    THEN N'PRESENT - enabled by owner decision'
                ELSE N'INVALID - startup must fail closed' END AS RolloutStatus
    FROM cfg.SystemConfigurations
    WHERE ConfigurationKey='notification.email_verification_templates.enabled' AND IsActive=1;
GO
