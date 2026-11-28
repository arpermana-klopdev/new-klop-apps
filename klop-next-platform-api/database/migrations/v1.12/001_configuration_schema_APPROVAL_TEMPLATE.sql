:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Proposed additive policy and immutable configuration change lifecycle schema.
-- No configuration values, existing defaults, roles, users, or role mappings are seeded or changed.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 53500, 'DRY RUN - explicit owner approval and a change ticket are required.', 1;
IF LEN(@ApprovalTicket)>100
    THROW 53500, 'Approval ticket must be at most 100 characters.', 1;
IF N'$(KLOP_ENVIRONMENT)'<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53501, 'Refused: this template is restricted to the reviewed Development environment.', 1;
IF N'$(KLOP_EXPECTED_DATABASE)'<>N'KlopPlatformDB' OR DB_NAME()<>N'$(KLOP_EXPECTED_DATABASE)'
    THROW 53502, 'Refused: target database does not match the reviewed Development database.', 1;
IF OBJECT_ID(N'cfg.SystemConfigurations',N'U') IS NULL
   OR OBJECT_ID(N'aud.AuditEvents',N'U') IS NULL
   OR OBJECT_ID(N'mst.AuditActionTypes',N'U') IS NULL
   OR OBJECT_ID(N'mst.AuditResultTypes',N'U') IS NULL
   OR OBJECT_ID(N'iam.usp_ValidateSessionAccess',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_ValidatePlatformPermission',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_GetPlatformPermissions',N'P') IS NULL
    THROW 53503, 'The existing configuration, audit, and v1.10/v1.11 authorization prerequisites are required.', 1;
IF COL_LENGTH(N'cfg.SystemConfigurations',N'ConfigurationKey') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'ConfigurationValue') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'ValueType') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'StorageType') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'MinNumericValue') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'MaxNumericValue') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'RequiresApproval') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'VersionNumber') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'IsActive') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'IsEditable') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'IsSensitive') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'RequiresRestart') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'UpdatedByUserId') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'UpdatedAtUtc') IS NULL
   OR COL_LENGTH(N'cfg.SystemConfigurations',N'RowVersion') IS NULL
    THROW 53503, 'The existing configuration table does not match the reviewed v1.1 source schema.', 1;
