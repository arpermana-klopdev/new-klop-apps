/*
TEMPLATE ONLY -- REVIEW BEFORE APPLYING. DB role is not a login. DB admins bind a dedicated
least-privileged backend principal (never a user-facing account); migration identity separate.
SQL Server ownership chaining needs same database owner for iam/ten/aud/mst schemas; validate.
If other direct grants/role memberships exist, this template does not remove those privileges.
*/
SET NOCOUNT ON;
GO
IF DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL
    CREATE ROLE klop_app_runtime AUTHORIZATION dbo;
GO
-- Grant SP execution individually; do not grant database-wide EXECUTE.
GRANT EXECUTE ON OBJECT::iam.usp_RegisterLocalUser TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_ConfirmEmail TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::ten.usp_CreateTenantWithOwner TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::ten.usp_InviteExistingUser TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::ten.usp_AcceptMembership TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::ten.usp_RemoveTenantMember TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_AssignTenantRole TO klop_app_runtime;
GRANT EXECUTE ON OBJECT::iam.usp_RevokeTenantRole TO klop_app_runtime;
GO
-- Defense-in-depth: audit and tenant tables are not directly writable by the runtime role.
-- Review procedure ownership chaining / signed modules, and effective principal permissions.
DENY INSERT, UPDATE, DELETE ON SCHEMA::iam TO klop_app_runtime;
DENY INSERT, UPDATE, DELETE ON SCHEMA::ten TO klop_app_runtime;
DENY INSERT, UPDATE, DELETE ON SCHEMA::aud TO klop_app_runtime;
DENY INSERT, UPDATE, DELETE ON SCHEMA::mst TO klop_app_runtime;
DENY INSERT, UPDATE, DELETE ON SCHEMA::cfg TO klop_app_runtime;
GO
-- Do NOT add runtime principal to db_owner, db_datawriter, or db_ddladmin.
-- Do NOT GRANT SELECT on credential/token hash tables.
