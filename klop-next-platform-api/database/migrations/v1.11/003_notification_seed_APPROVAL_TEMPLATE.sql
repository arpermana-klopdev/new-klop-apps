:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_SEED_ACTOR_USER_ID "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Owner-held, additive seed proposal. SMTP values and existing configuration are never changed.
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @SeedActorUserId BIGINT=TRY_CONVERT(BIGINT,N'$(KLOP_SEED_ACTOR_USER_ID)');
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 53140, 'DRY RUN - explicit owner approval and a change ticket are required.', 1;
IF @SeedActorUserId IS NULL OR @SeedActorUserId<=0
    THROW 53141, 'Provide the actual approved platform actor user ID; no actor is guessed.', 1;
IF OBJECT_ID(N'iam.Users',N'U') IS NULL OR OBJECT_ID(N'iam.PlatformRoleAssignments',N'U') IS NULL
   OR OBJECT_ID(N'mst.Roles',N'U') IS NULL OR OBJECT_ID(N'mst.RoleScopes',N'U') IS NULL
    THROW 53146, 'The platform actor authorization prerequisites are missing.', 1;
IF NOT EXISTS(SELECT 1 FROM iam.Users WHERE UserId=@SeedActorUserId)
   OR NOT EXISTS
   (
       SELECT 1 FROM iam.PlatformRoleAssignments assignment
       JOIN mst.Roles role ON role.RoleId=assignment.RoleId AND role.IsActive=1
       JOIN mst.RoleScopes scope ON scope.RoleScopeId=role.RoleScopeId
          AND scope.Code='PLATFORM' AND scope.IsActive=1
       WHERE assignment.UserId=@SeedActorUserId
   )
    THROW 53147, 'The supplied seed actor must be an existing user with an active PLATFORM assignment.', 1;
IF N'$(KLOP_ENVIRONMENT)'<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53142, 'Refused: this template is restricted to the reviewed Development environment.', 1;
IF N'$(KLOP_EXPECTED_DATABASE)'<>N'KlopPlatformDB' OR DB_NAME()<>N'$(KLOP_EXPECTED_DATABASE)'
    THROW 53143, 'Refused: target database does not match the reviewed Development database.', 1;
