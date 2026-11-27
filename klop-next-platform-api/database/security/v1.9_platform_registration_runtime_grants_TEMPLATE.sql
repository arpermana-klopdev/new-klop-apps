:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- REVIEW ONLY. Grants EXECUTE only on the four v1.9 registration read procedures.
-- Does not create principals, assign platform roles, or grant table/schema access.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Environment NVARCHAR(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase SYSNAME=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @ApprovalTicket NVARCHAR(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges NVARCHAR(20)=N'$(KLOP_APPLY_CHANGES)';
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 52940, 'Refused: Development environment and reviewed server are required.', 1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
    THROW 52941, 'Refused: this approval template is restricted to KlopPlatformDB.', 1;
IF DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL
    THROW 52942, 'The approved API runtime role is missing.', 1;
IF (SELECT COUNT(DISTINCT principal_id) FROM sys.schemas
    WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg'))<>1
    THROW 52943, 'Application schemas do not have one common owner; review ownership chaining first.', 1;
IF NOT EXISTS
(
    SELECT 1 FROM sys.database_role_members rm
    JOIN sys.database_principals role ON role.principal_id=rm.role_principal_id
    WHERE role.name=N'klop_app_runtime'
)
    THROW 52944, 'No approved runtime principal is mapped to klop_app_runtime.', 1;
IF NOT EXISTS
(
    SELECT 1 FROM sys.database_permissions permission
    WHERE permission.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
      AND permission.class=1 AND permission.permission_name=N'EXECUTE'
      AND permission.state IN('G','W')
      AND permission.major_id=OBJECT_ID(N'iam.usp_ValidatePlatformPermission',N'P')
)
    THROW 52945, 'Apply the approved v1.7 runtime permission-procedure grant before registration grants.', 1;

DECLARE @RequiredProcedures TABLE
(
    SchemaName SYSNAME NOT NULL,
    ProcedureName SYSNAME NOT NULL,
    PRIMARY KEY(SchemaName,ProcedureName)
);
INSERT @RequiredProcedures(SchemaName,ProcedureName) VALUES
    (N'reg',N'usp_GetPlatformRegistrationSummary'),
    (N'reg',N'usp_ListPlatformRegistrations'),
    (N'reg',N'usp_GetPlatformRegistration'),
    (N'reg',N'usp_GetPlatformRegistrationTimeline');
IF EXISTS
(
    SELECT 1 FROM @RequiredProcedures required
    WHERE OBJECT_ID(QUOTENAME(required.SchemaName)+N'.'+QUOTENAME(required.ProcedureName),N'P') IS NULL
)
    THROW 52946, 'A required v1.9 registration procedure is missing; no grants were applied.', 1;

SELECT N'GRANT_PLAN' AS Section,required.SchemaName,required.ProcedureName,
       CASE WHEN permission.major_id IS NULL THEN N'WOULD ADD OBJECT-LEVEL EXECUTE'
            ELSE N'PRESERVE EXISTING EXPLICIT GRANT' END AS PlannedAction
FROM @RequiredProcedures required
JOIN sys.schemas schemaInfo ON schemaInfo.name=required.SchemaName
JOIN sys.procedures procedureInfo
    ON procedureInfo.schema_id=schemaInfo.schema_id AND procedureInfo.name=required.ProcedureName
LEFT JOIN sys.database_permissions permission
    ON permission.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
   AND permission.class=1 AND permission.major_id=procedureInfo.object_id
   AND permission.permission_name=N'EXECUTE' AND permission.state IN('G','W')
ORDER BY required.SchemaName,required.ProcedureName;

IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
    SELECT N'DRY RUN - NO CHANGES' AS Status,
           N'Explicit DBA approval and ticket are required before applying object-level EXECUTE grants.' AS NextStep;
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @Schema SYSNAME,@Procedure SYSNAME,@Sql NVARCHAR(MAX);
    DECLARE GrantCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT SchemaName,ProcedureName FROM @RequiredProcedures ORDER BY SchemaName,ProcedureName;
    OPEN GrantCursor;
    FETCH NEXT FROM GrantCursor INTO @Schema,@Procedure;
    WHILE @@FETCH_STATUS=0
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1
            FROM sys.database_permissions permission
            JOIN sys.schemas schemaInfo ON schemaInfo.name=@Schema
            JOIN sys.procedures procedureInfo
                ON procedureInfo.schema_id=schemaInfo.schema_id AND procedureInfo.name=@Procedure
            WHERE permission.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
              AND permission.class=1 AND permission.major_id=procedureInfo.object_id
              AND permission.permission_name=N'EXECUTE' AND permission.state IN('G','W')
        )
        BEGIN
            SET @Sql=N'GRANT EXECUTE ON OBJECT::'+QUOTENAME(@Schema)+N'.'+QUOTENAME(@Procedure)+
                     N' TO [klop_app_runtime];';
            EXEC sys.sp_executesql @Sql;
        END;
        FETCH NEXT FROM GrantCursor INTO @Schema,@Procedure;
    END;
    CLOSE GrantCursor;
    DEALLOCATE GrantCursor;

    IF EXISTS
    (
        SELECT 1 FROM @RequiredProcedures required
        JOIN sys.schemas schemaInfo ON schemaInfo.name=required.SchemaName
        JOIN sys.procedures procedureInfo
            ON procedureInfo.schema_id=schemaInfo.schema_id AND procedureInfo.name=required.ProcedureName
        WHERE NOT EXISTS
        (
            SELECT 1 FROM sys.database_permissions permission
            WHERE permission.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
              AND permission.class=1 AND permission.major_id=procedureInfo.object_id
              AND permission.permission_name=N'EXECUTE' AND permission.state IN('G','W')
        )
    )
        THROW 52947, 'Post-check failed: a v1.9 procedure EXECUTE grant is missing.', 1;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local','GrantCursor')>=0 CLOSE GrantCursor;
    IF CURSOR_STATUS('local','GrantCursor')>-3 DEALLOCATE GrantCursor;
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT N'PASS' AS GrantStatus,COUNT(*) AS ExplicitV19RegistrationExecuteGrants
FROM sys.database_permissions permission
JOIN @RequiredProcedures required
    ON permission.major_id=OBJECT_ID(QUOTENAME(required.SchemaName)+N'.'+QUOTENAME(required.ProcedureName),N'P')
WHERE permission.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
  AND permission.class=1 AND permission.permission_name=N'EXECUTE' AND permission.state IN('G','W');
GO
