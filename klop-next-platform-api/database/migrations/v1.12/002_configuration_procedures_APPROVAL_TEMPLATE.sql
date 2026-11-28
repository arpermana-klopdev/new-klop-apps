:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Stored-procedure-only boundary for the proposed v1.12 safe catalog and change lifecycle.
-- Default execution refuses. No direct table grants or configuration values are exposed.
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 53510, 'DRY RUN - explicit owner approval and a change ticket are required.', 1;
IF N'$(KLOP_ENVIRONMENT)'<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53511, 'Refused: this template is restricted to the reviewed Development environment.', 1;
IF N'$(KLOP_EXPECTED_DATABASE)'<>N'KlopPlatformDB' OR DB_NAME()<>N'$(KLOP_EXPECTED_DATABASE)'
    THROW 53512, 'Refused: target database does not match the reviewed Development database.', 1;
IF OBJECT_ID(N'cfg.ConfigurationManagementPolicies',N'U') IS NULL
   OR OBJECT_ID(N'cfg.ConfigurationChangeRequests',N'U') IS NULL
   OR OBJECT_ID(N'cfg.ConfigurationChangeDecisions',N'U') IS NULL
   OR OBJECT_ID(N'cfg.ConfigurationAppliedHistory',N'U') IS NULL
   OR OBJECT_ID(N'cfg.SystemConfigurations',N'U') IS NULL
   OR OBJECT_ID(N'aud.AuditEvents',N'U') IS NULL
   OR OBJECT_ID(N'iam.usp_ValidateSessionAccess',N'P') IS NULL
   OR OBJECT_ID(N'iam.usp_ValidatePlatformPermission',N'P') IS NULL
    THROW 53513, 'Apply the reviewed v1.12 schema and v1.10/v1.11 authorization prerequisites first.', 1;
GO

CREATE OR ALTER PROCEDURE cfg.usp_ConfigurationManagement_ListCatalog
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,
    @Category VARCHAR(80)=NULL,@PageNumber INT=1,@PageSize INT=25
