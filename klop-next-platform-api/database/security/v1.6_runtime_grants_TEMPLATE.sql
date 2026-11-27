-- REVIEW ONLY. DBA must verify schema ownership, runtime identity, and effective permissions before applying.
-- This template has NOT been executed. It grants EXECUTE only; it grants no table DML or DDL rights.
-- It is a proposal for every Stored Procedure called by the current API repository, not a runtime identity setup script.
SET NOCOUNT ON;
IF DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL
	THROW 51630, 'The approved API runtime role is missing.', 1;
IF (SELECT COUNT(DISTINCT principal_id) FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud',N'reg',N'leg'))<>1
	THROW 51631, 'Application schemas do not have one common owner; review ownership chaining first.', 1;
IF NOT EXISTS
(
	SELECT 1 FROM sys.database_role_members rm
	JOIN sys.database_principals r ON r.principal_id=rm.role_principal_id
	WHERE r.name=N'klop_app_runtime'
)
	THROW 51632, 'No approved runtime principal is mapped to klop_app_runtime; do not grant until DBA mapping is verified.', 1;

DECLARE @RequiredProcedures TABLE
(
	SchemaName SYSNAME NOT NULL,
	ProcedureName SYSNAME NOT NULL,
	PRIMARY KEY(SchemaName,ProcedureName)
);
INSERT @RequiredProcedures(SchemaName,ProcedureName) VALUES
	(N'iam',N'usp_RegisterLocalUser'),
	(N'iam',N'usp_ConfirmEmail'),
	(N'iam',N'usp_IssueEmailVerificationChallenge'),
	(N'iam',N'usp_GetLocalLoginCandidate'),
	(N'iam',N'usp_RecordLocalLoginFailure'),
	(N'iam',N'usp_CreateAuthSession'),
	(N'iam',N'usp_ValidateSessionAccess'),
	(N'iam',N'usp_RotateRefreshToken'),
	(N'iam',N'usp_RevokeAuthSession'),
	(N'iam',N'usp_GetUserProfile'),
	(N'iam',N'usp_AssignTenantRole'),
	(N'iam',N'usp_RevokeTenantRole'),
	(N'ten',N'usp_ListMyTenants'),
	(N'ten',N'usp_CreateTenantWithOwner'),
	(N'ten',N'usp_InviteExistingUser'),
	(N'ten',N'usp_AcceptMembership'),
	(N'ten',N'usp_RemoveTenantMember'),
	(N'mst',N'usp_OrganizationType_GetAll'),
	(N'mst',N'usp_TenantType_GetAll'),
	(N'cfg',N'usp_Configuration_GetByKey'),
	(N'reg',N'usp_GetMyApplication'),
	(N'reg',N'usp_GetApplicationForOwner'),
	(N'reg',N'usp_SavePersonalDraft'),
	(N'reg',N'usp_SaveOrganizationDraft'),
	(N'reg',N'usp_GetOrganizationRequirements'),
	(N'reg',N'usp_SubmitOnboarding'),
	(N'leg',N'usp_GetCurrentTerms'),
	(N'leg',N'usp_GetPublicTermsFile');

IF EXISTS
(
	SELECT 1 FROM @RequiredProcedures r
	WHERE OBJECT_ID(QUOTENAME(r.SchemaName)+N'.'+QUOTENAME(r.ProcedureName),N'P') IS NULL
)
	THROW 51633, 'A required API Stored Procedure is missing; no grants were applied.', 1;

GRANT EXECUTE ON OBJECT::iam.usp_RegisterLocalUser TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_ConfirmEmail TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_IssueEmailVerificationChallenge TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_GetLocalLoginCandidate TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_RecordLocalLoginFailure TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_CreateAuthSession TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_ValidateSessionAccess TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_RotateRefreshToken TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_RevokeAuthSession TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_GetUserProfile TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_AssignTenantRole TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_RevokeTenantRole TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::ten.usp_ListMyTenants TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::ten.usp_CreateTenantWithOwner TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::ten.usp_InviteExistingUser TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::ten.usp_AcceptMembership TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::ten.usp_RemoveTenantMember TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::mst.usp_OrganizationType_GetAll TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::mst.usp_TenantType_GetAll TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::cfg.usp_Configuration_GetByKey TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::reg.usp_GetMyApplication TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::reg.usp_GetApplicationForOwner TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::reg.usp_SavePersonalDraft TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::reg.usp_SaveOrganizationDraft TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::reg.usp_GetOrganizationRequirements TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::reg.usp_SubmitOnboarding TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_GetCurrentTerms TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::leg.usp_GetPublicTermsFile TO klop_app_runtime;
GO
