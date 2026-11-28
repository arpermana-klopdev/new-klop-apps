:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_RUNTIME_PRINCIPAL "UNSET"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Exact EXECUTE-only grant proposal. The existing runtime database principal must be owner-confirmed.
-- Grants no direct table access, creates no principal, and changes no role membership.
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @Principal SYSNAME=N'$(KLOP_RUNTIME_PRINCIPAL)';
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
   OR @Principal IN(N'',N'UNSET')
    THROW 53560, 'DRY RUN - owner approval, runtime principal, and change ticket are required.', 1;
IF LEN(@ApprovalTicket)>100
    THROW 53561, 'Approval ticket must be at most 100 characters.', 1;
IF N'$(KLOP_ENVIRONMENT)'<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53562, 'Refused: this template is restricted to the reviewed Development environment.', 1;
IF N'$(KLOP_EXPECTED_DATABASE)'<>N'KlopPlatformDB' OR DB_NAME()<>N'$(KLOP_EXPECTED_DATABASE)'
    THROW 53563, 'Refused: target database does not match the reviewed Development database.', 1;
IF NOT EXISTS(SELECT 1 FROM sys.database_principals
              WHERE name=@Principal AND type IN('R','S','U','G','E','X'))
    THROW 53564, 'The owner-supplied runtime principal is not an existing database principal.', 1;

DECLARE @Procedures TABLE(SchemaName SYSNAME,ProcedureName SYSNAME,PRIMARY KEY(SchemaName,ProcedureName));
INSERT @Procedures VALUES
    (N'cfg',N'usp_ConfigurationManagement_ListCatalog'),
    (N'cfg',N'usp_ConfigurationManagement_ListRequests'),
    (N'cfg',N'usp_ConfigurationManagement_ListHistory'),
    (N'cfg',N'usp_ConfigurationManagement_CreateDraft'),
    (N'cfg',N'usp_ConfigurationManagement_UpdateDraft'),
    (N'cfg',N'usp_ConfigurationManagement_Transition'),
    (N'cfg',N'usp_ConfigurationManagement_Apply');
IF EXISTS(SELECT 1 FROM @Procedures p
          WHERE OBJECT_ID(QUOTENAME(p.SchemaName)+N'.'+QUOTENAME(p.ProcedureName),N'P') IS NULL)
    THROW 53565, 'A required v1.12 stored procedure is missing; no grant was applied.', 1;
IF @ApplyChanges<>N'APPROVED'
BEGIN
    SELECT N'DRY RUN - NO GRANTS' AS Status,@Principal AS ProposedPrincipal,
           QUOTENAME(SchemaName)+N'.'+QUOTENAME(ProcedureName) AS ProposedExecuteObject
    FROM @Procedures ORDER BY SchemaName,ProcedureName;
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @Grant NVARCHAR(MAX);
    DECLARE procedureCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT SchemaName,ProcedureName FROM @Procedures ORDER BY SchemaName,ProcedureName;
    DECLARE @Schema SYSNAME,@Procedure SYSNAME;
    OPEN procedureCursor;
    FETCH NEXT FROM procedureCursor INTO @Schema,@Procedure;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @Grant=N'GRANT EXECUTE ON OBJECT::'+QUOTENAME(@Schema)+N'.'+QUOTENAME(@Procedure)
                   +N' TO '+QUOTENAME(@Principal)+N';';
        EXEC sys.sp_executesql @Grant;
        FETCH NEXT FROM procedureCursor INTO @Schema,@Procedure;
    END;
    CLOSE procedureCursor;
    DEALLOCATE procedureCursor;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local','procedureCursor')>=0 CLOSE procedureCursor;
    IF CURSOR_STATUS('local','procedureCursor')>-3 DEALLOCATE procedureCursor;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