AS
BEGIN
    SET NOCOUNT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.configurations.read';
    IF @PageNumber NOT BETWEEN 1 AND 100000 OR @PageSize NOT BETWEEN 1 AND 100
        THROW 53593, 'The configuration catalog page is invalid.', 1;
    IF LEN(ISNULL(@Category,''))>80
        THROW 53593, 'The configuration catalog filter is invalid.', 1;

    DECLARE @ApprovedCatalog TABLE
    (
        ConfigurationKey VARCHAR(150) NOT NULL,
        Category VARCHAR(80) NOT NULL,
        ValueType VARCHAR(20) NOT NULL,
        StorageType VARCHAR(30) NOT NULL,
        MinimumInteger INT NULL,
        MaximumInteger INT NULL
    );
    INSERT @ApprovedCatalog VALUES
      ('auth.access_token_minutes','Authentication','INTEGER','PLAIN',5,60),
      ('auth.refresh_token_days','Authentication','INTEGER','PLAIN',1,30),
      ('auth.email_verification_hours','Authentication','INTEGER','PLAIN',1,24),
      ('security.max_login_attempts','Security','INTEGER','PLAIN',3,10),
      ('security.password.min_length','Security','INTEGER','PLAIN',12,128),
      ('security.auth_requests_per_minute','Security','INTEGER','PLAIN',1,120),
      ('registration.personal.enabled','Registration','BOOLEAN','PLAIN',NULL,NULL),
      ('registration.organization.enabled','Registration','BOOLEAN','PLAIN',NULL,NULL),
      ('registration.legal_consent_enforcement','Registration','BOOLEAN','PLAIN',NULL,NULL),
      ('notification.email_verification_templates.enabled','Notifications','BOOLEAN','PLAIN',NULL,NULL),
      ('notification.email_verification_delivery_audit.enabled','Notifications','BOOLEAN','PLAIN',NULL,NULL),
      ('database.command_timeout_seconds','Database','INTEGER','PLAIN',1,120);

    DECLARE @Catalog TABLE
    (
        ConfigurationKey VARCHAR(150) NOT NULL,
        Category VARCHAR(80) NOT NULL,
        ValueType VARCHAR(20) NOT NULL,
        StorageType VARCHAR(30) NOT NULL,
        Readiness VARCHAR(20) NOT NULL,
        ManagementStatus VARCHAR(20) NOT NULL,
        IsEditable BIT NOT NULL,
        RequiresApproval BIT NOT NULL,
        RequiresRestart BIT NOT NULL,
        VersionNumber INT NULL,
        ConcurrencyVersion BINARY(8) NULL,
        CreatedAtUtc DATETIME2(3) NULL,
        UpdatedAtUtc DATETIME2(3) NULL,
        Minimum DECIMAL(18,4) NULL,
        Maximum DECIMAL(18,4) NULL
    );

    INSERT @Catalog
    SELECT approved.ConfigurationKey,approved.Category,approved.ValueType,approved.StorageType,
        CASE
          WHEN policy.ConfigurationKey IS NULL THEN 'INVALID'
          WHEN policy.Category<>approved.Category OR policy.ValueType<>approved.ValueType
            OR policy.StorageType<>approved.StorageType OR policy.RequiresApproval<>1
            OR policy.RequiresRestart<>1
            OR ISNULL(policy.MinimumInteger,-2147483648)<>ISNULL(approved.MinimumInteger,-2147483648)
            OR ISNULL(policy.MaximumInteger,-2147483648)<>ISNULL(approved.MaximumInteger,-2147483648)
            THEN 'INVALID'
          WHEN config.ConfigurationId IS NULL THEN 'MISSING'
          WHEN config.IsActive=0 THEN 'INACTIVE'
          WHEN config.ValueType<>approved.ValueType OR config.StorageType<>approved.StorageType THEN 'INVALID'
          WHEN config.RequiresApproval<>1 OR config.RequiresRestart<>1 THEN 'INVALID'
          WHEN approved.ValueType='INTEGER'
               AND (LTRIM(RTRIM(config.ConfigurationValue)) LIKE '%[^0-9]%'
                    OR TRY_CONVERT(INT,config.ConfigurationValue) IS NULL
                    OR TRY_CONVERT(INT,config.ConfigurationValue)<
                       CASE WHEN config.MinNumericValue IS NULL THEN approved.MinimumInteger
                            WHEN config.MinNumericValue>approved.MinimumInteger THEN config.MinNumericValue
                            ELSE approved.MinimumInteger END
                    OR TRY_CONVERT(INT,config.ConfigurationValue)>
                       CASE WHEN config.MaxNumericValue IS NULL THEN approved.MaximumInteger
                            WHEN config.MaxNumericValue<approved.MaximumInteger THEN config.MaxNumericValue
                            ELSE approved.MaximumInteger END
                    OR (config.MinNumericValue IS NOT NULL AND config.MaxNumericValue IS NOT NULL
                        AND config.MinNumericValue>config.MaxNumericValue)) THEN 'INVALID'
          WHEN approved.ValueType='BOOLEAN'
               AND LOWER(LTRIM(RTRIM(config.ConfigurationValue))) NOT IN('true','false') THEN 'INVALID'
          ELSE 'PRESENT'
        END,
        CASE WHEN policy.ConfigurationKey IS NULL THEN 'MISSING'
             WHEN policy.Category<>approved.Category OR policy.ValueType<>approved.ValueType
               OR policy.StorageType<>approved.StorageType OR policy.RequiresApproval<>1
               OR policy.RequiresRestart<>1
               OR ISNULL(policy.MinimumInteger,-2147483648)<>ISNULL(approved.MinimumInteger,-2147483648)
               OR ISNULL(policy.MaximumInteger,-2147483648)<>ISNULL(approved.MaximumInteger,-2147483648)
             THEN 'INVALID' ELSE policy.ManagementStatus END,
        CONVERT(BIT,CASE WHEN policy.IsManageable=1 AND policy.ManagementStatus='ACTIVE'
                          AND policy.Category=approved.Category AND policy.ValueType=approved.ValueType
                          AND policy.StorageType=approved.StorageType AND policy.RequiresApproval=1
                          AND policy.RequiresRestart=1
                          AND policy.MinimumInteger=approved.MinimumInteger
                          AND policy.MaximumInteger=approved.MaximumInteger
                          AND config.IsActive=1 AND config.IsEditable=1 AND config.IsSensitive=0
                          AND config.StorageType='PLAIN' AND config.RequiresApproval=1
                          AND config.RequiresRestart=1 AND policy.ValueType='INTEGER'
                          AND policy.ConfigurationKey='database.command_timeout_seconds'
                         THEN 1 ELSE 0 END),
        CASE WHEN config.ConfigurationId IS NULL THEN CONVERT(BIT,1) ELSE config.RequiresApproval END,
        CASE WHEN config.ConfigurationId IS NULL THEN CONVERT(BIT,1) ELSE config.RequiresRestart END,
        config.VersionNumber,config.RowVersion,config.CreatedAtUtc,config.UpdatedAtUtc,
        CASE WHEN approved.MinimumInteger IS NULL THEN config.MinNumericValue
             WHEN config.MinNumericValue IS NULL THEN approved.MinimumInteger
             WHEN config.MinNumericValue>approved.MinimumInteger THEN config.MinNumericValue
             ELSE approved.MinimumInteger END,
        CASE WHEN approved.MaximumInteger IS NULL THEN config.MaxNumericValue
             WHEN config.MaxNumericValue IS NULL THEN approved.MaximumInteger
             WHEN config.MaxNumericValue<approved.MaximumInteger THEN config.MaxNumericValue
             ELSE approved.MaximumInteger END
    FROM @ApprovedCatalog approved
    LEFT JOIN cfg.ConfigurationManagementPolicies policy
      ON policy.ConfigurationKey=approved.ConfigurationKey
    LEFT JOIN cfg.SystemConfigurations config
      ON config.ConfigurationKey=approved.ConfigurationKey
    WHERE (@Category IS NULL OR approved.Category=@Category);
    UPDATE @Catalog SET IsEditable=0
    WHERE Readiness<>'PRESENT' OR ManagementStatus<>'ACTIVE';

    SELECT COUNT_BIG(*) AS TotalCount,
           (SELECT COUNT_BIG(*) FROM cfg.SystemConfigurations config
             WHERE NOT EXISTS
                 (SELECT 1 FROM @ApprovedCatalog approved
                  WHERE approved.ConfigurationKey=config.ConfigurationKey)) AS UnclassifiedCount
    FROM @Catalog;
    SELECT ConfigurationKey,Category,ValueType,StorageType,Readiness,ManagementStatus,IsEditable,
           RequiresApproval,RequiresRestart,VersionNumber,ConcurrencyVersion,CreatedAtUtc,UpdatedAtUtc,Minimum,Maximum
    FROM @Catalog
    ORDER BY Category,ConfigurationKey
    OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE cfg.usp_ConfigurationManagement_ListRequests
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,
    @Status VARCHAR(20)='ALL',@PageNumber INT=1,@PageSize INT=25
