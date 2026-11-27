:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_RUNTIME_USER "KLOP_PLATFORM_API_DEV"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"
:setvar KLOP_REVOKE_OBJECTS "UNSET"
:setvar KLOP_REMOVE_RUNTIME_MEMBERSHIP "NO"

SET NOCOUNT ON;
DECLARE @Environment nvarchar(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @RuntimeUser sysname=N'$(KLOP_RUNTIME_USER)';
DECLARE @ApprovalTicket nvarchar(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges nvarchar(20)=N'$(KLOP_APPLY_CHANGES)';
DECLARE @RollbackList nvarchar(max)=N'$(KLOP_REVOKE_OBJECTS)';
DECLARE @RemoveMembership nvarchar(10)=N'$(KLOP_REMOVE_RUNTIME_MEMBERSHIP)';
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
	THROW 52570,'Refused: Development environment and reviewed server are required.',1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
	THROW 52571,'Refused: rollback is restricted to KlopPlatformDB.',1;
IF @RuntimeUser<>N'KLOP_PLATFORM_API_DEV' OR @RemoveMembership NOT IN(N'NO',N'YES')
	THROW 52572,'Refused: invalid runtime principal or membership rollback flag.',1;

DECLARE @Mapped TABLE(SchemaName sysname NOT NULL,ObjectName sysname NOT NULL PRIMARY KEY(SchemaName,ObjectName));
INSERT @Mapped VALUES
(N'cfg',N'usp_Configuration_GetByKey'),(N'mst',N'usp_TenantType_GetAll'),(N'mst',N'usp_OrganizationType_GetAll'),
(N'iam',N'usp_RegisterLocalUser'),(N'iam',N'usp_ConfirmEmail'),(N'ten',N'usp_CreateTenantWithOwner'),
(N'ten',N'usp_InviteExistingUser'),(N'ten',N'usp_AcceptMembership'),(N'ten',N'usp_RemoveTenantMember'),
(N'iam',N'usp_AssignTenantRole'),(N'iam',N'usp_RevokeTenantRole'),(N'iam',N'usp_GetLocalLoginCandidate'),
(N'iam',N'usp_RecordLocalLoginFailure'),(N'iam',N'usp_IssueEmailVerificationChallenge'),
(N'iam',N'usp_CreateAuthSession'),(N'iam',N'usp_ValidateSessionAccess'),(N'iam',N'usp_RotateRefreshToken'),
(N'iam',N'usp_RevokeAuthSession'),(N'iam',N'usp_GetUserProfile'),(N'ten',N'usp_ListMyTenants');
DECLARE @Revoke TABLE(SchemaName sysname NOT NULL,ObjectName sysname NOT NULL PRIMARY KEY(SchemaName,ObjectName));
IF @RollbackList<>N'UNSET'
BEGIN
	IF EXISTS(SELECT 1 FROM STRING_SPLIT(@RollbackList,N',') WHERE LTRIM(RTRIM(value))=N'mst.usp_TenantType_GetAll')
		THROW 52580,'Refused: preserve the pre-existing mst.usp_TenantType_GetAll grant; do not include it in rollback.',1;
	INSERT @Revoke(SchemaName,ObjectName)
	SELECT DISTINCT PARSENAME(LTRIM(RTRIM(value)),2),PARSENAME(LTRIM(RTRIM(value)),1)
	FROM STRING_SPLIT(@RollbackList,N',');
	IF EXISTS(SELECT 1 FROM STRING_SPLIT(@RollbackList,N',') WHERE PARSENAME(LTRIM(RTRIM(value)),2) IS NULL OR PARSENAME(LTRIM(RTRIM(value)),1) IS NULL)
	   OR EXISTS(SELECT 1 FROM @Revoke r LEFT JOIN @Mapped m ON m.SchemaName=r.SchemaName AND m.ObjectName=r.ObjectName WHERE m.ObjectName IS NULL)
		THROW 52573,'Refused: rollback list contains an invalid or out-of-allowlist object; provide only script-03 additions.',1;
END;
IF @RemoveMembership=N'YES' AND @RollbackList=N'UNSET' AND @ApplyChanges=N'APPROVED'
	SELECT N'No grants selected for rollback; membership removal is separately approval-gated.' AS Note;

SELECT N'ROLLBACK_PLAN' AS Section,r.SchemaName,r.ObjectName,
	CASE WHEN EXISTS(SELECT 1 FROM sys.database_permissions dp JOIN sys.schemas s ON s.name=r.SchemaName
					 JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=r.ObjectName
					 WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
					   AND dp.class=1 AND dp.major_id=p.object_id AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W'))
		 THEN N'EXPLICIT ROLE GRANT TO REVOKE IF APPROVED' ELSE N'NO CURRENT EXPLICIT GRANT' END AS PlannedAction
FROM @Revoke r ORDER BY r.SchemaName,r.ObjectName;
IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
	SELECT N'DRY RUN - NO CHANGES' AS Status,
		N'Rollback list must contain only grants recorded as added by the approved change; pre-existing grants are preserved.' AS Guardrail;
	RETURN;
END;
IF @RollbackList=N'UNSET' AND @RemoveMembership<>N'YES'
	THROW 52574,'Refused: explicitly select the newly added grants and/or approve membership removal.',1;
IF @RemoveMembership=N'YES' AND DATABASE_PRINCIPAL_ID(@RuntimeUser) IS NOT NULL AND EXISTS
(
	SELECT 1 FROM sys.database_role_members rm JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
	WHERE rm.member_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser) AND r.name<>N'klop_app_runtime'
)
	THROW 52576,'Refused: runtime user has another role membership; manual DBA reconciliation required.',1;
BEGIN TRY
	BEGIN TRANSACTION;
	DECLARE @Schema sysname,@Object sysname,@Sql nvarchar(max);
	DECLARE RevokeCursor CURSOR LOCAL FAST_FORWARD FOR SELECT SchemaName,ObjectName FROM @Revoke ORDER BY SchemaName,ObjectName;
	OPEN RevokeCursor;
	FETCH NEXT FROM RevokeCursor INTO @Schema,@Object;
	WHILE @@FETCH_STATUS=0
	BEGIN
		IF EXISTS(SELECT 1 FROM sys.database_permissions dp JOIN sys.schemas s ON s.name=@Schema
				  JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=@Object
				  WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
					AND dp.class=1 AND dp.major_id=p.object_id AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W'))
		BEGIN
			SET @Sql=N'REVOKE EXECUTE ON OBJECT::'+QUOTENAME(@Schema)+N'.'+QUOTENAME(@Object)+N' FROM [klop_app_runtime];';
			EXEC sys.sp_executesql @Sql;
		END;
		FETCH NEXT FROM RevokeCursor INTO @Schema,@Object;
	END;
	CLOSE RevokeCursor;
	DEALLOCATE RevokeCursor;
	IF @RemoveMembership=N'YES' AND EXISTS(SELECT 1 FROM sys.database_role_members
		WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime') AND member_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser))
	BEGIN
		SET @Sql=N'ALTER ROLE [klop_app_runtime] DROP MEMBER '+QUOTENAME(@RuntimeUser)+N';';
		EXEC sys.sp_executesql @Sql;
	END;
	IF EXISTS(SELECT 1 FROM @Revoke r JOIN sys.schemas s ON s.name=r.SchemaName JOIN sys.procedures p ON p.schema_id=s.schema_id AND p.name=r.ObjectName
			  WHERE EXISTS(SELECT 1 FROM sys.database_permissions dp WHERE dp.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
						  AND dp.class=1 AND dp.major_id=p.object_id AND dp.permission_name=N'EXECUTE' AND dp.state IN('G','W')))
		THROW 52578,'Rollback post-check failed: selected grants remain.',1;
	IF @RemoveMembership=N'YES' AND EXISTS(SELECT 1 FROM sys.database_role_members
		WHERE role_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime') AND member_principal_id=DATABASE_PRINCIPAL_ID(@RuntimeUser))
		THROW 52579,'Rollback post-check failed: runtime membership remains.',1;
	COMMIT TRANSACTION;
END TRY
BEGIN CATCH
	IF CURSOR_STATUS('local','RevokeCursor')>=0 CLOSE RevokeCursor;
	IF CURSOR_STATUS('local','RevokeCursor')>-3 DEALLOCATE RevokeCursor;
	IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
	THROW;
END CATCH;
SELECT N'PASS' AS RollbackStatus,
	N'Only explicitly selected role grants and (optionally) the runtime membership were changed. The login, DB user, role, pre-existing grants, and all database data remain.' AS Scope;
GO