IF SCHEMA_ID(N'ntf') IS NULL OR OBJECT_ID(N'ntf.NotificationTemplateVersions',N'U') IS NULL
    THROW 53144, 'Apply the reviewed notification schema proposal first.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    INSERT ntf.NotificationChannelStatuses(StatusCode,DisplayName,IsOperational)
    SELECT seeded.StatusCode,seeded.DisplayName,seeded.IsOperational
    FROM (VALUES
        ('CONFIGURATION_REQUIRED',N'Configuration required',0),
        ('READY',N'Ready',1),
        ('DISABLED',N'Disabled',0)
    ) seeded(StatusCode,DisplayName,IsOperational)
    WHERE NOT EXISTS(SELECT 1 FROM ntf.NotificationChannelStatuses existing
                     WHERE existing.StatusCode=seeded.StatusCode);

    INSERT ntf.NotificationTemplateStatuses(StatusCode,DisplayName,IsTerminal)
    SELECT seeded.StatusCode,seeded.DisplayName,seeded.IsTerminal
    FROM (VALUES
        ('DRAFT',N'Draft',0),('PENDING_APPROVAL',N'Pending approval',0),
        ('APPROVED',N'Approved',0),('ACTIVE',N'Active',0),('ARCHIVED',N'Archived',1)
    ) seeded(StatusCode,DisplayName,IsTerminal)
    WHERE NOT EXISTS(SELECT 1 FROM ntf.NotificationTemplateStatuses existing
                     WHERE existing.StatusCode=seeded.StatusCode);

    INSERT ntf.NotificationDeliveryOutcomes(OutcomeCode,DisplayName)
    SELECT seeded.OutcomeCode,seeded.DisplayName
    FROM (VALUES
        ('PROVIDER_ACCEPTED',N'Provider accepted; inbox delivery is not confirmed'),
        ('PROVIDER_REJECTED',N'Provider rejected')
    ) seeded(OutcomeCode,DisplayName)
    WHERE NOT EXISTS(SELECT 1 FROM ntf.NotificationDeliveryOutcomes existing
                     WHERE existing.OutcomeCode=seeded.OutcomeCode);

    INSERT ntf.NotificationErrorCategories(ErrorCategoryCode,DisplayName)
    SELECT seeded.ErrorCategoryCode,seeded.DisplayName
    FROM (VALUES
        ('SMTP_FAILURE',N'SMTP provider failure'),
        ('SMTP_CONFIGURATION',N'SMTP configuration failure'),
        ('TEMPLATE_UNAVAILABLE',N'Active verification template unavailable')
    ) seeded(ErrorCategoryCode,DisplayName)
    WHERE NOT EXISTS(SELECT 1 FROM ntf.NotificationErrorCategories existing
                     WHERE existing.ErrorCategoryCode=seeded.ErrorCategoryCode);

    IF NOT EXISTS(SELECT 1 FROM ntf.NotificationTemplateTypes WHERE TemplateCode='EMAIL_VERIFICATION')
        INSERT ntf.NotificationTemplateTypes(TemplateCode,DisplayName,IsEnabled)
        VALUES('EMAIL_VERIFICATION',N'Email verification',1);
    IF NOT EXISTS(SELECT 1 FROM ntf.NotificationChannels WHERE ChannelCode='EMAIL')
        INSERT ntf.NotificationChannels(ChannelCode,DisplayName,IsEnabled,StatusCode)
        VALUES('EMAIL',N'Email',1,'CONFIGURATION_REQUIRED');
    IF NOT EXISTS
        (SELECT 1 FROM ntf.NotificationVariableDefinitions
         WHERE TemplateCode='EMAIL_VERIFICATION' AND VariableCode='verification_link')
        INSERT ntf.NotificationVariableDefinitions
            (TemplateCode,VariableCode,DisplayName,DataTypeCode,IsRequired)
        VALUES('EMAIL_VERIFICATION','verification_link',N'Verification link','HTTPS_URL',1);
    IF NOT EXISTS
        (SELECT 1 FROM ntf.NotificationVariableDefinitions
         WHERE TemplateCode='EMAIL_VERIFICATION' AND VariableCode='expiry_hours')
        INSERT ntf.NotificationVariableDefinitions
            (TemplateCode,VariableCode,DisplayName,DataTypeCode,IsRequired)
        VALUES('EMAIL_VERIFICATION','expiry_hours',N'Link expiry hours','INTEGER',1);

    IF NOT EXISTS
        (SELECT 1 FROM cfg.SystemConfigurations
         WHERE ConfigurationKey='notification.email_verification_templates.enabled')
        INSERT cfg.SystemConfigurations
            (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,
             MinNumericValue,MaxNumericValue,RequiresApproval)
        VALUES('notification.email_verification_templates.enabled',N'false','BOOLEAN','Notifications',
               1,0,NULL,NULL,1);
    IF NOT EXISTS
        (SELECT 1 FROM cfg.SystemConfigurations
         WHERE ConfigurationKey='notification.email_verification_delivery_audit.enabled')
        INSERT cfg.SystemConfigurations
            (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,
             MinNumericValue,MaxNumericValue,RequiresApproval)
        VALUES('notification.email_verification_delivery_audit.enabled',N'false','BOOLEAN','Notifications',
               1,0,NULL,NULL,1);

    DECLARE @ChannelId INT=(SELECT ChannelId FROM ntf.NotificationChannels WHERE ChannelCode='EMAIL');
    DECLARE @TemplateId UNIQUEIDENTIFIER;
    SELECT @TemplateId=TemplateId FROM ntf.NotificationTemplates WITH(UPDLOCK,HOLDLOCK)
    WHERE TemplateCode='EMAIL_VERIFICATION' AND ChannelId=@ChannelId AND LocaleCode='en';
    IF @TemplateId IS NULL
    BEGIN
        SET @TemplateId=NEWID();
        INSERT ntf.NotificationTemplates(TemplateId,TemplateCode,DisplayName,ChannelId,LocaleCode,CreatedByUserId)
        VALUES(@TemplateId,'EMAIL_VERIFICATION',N'Email verification',@ChannelId,'en',@SeedActorUserId);
    END;
    IF NOT EXISTS(SELECT 1 FROM ntf.NotificationTemplateVersions WHERE TemplateId=@TemplateId)
    BEGIN
        DECLARE @VersionId UNIQUEIDENTIFIER=NEWID();
        DECLARE @VersionNumber INT=(SELECT ISNULL(MAX(VersionNumber),0)+1
                                    FROM ntf.NotificationTemplateVersions WITH(UPDLOCK,HOLDLOCK)
                                    WHERE TemplateId=@TemplateId);
        INSERT ntf.NotificationTemplateVersions
            (TemplateVersionId,TemplateId,TemplateCode,VersionNumber,StatusCode,Subject,Body,CreatedByUserId)
        VALUES(@VersionId,@TemplateId,'EMAIL_VERIFICATION',@VersionNumber,'DRAFT',
               N'KLOP - Email verification',
               N'Complete email verification using this single-use link:' + NCHAR(10) +
               N'{{verification_link}}' + NCHAR(10) +
               N'The link expires in {{expiry_hours}} hour(s). Never share it.',
               @SeedActorUserId);
        INSERT ntf.NotificationTemplateVersionVariables
            (TemplateVersionId,TemplateCode,VariableCode,IsRequired)
        SELECT @VersionId,TemplateCode,VariableCode,IsRequired
        FROM ntf.NotificationVariableDefinitions WHERE TemplateCode='EMAIL_VERIFICATION';
    END;

    DECLARE @AuditActionId BIGINT=(SELECT AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1);
    DECLARE @AuditResultId BIGINT=(SELECT AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1);
    IF @AuditActionId IS NULL OR @AuditResultId IS NULL
        THROW 53145, 'Required CREATE/SUCCESS audit definitions are missing.', 1;
    INSERT aud.AuditEvents
        (ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
         ChangeSummaryJson,RequestId,CorrelationId)
    SELECT @SeedActorUserId,@AuditActionId,@AuditResultId,N'NOTIFICATION_SEED',N'EMAIL_VERIFICATION',
           N'{"action":"EMAIL_VERIFICATION_DRAFT_SEEDED","rolloutEnabled":false,"roleMappings":"NONE"}',
           CONVERT(VARCHAR(100),@ApprovalTicket),NEWID();
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
