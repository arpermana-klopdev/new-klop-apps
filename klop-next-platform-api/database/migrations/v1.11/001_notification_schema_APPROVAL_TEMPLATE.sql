:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Owner-held v1.11 schema proposal. SQLCMD mode is required.
-- No database changes occur without an approved Development change ticket.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Environment NVARCHAR(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase SYSNAME=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 53100, 'DRY RUN - set an approved Development ticket and KLOP_APPLY_CHANGES=APPROVED only after owner review.', 1;
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53101, 'Refused: this approval template is restricted to the reviewed Development environment.', 1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
    THROW 53102, 'Refused: target database does not match the reviewed Development database.', 1;
IF LEN(@ApprovalTicket)>100
    THROW 53103, 'Approval ticket must be at most 100 characters.', 1;
IF OBJECT_ID(N'cfg.SystemConfigurations',N'U') IS NULL
   OR OBJECT_ID(N'aud.AuditEvents',N'U') IS NULL
   OR OBJECT_ID(N'mst.AuditActionTypes',N'U') IS NULL
   OR OBJECT_ID(N'mst.AuditResultTypes',N'U') IS NULL
   OR OBJECT_ID(N'iam.Users',N'U') IS NULL
   OR OBJECT_ID(N'iam.usp_ValidatePlatformPermission',N'P') IS NULL
    THROW 53104, 'Required existing configuration, audit, or authorization objects are missing.', 1;
IF SCHEMA_ID(N'ntf') IS NOT NULL
    THROW 53105, 'Schema ntf already exists; reconcile its ownership and version before applying this proposal.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    EXEC(N'CREATE SCHEMA ntf AUTHORIZATION dbo;');

    CREATE TABLE ntf.NotificationChannelStatuses
    (
        StatusCode VARCHAR(30) NOT NULL CONSTRAINT PK_NotificationChannelStatuses PRIMARY KEY,
        DisplayName NVARCHAR(100) NOT NULL,
        IsOperational BIT NOT NULL
    );
    CREATE TABLE ntf.NotificationChannels
    (
        ChannelId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_NotificationChannels PRIMARY KEY,
        ChannelCode VARCHAR(30) NOT NULL CONSTRAINT UQ_NotificationChannels_Code UNIQUE,
        DisplayName NVARCHAR(100) NOT NULL,
        IsEnabled BIT NOT NULL CONSTRAINT DF_NotificationChannels_IsEnabled DEFAULT(0),
        StatusCode VARCHAR(30) NOT NULL,
        RowVersion ROWVERSION NOT NULL,
        CONSTRAINT FK_NotificationChannels_Status FOREIGN KEY(StatusCode)
            REFERENCES ntf.NotificationChannelStatuses(StatusCode)
    );
    CREATE TABLE ntf.NotificationTemplateTypes
    (
        TemplateCode VARCHAR(50) NOT NULL CONSTRAINT PK_NotificationTemplateTypes PRIMARY KEY,
        DisplayName NVARCHAR(200) NOT NULL,
        IsEnabled BIT NOT NULL CONSTRAINT DF_NotificationTemplateTypes_IsEnabled DEFAULT(0)
    );
    CREATE TABLE ntf.NotificationTemplateStatuses
    (
        StatusCode VARCHAR(30) NOT NULL CONSTRAINT PK_NotificationTemplateStatuses PRIMARY KEY,
        DisplayName NVARCHAR(100) NOT NULL,
        IsTerminal BIT NOT NULL
    );
    CREATE TABLE ntf.NotificationVariableDefinitions
    (
        TemplateCode VARCHAR(50) NOT NULL,
        VariableCode VARCHAR(80) NOT NULL,
        DisplayName NVARCHAR(100) NOT NULL,
        DataTypeCode VARCHAR(30) NOT NULL,
        IsRequired BIT NOT NULL,
        CONSTRAINT PK_NotificationVariableDefinitions PRIMARY KEY(TemplateCode,VariableCode),
        CONSTRAINT FK_NotificationVariableDefinitions_Type FOREIGN KEY(TemplateCode)
            REFERENCES ntf.NotificationTemplateTypes(TemplateCode)
    );
    CREATE TABLE ntf.NotificationTemplates
    (
        TemplateId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_NotificationTemplates_Id DEFAULT(NEWSEQUENTIALID())
            CONSTRAINT PK_NotificationTemplates PRIMARY KEY,
        TemplateCode VARCHAR(50) NOT NULL,
        DisplayName NVARCHAR(200) NOT NULL,
        ChannelId INT NOT NULL,
        LocaleCode VARCHAR(20) NOT NULL,
        CreatedByUserId BIGINT NOT NULL,
        CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_NotificationTemplates_Created DEFAULT(SYSUTCDATETIME()),
        RowVersion ROWVERSION NOT NULL,
        CONSTRAINT UQ_NotificationTemplates_Key UNIQUE(TemplateCode,ChannelId,LocaleCode),
        CONSTRAINT UQ_NotificationTemplates_IdCode UNIQUE(TemplateId,TemplateCode),
        CONSTRAINT FK_NotificationTemplates_Type FOREIGN KEY(TemplateCode)
            REFERENCES ntf.NotificationTemplateTypes(TemplateCode),
        CONSTRAINT FK_NotificationTemplates_Channel FOREIGN KEY(ChannelId)
            REFERENCES ntf.NotificationChannels(ChannelId),
        CONSTRAINT FK_NotificationTemplates_CreatedBy FOREIGN KEY(CreatedByUserId)
            REFERENCES iam.Users(UserId)
    );
    CREATE TABLE ntf.NotificationTemplateVersions
    (
        TemplateVersionId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_NotificationTemplateVersions_Id DEFAULT(NEWSEQUENTIALID())
            CONSTRAINT PK_NotificationTemplateVersions PRIMARY KEY,
        TemplateId UNIQUEIDENTIFIER NOT NULL,
        TemplateCode VARCHAR(50) NOT NULL,
        VersionNumber INT NOT NULL,
        StatusCode VARCHAR(30) NOT NULL,
        Subject NVARCHAR(300) NOT NULL,
        Body NVARCHAR(MAX) NOT NULL,
        CreatedByUserId BIGINT NOT NULL,
        CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_NotificationTemplateVersions_Created DEFAULT(SYSUTCDATETIME()),
        SubmittedAtUtc DATETIME2(3) NULL,
        ActivatedAtUtc DATETIME2(3) NULL,
        ArchivedAtUtc DATETIME2(3) NULL,
        RowVersion ROWVERSION NOT NULL,
        CONSTRAINT UQ_NotificationTemplateVersions_Number UNIQUE(TemplateId,VersionNumber),
        CONSTRAINT UQ_NotificationTemplateVersions_IdCode UNIQUE(TemplateVersionId,TemplateCode),
        CONSTRAINT FK_NotificationTemplateVersions_Template FOREIGN KEY(TemplateId)
            REFERENCES ntf.NotificationTemplates(TemplateId),
        CONSTRAINT FK_NotificationTemplateVersions_TemplateCode FOREIGN KEY(TemplateId,TemplateCode)
            REFERENCES ntf.NotificationTemplates(TemplateId,TemplateCode),
        CONSTRAINT FK_NotificationTemplateVersions_Status FOREIGN KEY(StatusCode)
            REFERENCES ntf.NotificationTemplateStatuses(StatusCode),
        CONSTRAINT FK_NotificationTemplateVersions_CreatedBy FOREIGN KEY(CreatedByUserId)
            REFERENCES iam.Users(UserId),
        CONSTRAINT CK_NotificationTemplateVersions_Number CHECK(VersionNumber>0),
        CONSTRAINT CK_NotificationTemplateVersions_Content CHECK(LEN(Subject)>0 AND LEN(Body)>0)
    );
    CREATE UNIQUE INDEX UX_NotificationTemplateVersions_OneActive
        ON ntf.NotificationTemplateVersions(TemplateId) WHERE StatusCode='ACTIVE';
    CREATE TABLE ntf.NotificationTemplateVersionVariables
    (
        TemplateVersionId UNIQUEIDENTIFIER NOT NULL,
        TemplateCode VARCHAR(50) NOT NULL,
        VariableCode VARCHAR(80) NOT NULL,
        IsRequired BIT NOT NULL,
        CONSTRAINT PK_NotificationTemplateVersionVariables PRIMARY KEY(TemplateVersionId,VariableCode),
        CONSTRAINT FK_NotificationTemplateVersionVariables_Version FOREIGN KEY(TemplateVersionId,TemplateCode)
            REFERENCES ntf.NotificationTemplateVersions(TemplateVersionId,TemplateCode),
        CONSTRAINT FK_NotificationTemplateVersionVariables_Definition FOREIGN KEY(TemplateCode,VariableCode)
            REFERENCES ntf.NotificationVariableDefinitions(TemplateCode,VariableCode)
    );
    CREATE TABLE ntf.NotificationTemplateApprovals
    (
        ApprovalId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_NotificationTemplateApprovals PRIMARY KEY,
        TemplateVersionId UNIQUEIDENTIFIER NOT NULL,
        ActorUserId BIGINT NOT NULL,
        DecisionCode VARCHAR(20) NOT NULL,
        DecisionNote NVARCHAR(1000) NULL,
        DecidedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_NotificationTemplateApprovals_Decided DEFAULT(SYSUTCDATETIME()),
        CONSTRAINT FK_NotificationTemplateApprovals_Version FOREIGN KEY(TemplateVersionId)
            REFERENCES ntf.NotificationTemplateVersions(TemplateVersionId),
        CONSTRAINT FK_NotificationTemplateApprovals_Actor FOREIGN KEY(ActorUserId)
            REFERENCES iam.Users(UserId),
        CONSTRAINT CK_NotificationTemplateApprovals_Decision CHECK(DecisionCode IN('APPROVE','REJECT'))
    );
    CREATE TABLE ntf.NotificationDeliveryOutcomes
    (
        OutcomeCode VARCHAR(30) NOT NULL CONSTRAINT PK_NotificationDeliveryOutcomes PRIMARY KEY,
        DisplayName NVARCHAR(100) NOT NULL
    );
    CREATE TABLE ntf.NotificationErrorCategories
    (
        ErrorCategoryCode VARCHAR(40) NOT NULL CONSTRAINT PK_NotificationErrorCategories PRIMARY KEY,
        DisplayName NVARCHAR(100) NOT NULL
    );
    CREATE TABLE ntf.NotificationDeliveries
    (
        DeliveryId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_NotificationDeliveries_Id DEFAULT(NEWSEQUENTIALID())
            CONSTRAINT PK_NotificationDeliveries PRIMARY KEY,
        TemplateVersionId UNIQUEIDENTIFIER NULL,
        TemplateCodeSnapshot VARCHAR(50) NOT NULL,
        TemplateVersionSnapshot INT NULL,
        ChannelId INT NOT NULL,
        CorrelationId UNIQUEIDENTIFIER NOT NULL,
        CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_NotificationDeliveries_Created DEFAULT(SYSUTCDATETIME()),
        CONSTRAINT CK_NotificationDeliveries_VersionSnapshot CHECK(TemplateVersionSnapshot IS NULL OR TemplateVersionSnapshot>0),
        CONSTRAINT FK_NotificationDeliveries_Version FOREIGN KEY(TemplateVersionId)
            REFERENCES ntf.NotificationTemplateVersions(TemplateVersionId),
        CONSTRAINT FK_NotificationDeliveries_Channel FOREIGN KEY(ChannelId)
            REFERENCES ntf.NotificationChannels(ChannelId)
    );
    CREATE INDEX IX_NotificationDeliveries_Correlation
        ON ntf.NotificationDeliveries(CorrelationId,CreatedAtUtc DESC);
    CREATE TABLE ntf.NotificationDeliveryAttempts
    (
        AttemptId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_NotificationDeliveryAttempts PRIMARY KEY,
        DeliveryId UNIQUEIDENTIFIER NOT NULL,
        AttemptNumber INT NOT NULL,
        OutcomeCode VARCHAR(30) NOT NULL,
        ErrorCategoryCode VARCHAR(40) NULL,
        OccurredAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_NotificationDeliveryAttempts_Occurred DEFAULT(SYSUTCDATETIME()),
        ProviderAccepted BIT NOT NULL,
        CONSTRAINT CK_NotificationDeliveryAttempts_Number CHECK(AttemptNumber>0),
        CONSTRAINT CK_NotificationDeliveryAttempts_Outcome CHECK
            ((ProviderAccepted=1 AND OutcomeCode='PROVIDER_ACCEPTED' AND ErrorCategoryCode IS NULL)
             OR (ProviderAccepted=0 AND OutcomeCode='PROVIDER_REJECTED' AND ErrorCategoryCode IS NOT NULL)),
        CONSTRAINT UQ_NotificationDeliveryAttempts_Number UNIQUE(DeliveryId,AttemptNumber),
        CONSTRAINT FK_NotificationDeliveryAttempts_Delivery FOREIGN KEY(DeliveryId)
            REFERENCES ntf.NotificationDeliveries(DeliveryId),
        CONSTRAINT FK_NotificationDeliveryAttempts_Outcome FOREIGN KEY(OutcomeCode)
            REFERENCES ntf.NotificationDeliveryOutcomes(OutcomeCode),
        CONSTRAINT FK_NotificationDeliveryAttempts_Error FOREIGN KEY(ErrorCategoryCode)
            REFERENCES ntf.NotificationErrorCategories(ErrorCategoryCode)
    );
    EXEC(N'
        CREATE TRIGGER ntf.trg_NotificationTemplateVersions_ActiveImmutable
        ON ntf.NotificationTemplateVersions
        AFTER UPDATE
        AS
        BEGIN
            SET NOCOUNT ON;
            IF EXISTS
            (
                SELECT 1
                FROM inserted i
                JOIN deleted d ON d.TemplateVersionId=i.TemplateVersionId
                WHERE d.StatusCode IN(''ACTIVE'',''ARCHIVED'')
                  AND (i.TemplateId<>d.TemplateId OR i.TemplateCode<>d.TemplateCode
                       OR i.VersionNumber<>d.VersionNumber
                       OR CONVERT(VARBINARY(MAX),i.Subject)<>CONVERT(VARBINARY(MAX),d.Subject)
                       OR CONVERT(VARBINARY(MAX),i.Body)<>CONVERT(VARBINARY(MAX),d.Body)
                       OR i.CreatedByUserId<>d.CreatedByUserId
                       OR i.CreatedAtUtc<>d.CreatedAtUtc
                       OR ISNULL(i.SubmittedAtUtc,CONVERT(DATETIME2(3),''19000101''))
                          <>ISNULL(d.SubmittedAtUtc,CONVERT(DATETIME2(3),''19000101''))
                       OR (d.StatusCode=''ACTIVE'' AND
                           (i.StatusCode NOT IN(''ACTIVE'',''ARCHIVED'')
                            OR i.ActivatedAtUtc<>d.ActivatedAtUtc
                            OR (i.StatusCode=''ACTIVE'' AND
                                ISNULL(i.ArchivedAtUtc,CONVERT(DATETIME2(3),''19000101''))
                                <>ISNULL(d.ArchivedAtUtc,CONVERT(DATETIME2(3),''19000101'')))
                            OR (i.StatusCode=''ARCHIVED'' AND i.ArchivedAtUtc IS NULL)))
                       OR (d.StatusCode=''ARCHIVED'' AND
                           (i.StatusCode<>''ARCHIVED'' OR i.ActivatedAtUtc<>d.ActivatedAtUtc
                            OR ISNULL(i.ArchivedAtUtc,CONVERT(DATETIME2(3),''19000101''))
                               <>ISNULL(d.ArchivedAtUtc,CONVERT(DATETIME2(3),''19000101''))))
            )
                THROW 53107, ''Active and archived notification versions are immutable.'', 1;
        END;');
    EXEC(N'
        CREATE TRIGGER ntf.trg_NotificationTemplateVersions_ActiveDelete
        ON ntf.NotificationTemplateVersions
        INSTEAD OF DELETE
        AS
        BEGIN
            SET NOCOUNT ON;
            IF EXISTS(SELECT 1 FROM deleted WHERE StatusCode IN(''ACTIVE'',''ARCHIVED''))
                THROW 53108, ''Active and archived notification versions cannot be deleted.'', 1;
            DELETE target
            FROM ntf.NotificationTemplateVersions target
            JOIN deleted item ON item.TemplateVersionId=target.TemplateVersionId;
        END;');

    DECLARE @ActionId BIGINT=(SELECT AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1);
    DECLARE @ResultId BIGINT=(SELECT AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1);
    IF @ActionId IS NULL OR @ResultId IS NULL
        THROW 53106, 'Required CREATE/SUCCESS audit definitions are missing.', 1;
    INSERT aud.AuditEvents
        (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,ChangeSummaryJson,RequestId,CorrelationId)
    VALUES
        (CONCAT(N'KLOP.NOTIFICATIONS.V1.11 DBA: ',SUSER_SNAME()),@ActionId,@ResultId,
         N'NOTIFICATION_SCHEMA',N'v1.11',
         N'{"action":"NOTIFICATION_SCHEMA_CREATED","roleMappings":"NONE","smtpValues":"UNCHANGED"}',
         CONVERT(VARCHAR(100),@ApprovalTicket),NEWID());
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
