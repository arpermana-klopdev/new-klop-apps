-- REVIEW ONLY; apply by DBA after verifying runtime principal and effective rights.
-- No table SELECT/INSERT/UPDATE/DELETE grants to the API principal.
IF DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL THROW 52380,'Runtime database role missing',1;
GRANT EXECUTE ON OBJECT::iam.usp_GetLocalLoginCandidate TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_RecordLocalLoginFailure TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_IssueEmailVerificationChallenge TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_CreateAuthSession TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_ValidateSessionAccess TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_RotateRefreshToken TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_RevokeAuthSession TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_GetUserProfile TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::ten.usp_ListMyTenants TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::mst.usp_OrganizationType_GetAll TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::cfg.usp_Configuration_GetByKey TO klop_app_runtime;
GO
