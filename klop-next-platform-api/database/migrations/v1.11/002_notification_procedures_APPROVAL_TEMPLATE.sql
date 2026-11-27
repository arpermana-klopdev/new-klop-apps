:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Owner-held v1.11 procedure proposal. Procedures only; no direct table grants.
SET NOCOUNT ON;
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 53110, 'DRY RUN - explicit owner approval and a change ticket are required.', 1;
IF N'$(KLOP_ENVIRONMENT)'<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53111, 'Refused: this template is restricted to the reviewed Development environment.', 1;
IF N'$(KLOP_EXPECTED_DATABASE)'<>N'KlopPlatformDB' OR DB_NAME()<>N'$(KLOP_EXPECTED_DATABASE)'
    THROW 53112, 'Refused: target database does not match the reviewed Development database.', 1;
IF SCHEMA_ID(N'ntf') IS NULL OR OBJECT_ID(N'ntf.NotificationTemplateVersions',N'U') IS NULL
    THROW 53113, 'Apply the reviewed notification schema proposal first.', 1;
GO

CREATE OR ALTER PROCEDURE ntf.usp_ListTemplates
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.notifications.read';
    SELECT t.TemplateId,t.TemplateCode,t.DisplayName,c.ChannelCode,t.LocaleCode,
           active.TemplateVersionId AS ActiveVersionId,active.VersionNumber AS ActiveVersionNumber,
           active.StatusCode AS ActiveVersionStatus,t.RowVersion AS ConcurrencyVersion
    FROM ntf.NotificationTemplates t
    JOIN ntf.NotificationChannels c ON c.ChannelId=t.ChannelId
    OUTER APPLY
    (
        SELECT TOP(1) v.TemplateVersionId,v.VersionNumber,v.StatusCode
        FROM ntf.NotificationTemplateVersions v
        WHERE v.TemplateId=t.TemplateId AND v.StatusCode='ACTIVE'
        ORDER BY v.VersionNumber DESC
    ) active
    ORDER BY t.TemplateCode,t.LocaleCode;
END;
GO

CREATE OR ALTER PROCEDURE ntf.usp_GetTemplate
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,@TemplateId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.notifications.read';
    SELECT v.TemplateVersionId AS VersionId,t.TemplateCode,t.DisplayName,v.VersionNumber,
           v.StatusCode AS Status,v.Subject,v.Body,c.ChannelCode,t.LocaleCode,v.CreatedAtUtc,
           v.RowVersion AS ConcurrencyVersion
    FROM ntf.NotificationTemplates t
    JOIN ntf.NotificationChannels c ON c.ChannelId=t.ChannelId
    JOIN ntf.NotificationTemplateVersions v ON v.TemplateId=t.TemplateId
    WHERE t.TemplateId=@TemplateId
    ORDER BY v.VersionNumber DESC;
END;
GO

CREATE OR ALTER PROCEDURE ntf.usp_GetTemplateVersionForPreview
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,@TemplateVersionId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.notifications.draft.preview';
    SELECT v.TemplateVersionId AS VersionId,t.TemplateCode,t.DisplayName,v.VersionNumber,
           v.StatusCode AS Status,v.Subject,v.Body,c.ChannelCode,t.LocaleCode,v.CreatedAtUtc,
           v.RowVersion AS ConcurrencyVersion
    FROM ntf.NotificationTemplateVersions v
    JOIN ntf.NotificationTemplates t ON t.TemplateId=v.TemplateId
    JOIN ntf.NotificationChannels c ON c.ChannelId=t.ChannelId
    WHERE v.TemplateVersionId=@TemplateVersionId;
END;
GO

CREATE OR ALTER PROCEDURE ntf.usp_ListChannels
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.notifications.read';
    SELECT c.ChannelCode,c.DisplayName,s.DisplayName AS Status,c.IsEnabled,s.DisplayName AS Readiness
    FROM ntf.NotificationChannels c
    JOIN ntf.NotificationChannelStatuses s ON s.StatusCode=c.StatusCode
    ORDER BY c.ChannelCode;
END;
GO

