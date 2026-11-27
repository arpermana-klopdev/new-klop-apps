:on error exit
:setvar KLOP_SCHEMA_DEPLOY_APPROVED "NO"
:setvar KLOP_APPROVAL_TICKET "UNSET"

USE [KlopPlatformDB_TEST];
GO
SET NOCOUNT ON;
IF @@SERVERNAME<>N'DEV-PC\SQLEXPRESS' OR DB_NAME()<>N'KlopPlatformDB_TEST'
    THROW 52450,'Refused: schema deployment is allowed only on DEV-PC\SQLEXPRESS / KlopPlatformDB_TEST.',1;
IF '$(KLOP_SCHEMA_DEPLOY_APPROVED)'<>N'APPROVED' OR '$(KLOP_APPROVAL_TICKET)' IN(N'',N'UNSET')
    THROW 52451,'Refused: explicit schema deployment approval and ticket are required.',1;
IF EXISTS(SELECT 1 FROM sys.schemas WHERE name IN(N'cfg',N'iam',N'mst',N'ten',N'aud'))
    THROW 52452,'Refused: application schemas already exist; do not replay this fresh-database bundle.',1;
GO

-- Run sqlcmd from klop-next-platform-api so these paths resolve to the immutable/versioned sources.
:r ..\document\KLOP_Platform_SQL_v1.1\00_Foundation\001_schemas.sql
:r ..\document\KLOP_Platform_SQL_v1.1\01_Tables\010_master_tables.sql
:r ..\document\KLOP_Platform_SQL_v1.1\01_Tables\020_configuration.sql
:r ..\document\KLOP_Platform_SQL_v1.1\02_Constraints\030_foreign_keys_indexes.sql
:r ..\document\KLOP_Platform_SQL_v1.1\03_Seed\040_reference_seed.sql
:r ..\document\KLOP_Platform_SQL_v1.1\03_Seed\050_configuration_seed.sql
:r ..\document\KLOP_Platform_SQL_v1.1\04_StoredProcedures\060_read_procedures.sql

:r ..\document\KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT\sql\00_Preflight\000_v1_1_prerequisites.sql
:r ..\document\KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT\sql\01_Tables\010_new_masters.sql
:r ..\document\KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT\sql\01_Tables\020_iam_tenant.sql
:r ..\document\KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT\sql\01_Tables\030_audit_events.sql
:r ..\document\KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT\sql\02_Constraints\040_foreign_keys_indexes_checks.sql
:r ..\document\KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT\sql\03_Seed\050_new_master_seed.sql
:r ..\document\KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT\sql\04_Validation\090_smoke_checks.sql

:r ..\document\KLOP_DB_FOUNDATION_1_2_1_DRAFT\sql\00_Preflight\000_require_v1_2.sql
:r ..\document\KLOP_DB_FOUNDATION_1_2_1_DRAFT\sql\01_StoredProcedures\100_registration.sql
:r ..\document\KLOP_DB_FOUNDATION_1_2_1_DRAFT\sql\01_StoredProcedures\110_tenant_create.sql
:r ..\document\KLOP_DB_FOUNDATION_1_2_1_DRAFT\sql\01_StoredProcedures\120_membership.sql
:r ..\document\KLOP_DB_FOUNDATION_1_2_1_DRAFT\sql\01_StoredProcedures\130_roles.sql
:r ..\document\KLOP_DB_FOUNDATION_1_2_1_DRAFT\sql\03_Validation\300_structure_checks.sql

:r sql\050_config_seed_DEVELOPMENT_REVIEW.sql
:r database\migrations\v1.4\001_runtime_settings.sql
:r database\migrations\v1.5\001_auth_session_procedures_STANDALONE.sql

PRINT 'Schema bundle finished. Run database/testing/006_validate_test_database_READONLY.sql separately.';
GO