IF OBJECT_ID(N'cfg.ConfigurationManagementPolicies',N'U') IS NOT NULL
   OR OBJECT_ID(N'cfg.ConfigurationChangeRequests',N'U') IS NOT NULL
   OR OBJECT_ID(N'cfg.ConfigurationChangeDecisions',N'U') IS NOT NULL
   OR OBJECT_ID(N'cfg.ConfigurationAppliedHistory',N'U') IS NOT NULL
    THROW 53504, 'A v1.12 object already exists; stop for explicit reconciliation.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    CREATE TABLE cfg.ConfigurationManagementPolicies
    (
        ConfigurationKey VARCHAR(150) NOT NULL
            CONSTRAINT PK_ConfigurationManagementPolicies PRIMARY KEY,
        Category VARCHAR(80) NOT NULL,
        ValueType VARCHAR(20) NOT NULL,
        StorageType VARCHAR(30) NOT NULL,
        RequiresApproval BIT NOT NULL,
        RequiresRestart BIT NOT NULL,
        MinimumInteger INT NULL,
        MaximumInteger INT NULL,
        IsManageable BIT NOT NULL CONSTRAINT DF_ConfigurationManagementPolicies_IsManageable DEFAULT(0),
        ManagementStatus VARCHAR(20) NOT NULL CONSTRAINT DF_ConfigurationManagementPolicies_Status DEFAULT('HOLD'),
        CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_ConfigurationManagementPolicies_Created DEFAULT(SYSUTCDATETIME()),
        UpdatedAtUtc DATETIME2(3) NULL,
        RowVersion ROWVERSION NOT NULL,
        CONSTRAINT CK_ConfigurationManagementPolicies_Status CHECK(ManagementStatus IN('HOLD','ACTIVE')),
        CONSTRAINT CK_ConfigurationManagementPolicies_Managed CHECK(IsManageable=0 OR ManagementStatus='ACTIVE'),
        CONSTRAINT CK_ConfigurationManagementPolicies_IntegerBounds CHECK
            ((MinimumInteger IS NULL AND MaximumInteger IS NULL)
             OR (ValueType='INTEGER' AND MinimumInteger IS NOT NULL
                 AND MaximumInteger IS NOT NULL AND MinimumInteger<=MaximumInteger))
    );

    CREATE TABLE cfg.ConfigurationChangeRequests
    (
        RequestId UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_ConfigurationChangeRequests PRIMARY KEY
            DEFAULT(NEWSEQUENTIALID()),
        ConfigurationKey VARCHAR(150) NOT NULL,
        ProposedInteger INT NOT NULL,
        ExpectedVersionNumber INT NOT NULL,
        ExpectedTargetRowVersion BINARY(8) NOT NULL,
        ExpectedPolicyRowVersion BINARY(8) NOT NULL,
        ReasonCode VARCHAR(40) NOT NULL,
        StatusCode VARCHAR(20) NOT NULL CONSTRAINT DF_ConfigurationChangeRequests_Status DEFAULT('DRAFT'),
        RequesterUserId BIGINT NOT NULL,
        ApproverUserId BIGINT NULL,
        AppliedByUserId BIGINT NULL,
        CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_ConfigurationChangeRequests_Created DEFAULT(SYSUTCDATETIME()),
        UpdatedAtUtc DATETIME2(3) NULL,
        SubmittedAtUtc DATETIME2(3) NULL,
        DecidedAtUtc DATETIME2(3) NULL,
        AppliedAtUtc DATETIME2(3) NULL,
        RowVersion ROWVERSION NOT NULL,
        CONSTRAINT FK_ConfigurationChangeRequests_Policy FOREIGN KEY(ConfigurationKey)
            REFERENCES cfg.ConfigurationManagementPolicies(ConfigurationKey),
        CONSTRAINT CK_ConfigurationChangeRequests_Status CHECK
            (StatusCode IN('DRAFT','SUBMITTED','APPROVED','REJECTED','CANCELED','APPLIED')),
        CONSTRAINT CK_ConfigurationChangeRequests_Reason CHECK
            (ReasonCode IN('ROUTINE_MAINTENANCE','CAPACITY_ADJUSTMENT','INCIDENT_FOLLOWUP')),
        CONSTRAINT CK_ConfigurationChangeRequests_Version CHECK(ExpectedVersionNumber>0)
    );

    CREATE TABLE cfg.ConfigurationChangeDecisions
    (
        DecisionId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ConfigurationChangeDecisions PRIMARY KEY,
        RequestId UNIQUEIDENTIFIER NOT NULL,
        DecisionCode VARCHAR(10) NOT NULL,
        ActorUserId BIGINT NOT NULL,
        OccurredAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_ConfigurationChangeDecisions_Occurred DEFAULT(SYSUTCDATETIME()),
        CONSTRAINT FK_ConfigurationChangeDecisions_Request FOREIGN KEY(RequestId)
            REFERENCES cfg.ConfigurationChangeRequests(RequestId),
        CONSTRAINT CK_ConfigurationChangeDecisions_Code CHECK(DecisionCode IN('APPROVE','REJECT')),
        CONSTRAINT UQ_ConfigurationChangeDecisions_Request UNIQUE(RequestId)
    );

    CREATE TABLE cfg.ConfigurationAppliedHistory
    (
        HistoryId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ConfigurationAppliedHistory PRIMARY KEY,
        RequestId UNIQUEIDENTIFIER NOT NULL,
        ConfigurationKey VARCHAR(150) NOT NULL,
        VersionNumber INT NOT NULL,
        AppliedInteger INT NOT NULL,
        ReasonCode VARCHAR(40) NOT NULL,
        ActorUserId BIGINT NOT NULL,
        OccurredAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_ConfigurationAppliedHistory_Occurred DEFAULT(SYSUTCDATETIME()),
        CONSTRAINT FK_ConfigurationAppliedHistory_Request FOREIGN KEY(RequestId)
            REFERENCES cfg.ConfigurationChangeRequests(RequestId),
        CONSTRAINT UQ_ConfigurationAppliedHistory_Request UNIQUE(RequestId),
        CONSTRAINT CK_ConfigurationAppliedHistory_Version CHECK(VersionNumber>0)
    );

    CREATE INDEX IX_ConfigurationChangeRequests_StatusCreated
        ON cfg.ConfigurationChangeRequests(StatusCode,CreatedAtUtc DESC,RequestId DESC);
    CREATE INDEX IX_ConfigurationAppliedHistory_Occurred
        ON cfg.ConfigurationAppliedHistory(OccurredAtUtc DESC,HistoryId DESC);

    EXEC(N'CREATE TRIGGER cfg.trg_ConfigurationChangeRequests_Immutable
    ON cfg.ConfigurationChangeRequests AFTER UPDATE,DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        IF EXISTS(SELECT 1 FROM deleted d LEFT JOIN inserted i ON i.RequestId=d.RequestId
                  WHERE i.RequestId IS NULL)
            THROW 53506, ''Configuration requests cannot be deleted.'', 1;
        IF EXISTS
        (
            SELECT 1 FROM deleted d JOIN inserted i ON i.RequestId=d.RequestId
            WHERE i.ConfigurationKey<>d.ConfigurationKey
               OR i.ExpectedVersionNumber<>d.ExpectedVersionNumber
               OR i.ExpectedTargetRowVersion<>d.ExpectedTargetRowVersion
               OR i.ExpectedPolicyRowVersion<>d.ExpectedPolicyRowVersion
               OR i.RequesterUserId<>d.RequesterUserId
               OR i.CreatedAtUtc<>d.CreatedAtUtc
               OR (i.ApproverUserId<>d.ApproverUserId
                   AND NOT(d.StatusCode=''SUBMITTED'' AND i.StatusCode IN(''APPROVED'',''REJECTED'')))
               OR (i.AppliedByUserId<>d.AppliedByUserId
                   AND NOT(d.StatusCode=''APPROVED'' AND i.StatusCode=''APPLIED''))
               OR (ISNULL(i.SubmittedAtUtc,CONVERT(DATETIME2(3),''19000101''))<>
                   ISNULL(d.SubmittedAtUtc,CONVERT(DATETIME2(3),''19000101''))
                   AND NOT(d.StatusCode=''DRAFT'' AND i.StatusCode=''SUBMITTED''))
               OR (ISNULL(i.DecidedAtUtc,CONVERT(DATETIME2(3),''19000101''))<>
                   ISNULL(d.DecidedAtUtc,CONVERT(DATETIME2(3),''19000101''))
                   AND NOT(d.StatusCode=''SUBMITTED'' AND i.StatusCode IN(''APPROVED'',''REJECTED'')))
               OR (ISNULL(i.AppliedAtUtc,CONVERT(DATETIME2(3),''19000101''))<>
                   ISNULL(d.AppliedAtUtc,CONVERT(DATETIME2(3),''19000101''))
                   AND NOT(d.StatusCode=''APPROVED'' AND i.StatusCode=''APPLIED''))
               OR (d.StatusCode<>''DRAFT'' OR i.StatusCode<>''DRAFT'')
                  AND (i.ProposedInteger<>d.ProposedInteger OR i.ReasonCode<>d.ReasonCode)
               OR NOT
                  ((d.StatusCode=''DRAFT'' AND i.StatusCode IN(''DRAFT'',''SUBMITTED'',''CANCELED''))
                   OR (d.StatusCode=''SUBMITTED'' AND i.StatusCode IN(''SUBMITTED'',''APPROVED'',''REJECTED'',''CANCELED''))
                   OR (d.StatusCode=''APPROVED'' AND i.StatusCode IN(''APPROVED'',''APPLIED''))
                   OR (d.StatusCode=i.StatusCode AND d.StatusCode IN(''REJECTED'',''CANCELED'',''APPLIED'')))
        )
            THROW 53507, ''Configuration request content is immutable after submission or the state transition is invalid.'', 1;
    END;');

    EXEC(N'CREATE TRIGGER cfg.trg_ConfigurationChangeDecisions_AppendOnly
    ON cfg.ConfigurationChangeDecisions INSTEAD OF UPDATE,DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        THROW 53508, ''Configuration approval decisions are append-only.'', 1;
    END;');

    EXEC(N'CREATE TRIGGER cfg.trg_ConfigurationAppliedHistory_AppendOnly
    ON cfg.ConfigurationAppliedHistory INSTEAD OF UPDATE,DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        THROW 53509, ''Applied configuration history is append-only.'', 1;
    END;');

    DECLARE @Policy TABLE
    (
        ConfigurationKey VARCHAR(150) PRIMARY KEY,
        Category VARCHAR(80),
        ValueType VARCHAR(20),
        StorageType VARCHAR(30),
        RequiresApproval BIT,
        MinimumInteger INT NULL,
        MaximumInteger INT NULL
    );
    INSERT @Policy VALUES
      ('auth.access_token_minutes','Authentication','INTEGER','PLAIN',1,5,60),
      ('auth.refresh_token_days','Authentication','INTEGER','PLAIN',1,1,30),
      ('auth.email_verification_hours','Authentication','INTEGER','PLAIN',1,1,24),
      ('security.max_login_attempts','Security','INTEGER','PLAIN',1,3,10),
      ('security.password.min_length','Security','INTEGER','PLAIN',1,12,128),
      ('security.auth_requests_per_minute','Security','INTEGER','PLAIN',1,1,120),
      ('registration.personal.enabled','Registration','BOOLEAN','PLAIN',1,NULL,NULL),
      ('registration.organization.enabled','Registration','BOOLEAN','PLAIN',1,NULL,NULL),
      ('registration.legal_consent_enforcement','Registration','BOOLEAN','PLAIN',1,NULL,NULL),
      ('notification.email_verification_templates.enabled','Notifications','BOOLEAN','PLAIN',1,NULL,NULL),
      ('notification.email_verification_delivery_audit.enabled','Notifications','BOOLEAN','PLAIN',1,NULL,NULL),
      ('database.command_timeout_seconds','Database','INTEGER','PLAIN',1,1,120);

    INSERT cfg.ConfigurationManagementPolicies
        (ConfigurationKey,Category,ValueType,StorageType,RequiresApproval,RequiresRestart,
         MinimumInteger,MaximumInteger,IsManageable,ManagementStatus)
    SELECT ConfigurationKey,Category,ValueType,StorageType,RequiresApproval,1,
           MinimumInteger,MaximumInteger,0,'HOLD'
    FROM @Policy;

    INSERT aud.AuditEvents
        (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
         ChangeSummaryJson,RequestId,CorrelationId)
    SELECT CONCAT(N'KLOP.CONFIG.V1.12 DBA: ',SUSER_SNAME()),actionType.AuditActionTypeId,
           resultType.AuditResultTypeId,N'CONFIGURATION_POLICY_CATALOG',N'v1.12',
           (SELECT COUNT(*) AS ExplicitSafeCatalogRows,N'HOLD' AS ManagementStatus,
                   N'NO_ROLE_MAPPINGS' AS RoleMappings FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
           CONVERT(VARCHAR(100),@ApprovalTicket),NEWID()
    FROM mst.AuditActionTypes actionType CROSS JOIN mst.AuditResultTypes resultType
    WHERE actionType.Code='CREATE' AND actionType.IsActive=1
      AND resultType.Code='SUCCESS' AND resultType.IsActive=1;
    IF @@ROWCOUNT<>1 THROW 53505, 'Configuration catalog seed audit metadata is unavailable.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