CREATE OR ALTER PROCEDURE ntf.usp_ListDeliveryHistory
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,
    @PageNumber INT=1,@PageSize INT=20
AS
BEGIN
    SET NOCOUNT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.notifications.history';
    IF @PageNumber NOT BETWEEN 1 AND 100000 OR @PageSize NOT BETWEEN 1 AND 100
        THROW 53120, 'Notification history page is invalid.', 1;
    ;WITH History AS
    (
        SELECT d.DeliveryId,COALESCE(t.TemplateCode,d.TemplateCodeSnapshot) AS TemplateCode,
               COALESCE(CONVERT(VARCHAR(20),v.VersionNumber),
                        CONVERT(VARCHAR(20),d.TemplateVersionSnapshot),'LEGACY') AS TemplateVersion,
               c.ChannelCode,a.OutcomeCode AS Outcome,a.ErrorCategoryCode AS SafeErrorCategory,
               a.OccurredAtUtc,d.CorrelationId,COUNT_BIG(*) OVER() AS TotalCount,
               ROW_NUMBER() OVER(ORDER BY a.OccurredAtUtc DESC,d.DeliveryId DESC) AS RowNumber
        FROM ntf.NotificationDeliveries d
        LEFT JOIN ntf.NotificationTemplateVersions v ON v.TemplateVersionId=d.TemplateVersionId
        LEFT JOIN ntf.NotificationTemplates t ON t.TemplateId=v.TemplateId
        JOIN ntf.NotificationChannels c ON c.ChannelId=d.ChannelId
        JOIN ntf.NotificationDeliveryAttempts a ON a.DeliveryId=d.DeliveryId
    )
    SELECT DeliveryId,TemplateCode,TemplateVersion,ChannelCode,Outcome,SafeErrorCategory,
           OccurredAtUtc,CorrelationId,TotalCount
    FROM History
    WHERE RowNumber BETWEEN ((@PageNumber-1)*@PageSize)+1 AND @PageNumber*@PageSize
    ORDER BY RowNumber;
END;
GO

