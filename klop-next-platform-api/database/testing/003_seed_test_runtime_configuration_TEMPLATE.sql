:on error exit
:setvar KLOP_SEED_APPROVED "NO"
:setvar KLOP_APPROVAL_TICKET "UNSET"

USE [KlopPlatformDB_TEST];
GO
SET NOCOUNT ON;
IF @@SERVERNAME<>N'DEV-PC\SQLEXPRESS' OR DB_NAME()<>N'KlopPlatformDB_TEST'
    THROW 52460,'Refused: configuration seeding is restricted to KlopPlatformDB_TEST.',1;
IF OBJECT_ID(N'cfg.SystemConfigurations',N'U') IS NULL
    THROW 52461,'Refused: v1.1 configuration table is missing.',1;
IF '$(KLOP_SEED_APPROVED)'<>N'APPROVED' OR '$(KLOP_APPROVAL_TICKET)' IN(N'',N'UNSET')
    THROW 52462,'Refused: explicit test-configuration seed approval and ticket are required.',1;
GO

-- Idempotent source seeds insert only missing rows; existing values are never overwritten.
-- Development-only defaults use localhost and an SMTP sink at 127.0.0.1:1025.
:r sql\050_config_seed_DEVELOPMENT_REVIEW.sql
:r database\migrations\v1.4\001_runtime_settings.sql
:r database\validation\001_runtime_settings_readonly.sql
GO
