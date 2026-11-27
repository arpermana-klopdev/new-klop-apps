-- REVIEW ONLY. This template has NOT been executed.
-- It grants EXECUTE on legal-administration Stored Procedures only; no table DML, DDL, login,
-- role, or database-principal changes are included. Apply only after the v1.7 migration is approved.
SET NOCOUNT ON;

IF DB_NAME() <> N'KlopPlatformDB'
	THROW 51639, 'This approval template is restricted to KlopPlatformDB Development.', 1;
IF DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL
	THROW 51630, 'The approved API runtime role is missing.', 1;
IF (SELECT COUNT(DISTINCT principal_id) FROM sys.schemas
	WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg'))<>1
	THROW 51631, 'Application schemas do not have one common owner; review ownership chaining first.', 1;
IF NOT EXISTS
(
	SELECT 1 FROM sys.database_role_members rm
	JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
	WHERE r.name=N'klop_app_runtime'
)
	THROW 51632, 'No approved runtime principal is mapped to klop_app_runtime; verify the DBA mapping first.', 1;

DECLARE @RequiredProcedures TABLE
(
	SchemaName SYSNAME NOT NULL,
	ProcedureName SYSNAME NOT NULL,
	PRIMARY KEY(SchemaName,ProcedureName)
);
INSERT @RequiredProcedures(SchemaName,ProcedureName) VALUES
	(N'iam',N'usp_ValidatePlatformPermission'),
	(N'iam',N'usp_GetPlatformPermissions'),
	(N'leg',N'usp_ListLegalDocuments'),
	(N'leg',N'usp_GetLegalDocument'),
	(N'leg',N'usp_GetLegalDocumentVersion'),
	(N'leg',N'usp_GetLegalDocumentPreview'),
	(N'leg',N'usp_CreateLegalDocumentDraft'),
	(N'leg',N'usp_UpdateLegalDocumentDraft'),
	(N'leg',N'usp_SubmitLegalDocument'),
	(N'leg',N'usp_DecideLegalDocumentApproval'),
	(N'leg',N'usp_PublishLegalDocument'),
	(N'leg',N'usp_ArchiveLegalDocument');

IF EXISTS
(
	SELECT 1 FROM @RequiredProcedures r
	WHERE OBJECT_ID(QUOTENAME(r.SchemaName)+N'.'+QUOTENAME(r.ProcedureName),N'P') IS NULL
)
	THROW 51633, 'A required v1.7 Stored Procedure is missing; no grants were applied.', 1;

GRANT EXECUTE ON OBJECT::iam.usp_ValidatePlatformPermission TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_GetPlatformPermissions TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_ListLegalDocuments TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_GetLegalDocument TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_GetLegalDocumentVersion TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_GetLegalDocumentPreview TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_CreateLegalDocumentDraft TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_UpdateLegalDocumentDraft TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_SubmitLegalDocument TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_DecideLegalDocumentApproval TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_PublishLegalDocument TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_ArchiveLegalDocument TO klop_app_runtime;
GO