AS
BEGIN
    SET NOCOUNT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.configurations.read';
    IF @Status='SUBMITTED'
        EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.configurations.approve';
    IF @PageNumber NOT BETWEEN 1 AND 100000 OR @PageSize NOT BETWEEN 1 AND 100
       OR @Status NOT IN('ALL','DRAFT','SUBMITTED','APPROVED','REJECTED','CANCELED','APPLIED')
        THROW 53593, 'The configuration request page is invalid.', 1;
    SELECT COUNT_BIG(*) FROM cfg.ConfigurationChangeRequests request
    JOIN cfg.ConfigurationManagementPolicies policy ON policy.ConfigurationKey=request.ConfigurationKey
    WHERE request.ConfigurationKey='database.command_timeout_seconds'
      AND (@Status='ALL' OR request.StatusCode=@Status);
    SELECT request.RequestId,request.ConfigurationKey,request.StatusCode AS Status,
           request.ProposedInteger,request.ExpectedVersionNumber,request.ReasonCode,
           request.CreatedAtUtc,request.UpdatedAtUtc,request.RowVersion AS RequestConcurrencyVersion
    FROM cfg.ConfigurationChangeRequests request
    JOIN cfg.ConfigurationManagementPolicies policy ON policy.ConfigurationKey=request.ConfigurationKey
    WHERE request.ConfigurationKey='database.command_timeout_seconds'
      AND (@Status='ALL' OR request.StatusCode=@Status)
    ORDER BY request.CreatedAtUtc DESC,request.RequestId DESC
    OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE cfg.usp_ConfigurationManagement_ListHistory
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,@PageNumber INT=1,@PageSize INT=25
AS
BEGIN
    SET NOCOUNT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.configurations.history';
    IF @PageNumber NOT BETWEEN 1 AND 100000 OR @PageSize NOT BETWEEN 1 AND 100
        THROW 53593, 'The configuration history page is invalid.', 1;
    SELECT COUNT_BIG(*) FROM cfg.ConfigurationAppliedHistory history
    WHERE history.ConfigurationKey='database.command_timeout_seconds';
    SELECT history.HistoryId,history.ConfigurationKey,history.VersionNumber,
           CONVERT(VARCHAR(20),'APPLIED') AS ChangeType,history.AppliedInteger,history.ReasonCode,
           history.OccurredAtUtc,history.ActorUserId
    FROM cfg.ConfigurationAppliedHistory history
    ORDER BY history.OccurredAtUtc DESC,history.HistoryId DESC
    OFFSET (@PageNumber-1)*@PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE cfg.usp_ConfigurationManagement_CreateDraft
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,@ConfigurationKey VARCHAR(150),
    @ProposedInteger INT,@ExpectedVersionNumber INT,@ExpectedTargetRowVersion BINARY(8),
    @ReasonCode VARCHAR(40),@RequestIdHeader VARCHAR(100),@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.configurations.request.create';
    IF @ConfigurationKey<>'database.command_timeout_seconds'
       OR @ReasonCode NOT IN('ROUTINE_MAINTENANCE','CAPACITY_ADJUSTMENT','INCIDENT_FOLLOWUP')
        THROW 53593, 'The configuration request is invalid.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @PolicyRowVersion BINARY(8),@Minimum INT,@Maximum INT,@Manageable BIT,@PolicyStatus VARCHAR(20);
        DECLARE @TargetVersion INT,@TargetRowVersion BINARY(8),@Editable BIT,@Sensitive BIT,
                @StorageType VARCHAR(30),@ValueType VARCHAR(20),@TargetRequiresApproval BIT,
                @TargetRequiresRestart BIT,@TargetMinimum DECIMAL(18,4),@TargetMaximum DECIMAL(18,4);
        SELECT @PolicyRowVersion=RowVersion,@Minimum=MinimumInteger,@Maximum=MaximumInteger,
               @Manageable=IsManageable,@PolicyStatus=ManagementStatus
        FROM cfg.ConfigurationManagementPolicies WITH(UPDLOCK,HOLDLOCK)
        WHERE ConfigurationKey=@ConfigurationKey AND ValueType='INTEGER' AND StorageType='PLAIN';
        SELECT @TargetVersion=VersionNumber,@TargetRowVersion=RowVersion,@Editable=IsEditable,
               @Sensitive=IsSensitive,@StorageType=StorageType,@ValueType=ValueType,
               @TargetRequiresApproval=RequiresApproval,@TargetRequiresRestart=RequiresRestart,
               @TargetMinimum=MinNumericValue,@TargetMaximum=MaxNumericValue
        FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK)
        WHERE ConfigurationKey=@ConfigurationKey AND IsActive=1;
        IF @PolicyRowVersion IS NULL OR @Manageable<>1 OR @PolicyStatus<>'ACTIVE'
           OR ISNULL(@Minimum,0)<>1 OR ISNULL(@Maximum,0)<>120
           OR @TargetVersion IS NULL OR @Editable<>1 OR @Sensitive<>0
           OR @StorageType<>'PLAIN' OR @ValueType<>'INTEGER'
           OR @TargetRequiresApproval<>1 OR @TargetRequiresRestart<>1
            THROW 53592, 'This configuration key is held or unavailable for management.', 1;
        IF @ProposedInteger NOT BETWEEN 1 AND 120
           OR @ProposedInteger NOT BETWEEN @Minimum AND @Maximum
           OR (@TargetMinimum IS NOT NULL AND @ProposedInteger<@TargetMinimum)
           OR (@TargetMaximum IS NOT NULL AND @ProposedInteger>@TargetMaximum)
           OR (@TargetMinimum IS NOT NULL AND @TargetMaximum IS NOT NULL
               AND @TargetMinimum>@TargetMaximum)
           OR @ExpectedVersionNumber<>@TargetVersion
           OR @ExpectedTargetRowVersion<>@TargetRowVersion
            THROW 53591, 'The requested configuration value or target version is stale or outside policy.', 1;
        DECLARE @RequestId UNIQUEIDENTIFIER=NEWID();
        INSERT cfg.ConfigurationChangeRequests
            (RequestId,ConfigurationKey,ProposedInteger,ExpectedVersionNumber,
             ExpectedTargetRowVersion,ExpectedPolicyRowVersion,ReasonCode,RequesterUserId)
        VALUES(@RequestId,@ConfigurationKey,@ProposedInteger,@ExpectedVersionNumber,
               @ExpectedTargetRowVersion,@PolicyRowVersion,@ReasonCode,@ActorUserId);
        INSERT aud.AuditEvents(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
                               ChangeSummaryJson,RequestId,CorrelationId)
        SELECT @ActorUserId,act.AuditActionTypeId,res.AuditResultTypeId,N'CONFIGURATION_CHANGE_REQUEST',
               CONVERT(NVARCHAR(150),@RequestId),
               (SELECT @ConfigurationKey AS ConfigurationKey,N'DRAFT_CREATED' AS Action,
                       @ProposedInteger AS ProposedInteger,@ReasonCode AS ReasonCode
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@RequestIdHeader,@CorrelationId
        FROM mst.AuditActionTypes act CROSS JOIN mst.AuditResultTypes res
        WHERE act.Code='CREATE' AND act.IsActive=1 AND res.Code='SUCCESS' AND res.IsActive=1;
        IF @@ROWCOUNT<>1 THROW 53596, 'Configuration audit metadata is unavailable.', 1;
        COMMIT TRANSACTION;
        SELECT RequestId,RowVersion AS RequestConcurrencyVersion
        FROM cfg.ConfigurationChangeRequests WHERE RequestId=@RequestId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE cfg.usp_ConfigurationManagement_UpdateDraft
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,@RequestId UNIQUEIDENTIFIER,
    @ProposedInteger INT,@ReasonCode VARCHAR(40),@ExpectedRequestRowVersion BINARY(8),
    @RequestIdHeader VARCHAR(100),@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.configurations.request.edit';
    IF @ReasonCode NOT IN('ROUTINE_MAINTENANCE','CAPACITY_ADJUSTMENT','INCIDENT_FOLLOWUP')
        THROW 53593, 'The configuration request is invalid.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Key VARCHAR(150),@ExpectedVersion INT,@TargetRowVersion BINARY(8),
                @ExpectedPolicyRowVersion BINARY(8),@Requester BIGINT,@CurrentRowVersion BINARY(8);
        SELECT @Key=ConfigurationKey,@ExpectedVersion=ExpectedVersionNumber,
               @TargetRowVersion=ExpectedTargetRowVersion,@ExpectedPolicyRowVersion=ExpectedPolicyRowVersion,
               @Requester=RequesterUserId,@CurrentRowVersion=RowVersion
        FROM cfg.ConfigurationChangeRequests WITH(UPDLOCK,HOLDLOCK)
        WHERE RequestId=@RequestId AND StatusCode='DRAFT';
        IF @Key IS NULL OR @Requester<>@ActorUserId OR @CurrentRowVersion<>@ExpectedRequestRowVersion
            THROW 53591, 'The configuration request changed or is not editable.', 1;
        DECLARE @PolicyRowVersion BINARY(8),@Minimum INT,@Maximum INT,@Manageable BIT,@PolicyStatus VARCHAR(20);
        SELECT @PolicyRowVersion=RowVersion,@Minimum=MinimumInteger,@Maximum=MaximumInteger,
               @Manageable=IsManageable,@PolicyStatus=ManagementStatus
        FROM cfg.ConfigurationManagementPolicies WITH(UPDLOCK,HOLDLOCK)
        WHERE ConfigurationKey=@Key AND ValueType='INTEGER' AND StorageType='PLAIN';
        IF @Key<>'database.command_timeout_seconds' OR @Manageable<>1 OR @PolicyStatus<>'ACTIVE'
           OR ISNULL(@Minimum,0)<>1 OR ISNULL(@Maximum,0)<>120
           OR @PolicyRowVersion<>@ExpectedPolicyRowVersion
            THROW 53592, 'The configuration management policy changed or is held.', 1;
        IF @ProposedInteger NOT BETWEEN 1 AND 120
           OR @ProposedInteger NOT BETWEEN @Minimum AND @Maximum
            THROW 53593, 'The proposed integer is outside the approved numeric policy.', 1;
        DECLARE @TargetMinimum DECIMAL(18,4),@TargetMaximum DECIMAL(18,4);
        SELECT @TargetMinimum=MinNumericValue,@TargetMaximum=MaxNumericValue
        FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK)
        WHERE ConfigurationKey=@Key AND IsActive=1 AND IsEditable=1 AND IsSensitive=0
          AND ValueType='INTEGER' AND StorageType='PLAIN'
          AND RequiresApproval=1 AND RequiresRestart=1
          AND VersionNumber=@ExpectedVersion AND RowVersion=@TargetRowVersion;
        IF @@ROWCOUNT<>1 OR (@TargetMinimum IS NOT NULL AND @ProposedInteger<@TargetMinimum)
           OR (@TargetMaximum IS NOT NULL AND @ProposedInteger>@TargetMaximum)
           OR (@TargetMinimum IS NOT NULL AND @TargetMaximum IS NOT NULL
               AND @TargetMinimum>@TargetMaximum)
            THROW 53591, 'The target configuration changed or no longer satisfies numeric policy.', 1;
        IF NOT EXISTS
        (
            SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK)
            WHERE ConfigurationKey=@Key AND IsActive=1 AND IsEditable=1 AND IsSensitive=0
              AND ValueType='INTEGER' AND StorageType='PLAIN'
              AND RequiresApproval=1 AND RequiresRestart=1
              AND VersionNumber=@ExpectedVersion AND RowVersion=@TargetRowVersion
        )
            THROW 53591, 'The target configuration changed after the request was created.', 1;
        UPDATE cfg.ConfigurationChangeRequests
        SET ProposedInteger=@ProposedInteger,ReasonCode=@ReasonCode,UpdatedAtUtc=SYSUTCDATETIME()
        WHERE RequestId=@RequestId AND StatusCode='DRAFT' AND RowVersion=@ExpectedRequestRowVersion;
        IF @@ROWCOUNT<>1 THROW 53591, 'The configuration request changed during update.', 1;
        INSERT aud.AuditEvents(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
                               ChangeSummaryJson,RequestId,CorrelationId)
        SELECT @ActorUserId,act.AuditActionTypeId,res.AuditResultTypeId,N'CONFIGURATION_CHANGE_REQUEST',
               CONVERT(NVARCHAR(150),@RequestId),
               (SELECT @Key AS ConfigurationKey,N'DRAFT_EDITED' AS Action,
                       @ProposedInteger AS ProposedInteger,@ReasonCode AS ReasonCode
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@RequestIdHeader,@CorrelationId
        FROM mst.AuditActionTypes act CROSS JOIN mst.AuditResultTypes res
        WHERE act.Code='UPDATE' AND act.IsActive=1 AND res.Code='SUCCESS' AND res.IsActive=1;
        IF @@ROWCOUNT<>1 THROW 53596, 'Configuration audit metadata is unavailable.', 1;
        COMMIT TRANSACTION;
        SELECT RequestId,RowVersion AS RequestConcurrencyVersion
        FROM cfg.ConfigurationChangeRequests WHERE RequestId=@RequestId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE cfg.usp_ConfigurationManagement_Transition
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,@RequestId UNIQUEIDENTIFIER,
    @ActionCode VARCHAR(20),@DecisionCode VARCHAR(20)=NULL,@ExpectedRequestRowVersion BINARY(8),
    @RequestIdHeader VARCHAR(100),@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @PermissionCode VARCHAR(150)=CASE
        WHEN @ActionCode='SUBMIT' AND @DecisionCode='SUBMIT' THEN 'platform.configurations.request.submit'
        WHEN @ActionCode='CANCEL' AND @DecisionCode='CANCEL' THEN 'platform.configurations.request.cancel'
        WHEN @ActionCode='APPROVAL' AND @DecisionCode IN('APPROVE','REJECT') THEN 'platform.configurations.approve'
        ELSE NULL END;
    IF @PermissionCode IS NULL THROW 53593, 'The configuration transition is invalid.', 1;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,@PermissionCode;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Key VARCHAR(150),@Status VARCHAR(20),@Requester BIGINT,@CurrentRowVersion BINARY(8),
                @ExpectedVersion INT,@TargetRowVersion BINARY(8),@ExpectedPolicyRowVersion BINARY(8),
                @Approver BIGINT,@ProposedInteger INT,@ReasonCode VARCHAR(40),
                @TargetMinimum DECIMAL(18,4),@TargetMaximum DECIMAL(18,4);
        SELECT @Key=ConfigurationKey,@Status=StatusCode,@Requester=RequesterUserId,
               @CurrentRowVersion=RowVersion,@ExpectedVersion=ExpectedVersionNumber,
               @TargetRowVersion=ExpectedTargetRowVersion,@ExpectedPolicyRowVersion=ExpectedPolicyRowVersion,
               @Approver=ApproverUserId,@ProposedInteger=ProposedInteger,@ReasonCode=ReasonCode
        FROM cfg.ConfigurationChangeRequests WITH(UPDLOCK,HOLDLOCK) WHERE RequestId=@RequestId;
        IF @Key IS NULL OR @CurrentRowVersion<>@ExpectedRequestRowVersion
            THROW 53591, 'The configuration request changed or does not exist.', 1;
        IF (@ActionCode='SUBMIT' AND (@Status<>'DRAFT' OR @Requester<>@ActorUserId))
           OR (@ActionCode='APPROVAL' AND (@Status<>'SUBMITTED' OR @Requester=@ActorUserId))
           OR (@ActionCode='CANCEL' AND (@Status NOT IN('DRAFT','SUBMITTED') OR @Requester<>@ActorUserId))
            THROW 53595, 'The configuration request is not in a valid state for this action.', 1;
        DECLARE @PolicyRowVersion BINARY(8),@Minimum INT,@Maximum INT,@Manageable BIT,@PolicyStatus VARCHAR(20);
        SELECT @PolicyRowVersion=RowVersion,@Minimum=MinimumInteger,@Maximum=MaximumInteger,
               @Manageable=IsManageable,@PolicyStatus=ManagementStatus
        FROM cfg.ConfigurationManagementPolicies WITH(UPDLOCK,HOLDLOCK)
        WHERE ConfigurationKey=@Key AND ValueType='INTEGER' AND StorageType='PLAIN';
        IF @Key<>'database.command_timeout_seconds' OR @Manageable<>1 OR @PolicyStatus<>'ACTIVE'
           OR ISNULL(@Minimum,0)<>1 OR ISNULL(@Maximum,0)<>120
           OR @PolicyRowVersion<>@ExpectedPolicyRowVersion
            THROW 53592, 'The configuration management policy changed or is held.', 1;
        IF @ActionCode<>'CANCEL'
        BEGIN
            IF @ProposedInteger NOT BETWEEN 1 AND 120
               OR @ProposedInteger NOT BETWEEN @Minimum AND @Maximum
                THROW 53593, 'The proposed integer is outside the approved numeric policy.', 1;
            SELECT @TargetMinimum=MinNumericValue,@TargetMaximum=MaxNumericValue
            FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK)
            WHERE ConfigurationKey=@Key AND IsActive=1 AND IsEditable=1 AND IsSensitive=0
              AND ValueType='INTEGER' AND StorageType='PLAIN'
              AND RequiresApproval=1 AND RequiresRestart=1
              AND VersionNumber=@ExpectedVersion AND RowVersion=@TargetRowVersion;
            IF @@ROWCOUNT<>1 OR (@TargetMinimum IS NOT NULL AND @ProposedInteger<@TargetMinimum)
               OR (@TargetMaximum IS NOT NULL AND @ProposedInteger>@TargetMaximum)
               OR (@TargetMinimum IS NOT NULL AND @TargetMaximum IS NOT NULL
                   AND @TargetMinimum>@TargetMaximum)
                THROW 53591, 'The target configuration changed or no longer satisfies numeric policy.', 1;
            IF NOT EXISTS
            (
                SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK)
                WHERE ConfigurationKey=@Key AND IsActive=1 AND IsEditable=1 AND IsSensitive=0
                  AND ValueType='INTEGER' AND StorageType='PLAIN'
                  AND RequiresApproval=1 AND RequiresRestart=1
                  AND VersionNumber=@ExpectedVersion AND RowVersion=@TargetRowVersion
            )
                THROW 53591, 'The target configuration changed after the request was created.', 1;
        END;

        IF @ActionCode='APPROVAL'
        BEGIN
            INSERT cfg.ConfigurationChangeDecisions(RequestId,DecisionCode,ActorUserId)
            VALUES(@RequestId,@DecisionCode,@ActorUserId);
            UPDATE cfg.ConfigurationChangeRequests
            SET StatusCode=CASE @DecisionCode WHEN 'APPROVE' THEN 'APPROVED' ELSE 'REJECTED' END,
                ApproverUserId=@ActorUserId,DecidedAtUtc=SYSUTCDATETIME(),UpdatedAtUtc=SYSUTCDATETIME()
            WHERE RequestId=@RequestId AND StatusCode='SUBMITTED'
              AND RowVersion=@ExpectedRequestRowVersion;
        END
        ELSE
            UPDATE cfg.ConfigurationChangeRequests
            SET StatusCode=CASE @ActionCode WHEN 'SUBMIT' THEN 'SUBMITTED' ELSE 'CANCELED' END,
                SubmittedAtUtc=CASE WHEN @ActionCode='SUBMIT' THEN SYSUTCDATETIME() ELSE SubmittedAtUtc END,
                UpdatedAtUtc=SYSUTCDATETIME()
            WHERE RequestId=@RequestId AND StatusCode=@Status
              AND RowVersion=@ExpectedRequestRowVersion;
        IF @@ROWCOUNT<>1 THROW 53591, 'The configuration request changed during transition.', 1;
        INSERT aud.AuditEvents(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
                               ChangeSummaryJson,RequestId,CorrelationId)
        SELECT @ActorUserId,act.AuditActionTypeId,res.AuditResultTypeId,N'CONFIGURATION_CHANGE_REQUEST',
               CONVERT(NVARCHAR(150),@RequestId),
               (SELECT @Key AS ConfigurationKey,@ActionCode AS Action,@DecisionCode AS Decision,
                       @ProposedInteger AS ProposedInteger,@ReasonCode AS ReasonCode
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@RequestIdHeader,@CorrelationId
        FROM mst.AuditActionTypes act CROSS JOIN mst.AuditResultTypes res
        WHERE act.Code=CASE WHEN @ActionCode='APPROVAL' THEN 'UPDATE' ELSE 'UPDATE' END
          AND act.IsActive=1 AND res.Code='SUCCESS' AND res.IsActive=1;
        IF @@ROWCOUNT<>1 THROW 53596, 'Configuration audit metadata is unavailable.', 1;
        COMMIT TRANSACTION;
        SELECT RequestId,RowVersion AS RequestConcurrencyVersion
        FROM cfg.ConfigurationChangeRequests WHERE RequestId=@RequestId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE cfg.usp_ConfigurationManagement_Apply
    @ActorUserId BIGINT,@PublicSessionId UNIQUEIDENTIFIER,@RequestId UNIQUEIDENTIFIER,
    @ExpectedRequestRowVersion BINARY(8),@RequestIdHeader VARCHAR(100),@CorrelationId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    EXEC iam.usp_ValidatePlatformPermission @ActorUserId,@PublicSessionId,'platform.configurations.apply';
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Key VARCHAR(150),@Status VARCHAR(20),@Requester BIGINT,@Approver BIGINT,
                @CurrentRequestRowVersion BINARY(8),@ExpectedVersion INT,@TargetRowVersion BINARY(8),
                @ExpectedPolicyRowVersion BINARY(8),@ProposedInteger INT,@ReasonCode VARCHAR(40),
                @Minimum INT,@Maximum INT,@Manageable BIT,@PolicyStatus VARCHAR(20),@PolicyRowVersion BINARY(8),
                @TargetMinimum DECIMAL(18,4),@TargetMaximum DECIMAL(18,4);
        SELECT @Key=ConfigurationKey,@Status=StatusCode,@Requester=RequesterUserId,@Approver=ApproverUserId,
               @CurrentRequestRowVersion=RowVersion,@ExpectedVersion=ExpectedVersionNumber,
               @TargetRowVersion=ExpectedTargetRowVersion,@ExpectedPolicyRowVersion=ExpectedPolicyRowVersion,
               @ProposedInteger=ProposedInteger,@ReasonCode=ReasonCode
        FROM cfg.ConfigurationChangeRequests WITH(UPDLOCK,HOLDLOCK) WHERE RequestId=@RequestId;
        IF @Key IS NULL OR @CurrentRequestRowVersion<>@ExpectedRequestRowVersion
            THROW 53591, 'The configuration request changed or does not exist.', 1;
        IF @Status<>'APPROVED' OR @Requester=@ActorUserId OR @Approver IS NULL OR @Approver=@ActorUserId
           OR EXISTS(SELECT 1 FROM cfg.ConfigurationAppliedHistory WHERE RequestId=@RequestId)
            THROW 53595, 'The approved request cannot be applied by this actor or state.', 1;
        SELECT @PolicyRowVersion=RowVersion,@Minimum=MinimumInteger,@Maximum=MaximumInteger,
               @Manageable=IsManageable,@PolicyStatus=ManagementStatus
        FROM cfg.ConfigurationManagementPolicies WITH(UPDLOCK,HOLDLOCK)
        WHERE ConfigurationKey=@Key AND ValueType='INTEGER' AND StorageType='PLAIN';
        IF @Key<>'database.command_timeout_seconds' OR @Manageable<>1 OR @PolicyStatus<>'ACTIVE'
           OR ISNULL(@Minimum,0)<>1 OR ISNULL(@Maximum,0)<>120
           OR @PolicyRowVersion<>@ExpectedPolicyRowVersion
            THROW 53592, 'The configuration management policy changed or is held.', 1;
        IF @ProposedInteger NOT BETWEEN 1 AND 120
           OR @ProposedInteger NOT BETWEEN @Minimum AND @Maximum
            THROW 53593, 'The approved integer is outside the current numeric policy.', 1;
        SELECT @TargetMinimum=MinNumericValue,@TargetMaximum=MaxNumericValue
        FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK)
        WHERE ConfigurationKey=@Key AND IsActive=1 AND IsEditable=1 AND IsSensitive=0
          AND ValueType='INTEGER' AND StorageType='PLAIN'
          AND RequiresApproval=1 AND RequiresRestart=1
          AND VersionNumber=@ExpectedVersion AND RowVersion=@TargetRowVersion;
        IF @@ROWCOUNT<>1 OR (@TargetMinimum IS NOT NULL AND @ProposedInteger<@TargetMinimum)
           OR (@TargetMaximum IS NOT NULL AND @ProposedInteger>@TargetMaximum)
           OR (@TargetMinimum IS NOT NULL AND @TargetMaximum IS NOT NULL
               AND @TargetMinimum>@TargetMaximum)
            THROW 53591, 'The target configuration changed or no longer satisfies current constraints.', 1;

        UPDATE cfg.SystemConfigurations
        SET ConfigurationValue=CONVERT(NVARCHAR(20),@ProposedInteger),
            VersionNumber=VersionNumber+1,UpdatedByUserId=@ActorUserId,UpdatedAtUtc=SYSUTCDATETIME()
        WHERE ConfigurationKey=@Key AND IsActive=1 AND IsEditable=1 AND IsSensitive=0
          AND ValueType='INTEGER' AND StorageType='PLAIN'
          AND RequiresApproval=1 AND RequiresRestart=1
          AND VersionNumber=@ExpectedVersion AND RowVersion=@TargetRowVersion;
        IF @@ROWCOUNT<>1 THROW 53591, 'The target configuration changed during apply.', 1;
        DECLARE @NewVersion INT=(SELECT VersionNumber FROM cfg.SystemConfigurations WHERE ConfigurationKey=@Key);
        INSERT cfg.ConfigurationAppliedHistory
            (RequestId,ConfigurationKey,VersionNumber,AppliedInteger,ReasonCode,ActorUserId)
        VALUES(@RequestId,@Key,@NewVersion,@ProposedInteger,@ReasonCode,@ActorUserId);
        UPDATE cfg.ConfigurationChangeRequests
        SET StatusCode='APPLIED',AppliedByUserId=@ActorUserId,
            AppliedAtUtc=SYSUTCDATETIME(),UpdatedAtUtc=SYSUTCDATETIME()
        WHERE RequestId=@RequestId AND StatusCode='APPROVED'
          AND RowVersion=@ExpectedRequestRowVersion;
        IF @@ROWCOUNT<>1 THROW 53591, 'The configuration request changed during apply.', 1;
        INSERT aud.AuditEvents(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
                               ChangeSummaryJson,RequestId,CorrelationId)
        SELECT @ActorUserId,act.AuditActionTypeId,res.AuditResultTypeId,N'CONFIGURATION_APPLIED',
               @Key,
               (SELECT @Key AS ConfigurationKey,@NewVersion AS VersionNumber,
                       @ProposedInteger AS AppliedInteger,@ReasonCode AS ReasonCode,
                       N'RESTART_REQUIRED; RUNTIME_VALUE_UNCHANGED' AS RuntimeStatus
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),@RequestIdHeader,@CorrelationId
        FROM mst.AuditActionTypes act CROSS JOIN mst.AuditResultTypes res
        WHERE act.Code='UPDATE' AND act.IsActive=1 AND res.Code='SUCCESS' AND res.IsActive=1;
        IF @@ROWCOUNT<>1 THROW 53596, 'Configuration audit metadata is unavailable.', 1;
        COMMIT TRANSACTION;
        SELECT RequestId,RowVersion AS RequestConcurrencyVersion
        FROM cfg.ConfigurationChangeRequests WHERE RequestId=@RequestId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