CREATE OR ALTER PROCEDURE ntf.usp_CreateTemplateDraft
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,@TemplateCode VARCHAR(50),
    @DisplayName NVARCHAR(200),@ChannelCode VARCHAR(30),@LocaleCode VARCHAR(20),
    @Subject NVARCHAR(300),@Body NVARCHAR(MAX),@RequestId VARCHAR(100),@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.notifications.draft.create';
    IF NULLIF(LTRIM(RTRIM(@Subject)),N'') IS NULL OR LEN(@Subject)>300
       OR @Subject LIKE N'%' + NCHAR(13) + N'%' OR @Subject LIKE N'%' + NCHAR(10) + N'%'
       OR NULLIF(LTRIM(RTRIM(@Body)),N'') IS NULL OR LEN(@Body)>20000
        THROW 53121, 'Notification draft content is invalid.', 1;

    DECLARE @TemplateId UNIQUEIDENTIFIER,@VersionId UNIQUEIDENTIFIER=NEWID(),@VersionNumber INT;
    DECLARE @ChannelId INT,@ContentToCheck NVARCHAR(MAX)=@Subject+NCHAR(10)+@Body;
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @ChannelId=ChannelId FROM ntf.NotificationChannels WITH(UPDLOCK,HOLDLOCK)
        WHERE ChannelCode=@ChannelCode AND IsEnabled=1;
        IF @ChannelId IS NULL OR NOT EXISTS
            (SELECT 1 FROM ntf.NotificationTemplateTypes WHERE TemplateCode=@TemplateCode AND IsEnabled=1)
            THROW 53122, 'Notification template type or channel is unavailable.', 1;
        IF EXISTS
            (SELECT 1 FROM ntf.NotificationVariableDefinitions
             WHERE TemplateCode=@TemplateCode AND IsRequired=1
               AND CHARINDEX(N'{{'+VariableCode+N'}}',@ContentToCheck)=0)
            THROW 53128, 'The template is missing a required variable.', 1;
        SELECT @ContentToCheck=REPLACE(@ContentToCheck,N'{{'+VariableCode+N'}}',N'')
        FROM ntf.NotificationVariableDefinitions WHERE TemplateCode=@TemplateCode;
        IF CHARINDEX(N'{{',@ContentToCheck)>0 OR CHARINDEX(N'}}',@ContentToCheck)>0
            THROW 53134, 'The template contains an unsupported or malformed variable.', 1;
        SELECT @TemplateId=TemplateId FROM ntf.NotificationTemplates WITH(UPDLOCK,HOLDLOCK)
        WHERE TemplateCode=@TemplateCode AND ChannelId=@ChannelId AND LocaleCode=@LocaleCode;
        IF @TemplateId IS NULL
        BEGIN
            SET @TemplateId=NEWID();
            INSERT ntf.NotificationTemplates(TemplateId,TemplateCode,DisplayName,ChannelId,LocaleCode,CreatedByUserId)
            VALUES(@TemplateId,@TemplateCode,@DisplayName,@ChannelId,@LocaleCode,@ActorUserId);
        END
        SELECT @VersionNumber=ISNULL(MAX(VersionNumber),0)+1
        FROM ntf.NotificationTemplateVersions WITH(UPDLOCK,HOLDLOCK) WHERE TemplateId=@TemplateId;
        INSERT ntf.NotificationTemplateVersions
            (TemplateVersionId,TemplateId,VersionNumber,StatusCode,Subject,Body,CreatedByUserId)
        VALUES(@VersionId,@TemplateId,@VersionNumber,'DRAFT',@Subject,@Body,@ActorUserId);
        INSERT ntf.NotificationTemplateVersionVariables(TemplateVersionId,TemplateCode,VariableCode,IsRequired)
        SELECT @VersionId,TemplateCode,VariableCode,IsRequired
        FROM ntf.NotificationVariableDefinitions WHERE TemplateCode=@TemplateCode;
        INSERT aud.AuditEvents(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
                               ChangeSummaryJson,RequestId,CorrelationId)
        SELECT @ActorUserId,act.AuditActionTypeId,res.AuditResultTypeId,'NOTIFICATION_TEMPLATE_VERSION',
               CONVERT(NVARCHAR(150),@VersionId),
               (SELECT @TemplateCode AS TemplateCode,@VersionNumber AS VersionNumber,N'DRAFT_CREATED' AS Action
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@RequestId,@CorrelationId
        FROM mst.AuditActionTypes act CROSS JOIN mst.AuditResultTypes res
        WHERE act.Code='CREATE' AND act.IsActive=1 AND res.Code='SUCCESS' AND res.IsActive=1;
        IF @@ROWCOUNT<>1 THROW 53123, 'Notification audit metadata is unavailable.', 1;
        COMMIT TRANSACTION;
        SELECT @TemplateId AS TemplateId,@VersionId AS VersionId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE ntf.usp_UpdateTemplateDraft
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,@TemplateVersionId UNIQUEIDENTIFIER,
    @Subject NVARCHAR(300),@Body NVARCHAR(MAX),@ExpectedVersion BINARY(8),
    @RequestId VARCHAR(100),@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.notifications.draft.edit';
    IF NULLIF(LTRIM(RTRIM(@Subject)),N'') IS NULL OR LEN(@Subject)>300
       OR @Subject LIKE N'%' + NCHAR(13) + N'%' OR @Subject LIKE N'%' + NCHAR(10) + N'%'
       OR NULLIF(LTRIM(RTRIM(@Body)),N'') IS NULL OR LEN(@Body)>20000
        THROW 53124, 'Notification draft content is invalid.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @TemplateCode=t.TemplateCode
        FROM ntf.NotificationTemplateVersions v
        JOIN ntf.NotificationTemplates t ON t.TemplateId=v.TemplateId
        WHERE v.TemplateVersionId=@TemplateVersionId;
        IF @TemplateCode IS NULL THROW 53201, 'Notification version changed or does not exist.', 1;
        IF EXISTS
            (SELECT 1 FROM ntf.NotificationVariableDefinitions
             WHERE TemplateCode=@TemplateCode AND IsRequired=1
               AND CHARINDEX(N'{{'+VariableCode+N'}}',@ContentToCheck)=0)
            THROW 53128, 'The template is missing a required variable.', 1;
        SELECT @ContentToCheck=REPLACE(@ContentToCheck,N'{{'+VariableCode+N'}}',N'')
        FROM ntf.NotificationVariableDefinitions WHERE TemplateCode=@TemplateCode;
        IF CHARINDEX(N'{{',@ContentToCheck)>0 OR CHARINDEX(N'}}',@ContentToCheck)>0
            THROW 53134, 'The template contains an unsupported or malformed variable.', 1;
        UPDATE ntf.NotificationTemplateVersions WITH(UPDLOCK)
        SET Subject=@Subject,Body=@Body
        WHERE TemplateVersionId=@TemplateVersionId AND StatusCode='DRAFT'
          AND RowVersion=@ExpectedVersion;
        IF @@ROWCOUNT<>1 THROW 53201, 'Notification version changed or is not editable.', 1;
        INSERT aud.AuditEvents(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
                               ChangeSummaryJson,RequestId,CorrelationId)
        SELECT @ActorUserId,act.AuditActionTypeId,res.AuditResultTypeId,'NOTIFICATION_TEMPLATE_VERSION',
               CONVERT(NVARCHAR(150),@TemplateVersionId),N'{"action":"DRAFT_EDITED"}',@RequestId,@CorrelationId
        FROM mst.AuditActionTypes act CROSS JOIN mst.AuditResultTypes res
        WHERE act.Code='UPDATE' AND act.IsActive=1 AND res.Code='SUCCESS' AND res.IsActive=1;
        IF @@ROWCOUNT<>1 THROW 53125, 'Notification audit metadata is unavailable.', 1;
        COMMIT TRANSACTION;
        SELECT TemplateId,@TemplateVersionId AS VersionId
        FROM ntf.NotificationTemplateVersions WHERE TemplateVersionId=@TemplateVersionId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE ntf.usp_TransitionTemplateVersion
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,@TemplateVersionId UNIQUEIDENTIFIER,
    @ActionCode VARCHAR(20),@DecisionCode VARCHAR(20)=NULL,@DecisionNote NVARCHAR(1000)=NULL,
    @ExpectedVersion BINARY(8),@RequestId VARCHAR(100),@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @PermissionCode VARCHAR(150)=CASE @ActionCode
        WHEN 'SUBMIT' THEN 'platform.notifications.submit'
        WHEN 'APPROVE' THEN 'platform.notifications.approve'
        WHEN 'ACTIVATE' THEN 'platform.notifications.activate'
        WHEN 'ARCHIVE' THEN 'platform.notifications.archive' END;
    IF @PermissionCode IS NULL THROW 53126, 'Notification transition is unsupported.', 1;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,@PermissionCode;
    IF LEN(COALESCE(@DecisionNote,N''))>1000
        THROW 53135, 'Notification decision note is too long.', 1;

    DECLARE @CurrentStatus VARCHAR(30),@TemplateId UNIQUEIDENTIFIER,@TemplateCode VARCHAR(50),
            @TargetStatus VARCHAR(30),@ActionType VARCHAR(20)='UPDATE',
            @ContentToCheck NVARCHAR(MAX)=@Subject+NCHAR(10)+@Body;
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @CurrentStatus=v.StatusCode,@TemplateId=v.TemplateId,@TemplateCode=t.TemplateCode
        FROM ntf.NotificationTemplateVersions v WITH(UPDLOCK,HOLDLOCK)
        JOIN ntf.NotificationTemplates t ON t.TemplateId=v.TemplateId
        WHERE v.TemplateVersionId=@TemplateVersionId AND v.RowVersion=@ExpectedVersion;
        IF @TemplateId IS NULL THROW 53201, 'Notification version changed or does not exist.', 1;

        IF @ActionCode='SUBMIT' AND @CurrentStatus='DRAFT'
        BEGIN
            IF NOT EXISTS
                (SELECT 1 FROM ntf.NotificationTemplateVersionVariables
                 WHERE TemplateVersionId=@TemplateVersionId AND IsRequired=1)
                THROW 53127, 'Required notification variable definitions are missing.', 1;
            IF EXISTS
                (SELECT 1 FROM ntf.NotificationTemplateVersionVariables vv
                 JOIN ntf.NotificationTemplateVersions v ON v.TemplateVersionId=vv.TemplateVersionId
                 WHERE vv.TemplateVersionId=@TemplateVersionId AND vv.IsRequired=1
                   AND CHARINDEX(N'{{'+vv.VariableCode+N'}}',v.Subject+NCHAR(10)+v.Body)=0)
                THROW 53128, 'The template is missing a required variable.', 1;
            UPDATE ntf.NotificationTemplateVersions
            SET StatusCode='PENDING_APPROVAL',SubmittedAtUtc=SYSUTCDATETIME()
            WHERE TemplateVersionId=@TemplateVersionId;
            SET @TargetStatus='PENDING_APPROVAL';
        END
        ELSE IF @ActionCode='APPROVE' AND @CurrentStatus='PENDING_APPROVAL'
        BEGIN
            IF @DecisionCode NOT IN('APPROVE','REJECT')
                THROW 53129, 'An explicit approval or rejection decision is required.', 1;
            SET @TargetStatus=CASE WHEN @DecisionCode='APPROVE' THEN 'APPROVED' ELSE 'DRAFT' END;
            UPDATE ntf.NotificationTemplateVersions SET StatusCode=@TargetStatus
            WHERE TemplateVersionId=@TemplateVersionId;
            INSERT ntf.NotificationTemplateApprovals
                (TemplateVersionId,ActorUserId,DecisionCode,DecisionNote)
            VALUES(@TemplateVersionId,@ActorUserId,@DecisionCode,@DecisionNote);
        END
        ELSE IF @ActionCode='ACTIVATE' AND @CurrentStatus='APPROVED'
        BEGIN
            UPDATE ntf.NotificationTemplateVersions
            SET StatusCode='ARCHIVED',ArchivedAtUtc=SYSUTCDATETIME()
            WHERE TemplateId=@TemplateId AND StatusCode='ACTIVE';
            UPDATE ntf.NotificationTemplateVersions
            SET StatusCode='ACTIVE',ActivatedAtUtc=SYSUTCDATETIME()
            WHERE TemplateVersionId=@TemplateVersionId;
            SET @TargetStatus='ACTIVE';
        END
        ELSE IF @ActionCode='ARCHIVE' AND @CurrentStatus='ACTIVE'
        BEGIN
            UPDATE ntf.NotificationTemplateVersions
            SET StatusCode='ARCHIVED',ArchivedAtUtc=SYSUTCDATETIME()
            WHERE TemplateVersionId=@TemplateVersionId;
            SET @TargetStatus='ARCHIVED';
        END
        ELSE
            THROW 53201, 'Notification version cannot make the requested transition.', 1;

        INSERT aud.AuditEvents(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
                               ChangeSummaryJson,RequestId,CorrelationId)
        SELECT @ActorUserId,act.AuditActionTypeId,res.AuditResultTypeId,'NOTIFICATION_TEMPLATE_VERSION',
               CONVERT(NVARCHAR(150),@TemplateVersionId),
               (SELECT @ActionCode AS Action,@CurrentStatus AS PreviousStatus,@TargetStatus AS NewStatus,
                       CASE WHEN @ActionCode='APPROVE' THEN @DecisionCode END AS Decision
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@RequestId,@CorrelationId
        FROM mst.AuditActionTypes act CROSS JOIN mst.AuditResultTypes res
        WHERE act.Code=@ActionType AND act.IsActive=1 AND res.Code='SUCCESS' AND res.IsActive=1;
        IF @@ROWCOUNT<>1 THROW 53130, 'Notification audit metadata is unavailable.', 1;
        COMMIT TRANSACTION;

        SELECT v.TemplateVersionId AS VersionId,t.TemplateCode,t.DisplayName,v.VersionNumber,
               v.StatusCode AS Status,v.Subject,v.Body,c.ChannelCode,t.LocaleCode,v.CreatedAtUtc,
               v.RowVersion AS ConcurrencyVersion
        FROM ntf.NotificationTemplateVersions v
        JOIN ntf.NotificationTemplates t ON t.TemplateId=v.TemplateId
        JOIN ntf.NotificationChannels c ON c.ChannelId=t.ChannelId
        WHERE v.TemplateVersionId=@TemplateVersionId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE ntf.usp_GetActiveVerificationTemplate
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP(1) v.TemplateVersionId AS VersionId,t.TemplateCode,t.DisplayName,v.VersionNumber,
           v.StatusCode AS Status,v.Subject,v.Body,c.ChannelCode,t.LocaleCode,v.CreatedAtUtc,
           v.RowVersion AS ConcurrencyVersion
    FROM ntf.NotificationTemplates t
    JOIN ntf.NotificationTemplateVersions v ON v.TemplateId=t.TemplateId AND v.StatusCode='ACTIVE'
    JOIN ntf.NotificationChannels c ON c.ChannelId=t.ChannelId AND c.IsEnabled=1
    WHERE t.TemplateCode='EMAIL_VERIFICATION' AND c.ChannelCode='EMAIL'
    ORDER BY v.ActivatedAtUtc DESC;
END;
GO

CREATE OR ALTER PROCEDURE ntf.usp_RecordDeliveryAttempt
    @TemplateCodeSnapshot VARCHAR(50),@CorrelationId UNIQUEIDENTIFIER,@ProviderAccepted BIT,
    @TemplateVersionId UNIQUEIDENTIFIER=NULL,@TemplateVersionSnapshot INT=NULL,
    @SafeErrorCategory VARCHAR(40)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF (@ProviderAccepted=1 AND @SafeErrorCategory IS NOT NULL)
       OR (@ProviderAccepted=0 AND @SafeErrorCategory IS NULL)
        THROW 53131, 'Delivery outcome metadata is invalid.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @ChannelId INT,@DeliveryId UNIQUEIDENTIFIER=NEWID();
        IF @TemplateVersionId IS NOT NULL
            SELECT @ChannelId=t.ChannelId,@TemplateCodeSnapshot=t.TemplateCode,
                   @TemplateVersionSnapshot=v.VersionNumber
            FROM ntf.NotificationTemplateVersions v WITH(UPDLOCK,HOLDLOCK)
            JOIN ntf.NotificationTemplates t ON t.TemplateId=v.TemplateId
            WHERE v.TemplateVersionId=@TemplateVersionId;
        ELSE
            SELECT @ChannelId=ChannelId FROM ntf.NotificationChannels
            WHERE ChannelCode='EMAIL' AND IsEnabled=1;
        IF @ChannelId IS NULL THROW 53132, 'Notification channel or version is unavailable.', 1;
        IF @SafeErrorCategory IS NOT NULL AND NOT EXISTS
            (SELECT 1 FROM ntf.NotificationErrorCategories WHERE ErrorCategoryCode=@SafeErrorCategory)
            THROW 53133, 'Delivery error category is not registered.', 1;
        INSERT ntf.NotificationDeliveries
            (DeliveryId,TemplateVersionId,TemplateCodeSnapshot,TemplateVersionSnapshot,
             ChannelId,CorrelationId,RecipientMetadata)
        VALUES(@DeliveryId,@TemplateVersionId,@TemplateCodeSnapshot,@TemplateVersionSnapshot,
               @ChannelId,@CorrelationId,NULL);
        INSERT ntf.NotificationDeliveryAttempts
            (DeliveryId,AttemptNumber,OutcomeCode,ErrorCategoryCode,ProviderAccepted)
        VALUES(@DeliveryId,1,CASE WHEN @ProviderAccepted=1 THEN 'PROVIDER_ACCEPTED' ELSE 'PROVIDER_REJECTED' END,
               @SafeErrorCategory,@ProviderAccepted);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
