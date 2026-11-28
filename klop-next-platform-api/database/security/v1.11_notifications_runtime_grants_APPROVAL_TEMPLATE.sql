:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- Exact object-level proposal only. No schema-wide, table, role-membership, or user grants.
SET NOCOUNT ON;
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
    THROW 53160, 'DRY RUN - explicit owner/DBA approval and a change ticket are required.', 1;
IF N'$(KLOP_ENVIRONMENT)'<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 53161, 'Refused: this template is restricted to the reviewed Development environment.', 1;
IF N'$(KLOP_EXPECTED_DATABASE)'<>N'KlopPlatformDB' OR DB_NAME()<>N'$(KLOP_EXPECTED_DATABASE)'
    THROW 53162, 'Refused: target database does not match the reviewed Development database.', 1;
IF DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL
    THROW 53163, 'The pre-existing runtime database role is absent; no principal is created.', 1;

DECLARE @Procedures TABLE(SchemaName SYSNAME,ProcedureName SYSNAME,PRIMARY KEY(SchemaName,ProcedureName));
INSERT @Procedures(SchemaName,ProcedureName) VALUES
('ntf','usp_ListTemplates'),
('ntf','usp_GetTemplate'),
('ntf','usp_GetTemplateVersionForPreview'),
('ntf','usp_ListChannels'),
('ntf','usp_ListDeliveryHistory'),
('ntf','usp_CreateTemplateDraft'),
('ntf','usp_UpdateTemplateDraft'),
('ntf','usp_TransitionTemplateVersion'),
('ntf','usp_GetActiveVerificationTemplate'),
('ntf','usp_RecordDeliveryAttempt');
IF EXISTS(SELECT 1 FROM @Procedures p WHERE OBJECT_ID(QUOTENAME(p.SchemaName)+N'.'+QUOTENAME(p.ProcedureName),N'P') IS NULL)
    THROW 53164, 'One or more exact notification procedures are missing; no grants are applied.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @SchemaName SYSNAME,@ProcedureName SYSNAME,@Statement NVARCHAR(MAX);
    DECLARE procedure_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT SchemaName,ProcedureName FROM @Procedures ORDER BY SchemaName,ProcedureName;
    OPEN procedure_cursor;
    FETCH NEXT FROM procedure_cursor INTO @SchemaName,@ProcedureName;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @Statement=N'GRANT EXECUTE ON OBJECT::'+QUOTENAME(@SchemaName)+N'.'+
            QUOTENAME(@ProcedureName)+N' TO [klop_app_runtime];';
        EXEC sys.sp_executesql @Statement;
        FETCH NEXT FROM procedure_cursor INTO @SchemaName,@ProcedureName;
    END;
    CLOSE procedure_cursor;
    DEALLOCATE procedure_cursor;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local','procedure_cursor')>=0 CLOSE procedure_cursor;
    IF CURSOR_STATUS('local','procedure_cursor')>-3 DEALLOCATE procedure_cursor;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
