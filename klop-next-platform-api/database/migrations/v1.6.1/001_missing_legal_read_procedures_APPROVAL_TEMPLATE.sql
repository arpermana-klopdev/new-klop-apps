:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"
:setvar KLOP_APPROVAL_TICKET "UNSET"
:setvar KLOP_APPLY_CHANGES "NO"

-- KLOP v1.6.1 targeted reconciliation only. DBA review and explicit approval required.
-- This script never alters an existing procedure and does not create schemas, tables,
-- triggers, configuration, users, logins, grants, or role memberships.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Environment nvarchar(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
DECLARE @ApprovalTicket nvarchar(200)=N'$(KLOP_APPROVAL_TICKET)';
DECLARE @ApplyChanges nvarchar(20)=N'$(KLOP_APPLY_CHANGES)';

IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
	THROW 52700,'Refused: targeted reconciliation is restricted to Development DEV-PC\SQLEXPRESS.',1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
	THROW 52701,'Refused: targeted reconciliation is restricted to KlopPlatformDB.',1;

DECLARE @RequiredProcedures TABLE(ProcedureName sysname NOT NULL PRIMARY KEY);
INSERT @RequiredProcedures(ProcedureName) VALUES
	(N'usp_GetCurrentTerms'),
	(N'usp_GetPublicTermsFile');

IF EXISTS
(
	SELECT 1 FROM @RequiredProcedures r
	JOIN sys.objects o ON o.schema_id=SCHEMA_ID(N'leg') AND o.name=r.ProcedureName
	WHERE o.type<>N'P'
)
	THROW 52702,'Refused: a target name exists but is not a stored procedure; DBA reconciliation is required.',1;

DECLARE @MissingProcedures TABLE(ProcedureName sysname NOT NULL PRIMARY KEY);
INSERT @MissingProcedures(ProcedureName)
SELECT r.ProcedureName
FROM @RequiredProcedures r
WHERE OBJECT_ID(N'leg.'+QUOTENAME(r.ProcedureName),N'P') IS NULL;

IF NOT EXISTS(SELECT 1 FROM @MissingProcedures)
BEGIN
	SELECT N'NO CHANGES - BOTH PROCEDURES ALREADY EXIST' AS Status,
		N'Existing procedures were preserved; no DDL was executed.' AS Detail;
	RETURN;
END;

IF @ApplyChanges<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
	SELECT N'DRY RUN - NO CHANGES' AS Status,
		N'Only the following absent procedures would be created after approved DBA review.' AS Detail,
		ProcedureName
	FROM @MissingProcedures ORDER BY ProcedureName;
	RETURN;
END;

IF SCHEMA_ID(N'leg') IS NULL OR SCHEMA_ID(N'mst') IS NULL
	THROW 52703,'Refused: expected pre-existing legal and master-data schemas are missing.',1;
IF EXISTS
(
	SELECT 1 FROM sys.schemas
	WHERE name IN(N'leg',N'mst') AND USER_NAME(principal_id)<>N'dbo'
)
	THROW 52704,'Refused: expected legal/master schemas do not have the reviewed dbo owner.',1;

DECLARE @RequiredColumns TABLE
(
	SchemaName sysname NOT NULL,
	TableName sysname NOT NULL,
	ColumnName sysname NOT NULL,
	PRIMARY KEY(SchemaName,TableName,ColumnName)
);
INSERT @RequiredColumns(SchemaName,TableName,ColumnName) VALUES
	(N'mst',N'TenantTypes',N'TenantTypeId'),
	(N'mst',N'TenantTypes',N'Code'),
	(N'mst',N'TenantTypes',N'IsActive'),
	(N'leg',N'LegalDocuments',N'LegalDocumentId'),
	(N'leg',N'LegalDocuments',N'DocumentTypeCode'),
	(N'leg',N'LegalDocumentVersions',N'DocumentVersionId'),
	(N'leg',N'LegalDocumentVersions',N'LegalDocumentId'),
	(N'leg',N'LegalDocumentVersions',N'Title'),
	(N'leg',N'LegalDocumentVersions',N'VersionIdentifier'),
	(N'leg',N'LegalDocumentVersions',N'EffectiveAtUtc'),
	(N'leg',N'LegalDocumentVersions',N'PublicationStatus'),
	(N'leg',N'LegalDocumentVersions',N'PublishedAtUtc'),
	(N'leg',N'LegalDocumentVersions',N'CreatedAtUtc'),
	(N'leg',N'LegalDocumentVersions',N'StorageReference'),
	(N'leg',N'LegalDocumentVersions',N'ContentHash'),
	(N'leg',N'LegalDocumentVersions',N'MimeType'),
	(N'leg',N'LegalDocumentVersions',N'FileSizeBytes'),
	(N'leg',N'LegalDocumentVersionScopes',N'DocumentVersionId'),
	(N'leg',N'LegalDocumentVersionScopes',N'TenantTypeId');

IF EXISTS
(
	SELECT 1 FROM @RequiredColumns r
	LEFT JOIN sys.schemas s ON s.name=r.SchemaName
	LEFT JOIN sys.tables t ON t.schema_id=s.schema_id AND t.name=r.TableName
	LEFT JOIN sys.columns c ON c.object_id=t.object_id AND c.name=r.ColumnName
	WHERE c.column_id IS NULL
)
	THROW 52705,'Refused: an expected v1.6 procedure dependency or column is missing.',1;

BEGIN TRY
	BEGIN TRANSACTION;

	IF OBJECT_ID(N'leg.usp_GetCurrentTerms',N'P') IS NULL
	BEGIN
		DECLARE @GetCurrentTermsSql nvarchar(max)=N'CREATE PROCEDURE leg.usp_GetCurrentTerms
	@RegistrationTypeCode VARCHAR(50)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(),@TenantTypeId BIGINT;
	SELECT @TenantTypeId=TenantTypeId FROM mst.TenantTypes
	WHERE Code=UPPER(LTRIM(RTRIM(@RegistrationTypeCode))) AND IsActive=1;
	IF @TenantTypeId IS NULL THROW 52114, ''Registration type is unavailable.'', 1;

	SELECT TOP (1) v.DocumentVersionId,d.DocumentTypeCode,v.Title,v.VersionIdentifier,
		   ty.Code AS RegistrationTypeCode,v.EffectiveAtUtc,v.PublicationStatus,
		   v.StorageReference,v.ContentHash,v.MimeType,v.FileSizeBytes
	FROM leg.LegalDocumentVersions v
	JOIN leg.LegalDocuments d ON d.LegalDocumentId=v.LegalDocumentId
	JOIN leg.LegalDocumentVersionScopes scope ON scope.DocumentVersionId=v.DocumentVersionId
	JOIN mst.TenantTypes ty ON ty.TenantTypeId=scope.TenantTypeId
	WHERE scope.TenantTypeId=@TenantTypeId AND d.DocumentTypeCode=''TERMS_AND_CONDITIONS''
	  AND v.PublicationStatus=''PUBLISHED'' AND v.EffectiveAtUtc<=@Now
	ORDER BY v.EffectiveAtUtc DESC,v.PublishedAtUtc DESC,v.CreatedAtUtc DESC;
END;';
		EXEC sys.sp_executesql @GetCurrentTermsSql;
	END;

	IF OBJECT_ID(N'leg.usp_GetPublicTermsFile',N'P') IS NULL
	BEGIN
		DECLARE @GetPublicTermsFileSql nvarchar(max)=N'CREATE PROCEDURE leg.usp_GetPublicTermsFile
	@DocumentVersionId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Now DATETIME2(3)=SYSUTCDATETIME();
	SELECT TOP (1) v.DocumentVersionId,d.DocumentTypeCode,v.Title,v.VersionIdentifier,
		   ty.Code AS RegistrationTypeCode,v.EffectiveAtUtc,v.PublicationStatus,
		   v.StorageReference,v.ContentHash,v.MimeType,v.FileSizeBytes
	FROM leg.LegalDocumentVersions v
	JOIN leg.LegalDocuments d ON d.LegalDocumentId=v.LegalDocumentId
	JOIN leg.LegalDocumentVersionScopes scope ON scope.DocumentVersionId=v.DocumentVersionId
	JOIN mst.TenantTypes ty ON ty.TenantTypeId=scope.TenantTypeId
	WHERE v.DocumentVersionId=@DocumentVersionId AND d.DocumentTypeCode=''TERMS_AND_CONDITIONS''
	  AND v.PublicationStatus=''PUBLISHED'' AND v.EffectiveAtUtc<=@Now
	ORDER BY ty.Code;
END;';
		EXEC sys.sp_executesql @GetPublicTermsFileSql;
	END;

	IF EXISTS
	(
		SELECT 1 FROM @RequiredProcedures r
		WHERE OBJECT_ID(N'leg.'+QUOTENAME(r.ProcedureName),N'P') IS NULL
	)
		THROW 52706,'Post-check failed: a required legal Stored Procedure is still missing.',1;

	COMMIT TRANSACTION;
END TRY
BEGIN CATCH
	IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
	THROW;
END CATCH;

SELECT N'PASS' AS ReconciliationStatus,
	N'Only previously absent legal read procedures were created; existing objects were preserved.' AS Scope;
GO
