:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_TERMS_ENFORCEMENT "OFF"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPROVER "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- APPROVAL REQUIRED. This template is intentionally not executed by implementation work.
-- It updates only the existing registration.legal_consent_enforcement setting, and only in
-- DEV-PC\SQLEXPRESS / KlopPlatformDB. It does not configure the application bypass flag.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Environment nvarchar(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @Desired nvarchar(3)=UPPER(N'$(KLOP_TERMS_ENFORCEMENT)');
DECLARE @ApprovalTicketInput nvarchar(4000)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApprovalTicket varchar(100);
DECLARE @Approver nvarchar(200)=N'$(KLOP_APPROVER)';
DECLARE @ApplyChanges nvarchar(20)=N'$(KLOP_APPLY_CHANGES)';

IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 52900, 'Refused: this configuration template is Development-only.', 1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
    THROW 52901, 'Refused: this template is restricted to KlopPlatformDB.', 1;
IF @Desired NOT IN(N'ON',N'OFF')
    THROW 52902, 'Set KLOP_TERMS_ENFORCEMENT to ON or OFF.', 1;
IF LEN(@ApprovalTicketInput)>100
    THROW 52906, 'The approval ticket must be no more than 100 characters.', 1;
SET @ApprovalTicket=CONVERT(varchar(100),@ApprovalTicketInput);
IF CONVERT(nvarchar(100),@ApprovalTicket)<>@ApprovalTicketInput
    THROW 52907, 'The approval ticket must contain only characters supported by the audit request ID.', 1;

DECLARE @CurrentValue bit;
DECLARE @VersionNumber int;
DECLARE @ConfigurationId bigint;
SELECT @ConfigurationId=ConfigurationId,
       @CurrentValue=TRY_CONVERT(bit,ConfigurationValue),
       @VersionNumber=VersionNumber
FROM cfg.SystemConfigurations
WHERE ConfigurationKey=N'registration.legal_consent_enforcement'
  AND IsActive=1 AND ValueType='BOOLEAN' AND StorageType='PLAIN'
  AND RequiresApproval=1 AND IsSystem=1 AND IsEditable=0;
IF @ConfigurationId IS NULL OR @CurrentValue IS NULL
    THROW 52903, 'The expected protected configuration row is missing or has changed; stop for DBA review.', 1;

IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET') OR @Approver IN(N'',N'UNSET')
BEGIN
    SELECT N'NO CHANGES' AS Status,
           @CurrentValue AS CurrentTermsEnforcement,
           CONVERT(bit,CASE WHEN @Desired=N'ON' THEN 1 ELSE 0 END) AS RequestedTermsEnforcement,
           N'Provide a separately approved ticket and approver before any change.' AS ApprovalRequired;
    RETURN;
END;

IF @CurrentValue=CONVERT(bit,CASE WHEN @Desired=N'ON' THEN 1 ELSE 0 END)
BEGIN
    SELECT N'NO CHANGE REQUIRED' AS Status,
           @CurrentValue AS TermsEnforcement;
    RETURN;
END;

DECLARE @ActionId bigint=(SELECT AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='UPDATE' AND IsActive=1);
DECLARE @ResultId bigint=(SELECT AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1);
DECLARE @CorrelationId uniqueidentifier=NEWID();
DECLARE @NewValue bit=CONVERT(bit,CASE WHEN @Desired=N'ON' THEN 1 ELSE 0 END);
DECLARE @Summary nvarchar(max);
IF @ActionId IS NULL OR @ResultId IS NULL
    THROW 52904, 'Required configuration audit masters are unavailable.', 1;

SELECT @Summary=
(
    SELECT N'registration.legal_consent_enforcement' AS ConfigurationKey,
           @CurrentValue AS PreviousValue,
           @NewValue AS NewValue,
           @ApprovalTicket AS ApprovalTicket,
           @Approver AS Approver,
           N'No user consent is implied by a Development bypass.' AS Note
    FOR JSON PATH,WITHOUT_ARRAY_WRAPPER
);

BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE cfg.SystemConfigurations
    SET ConfigurationValue=CASE WHEN @NewValue=1 THEN N'true' ELSE N'false' END,
        VersionNumber=VersionNumber+1,
        UpdatedAtUtc=SYSUTCDATETIME()
    WHERE ConfigurationId=@ConfigurationId
      AND ConfigurationValue=CASE WHEN @CurrentValue=1 THEN N'true' ELSE N'false' END
      AND VersionNumber=@VersionNumber
      AND IsActive=1 AND RequiresApproval=1 AND IsSystem=1 AND IsEditable=0;
    IF @@ROWCOUNT<>1
        THROW 52905, 'Configuration changed concurrently; stop and re-run read-only preflight.', 1;

    INSERT aud.AuditEvents
        (ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,
         ChangeSummaryJson,RequestId,CorrelationId)
    VALUES (N'KLOP.PLATFORM.CONFIGURATION.DBA',@ActionId,@ResultId,N'CONFIGURATION',
            N'registration.legal_consent_enforcement',@Summary,@ApprovalTicket,@CorrelationId);

    COMMIT TRANSACTION;
    SELECT N'UPDATED' AS Status,@NewValue AS TermsEnforcement,@CorrelationId AS CorrelationId;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
