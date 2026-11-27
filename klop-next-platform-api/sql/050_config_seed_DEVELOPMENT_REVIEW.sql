-- DRAFT: Development-only proposals for cfg.SystemConfigurations.
-- Review hostnames/origins and existing values; never execute in Production as-is.
-- Does NOT overwrite any existing ConfigurationKey. Key Vault references are names, not secrets.
SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='auth.jwt.issuer')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,RequiresRestart)
 VALUES('auth.jwt.issuer','https://localhost:7041','STRING','Authentication',1,0,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='auth.jwt.audience')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,RequiresRestart)
 VALUES('auth.jwt.audience','klop-platform','STRING','Authentication',1,0,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='web.allowed_origin')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,RequiresRestart)
 VALUES('web.allowed_origin','https://localhost:5173','STRING','Web',1,0,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='smtp.host')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,RequiresRestart)
 VALUES('smtp.host','127.0.0.1','STRING','Email',1,0,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='smtp.port')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,RequiresRestart)
 VALUES('smtp.port','1025','INTEGER','Email',1,0,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='smtp.from')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,RequiresRestart)
 VALUES('smtp.from','klop-dev@localhost','STRING','Email',1,0,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='smtp.require_tls')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,RequiresRestart)
 VALUES('smtp.require_tls','false','BOOLEAN','Email',1,0,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='smtp.username')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,RequiresRestart)
 VALUES('smtp.username',NULL,'STRING','Email',1,0,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='auth.signing_key_ref')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,StorageType,IsSystem,IsEditable,IsSensitive,RequiresRestart)
 VALUES('auth.signing_key_ref',NULL,'STRING','Authentication','KEYVAULT_REFERENCE',1,0,1,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='smtp.password_ref')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,StorageType,IsSystem,IsEditable,IsSensitive,RequiresRestart)
 VALUES('smtp.password_ref',NULL,'STRING','Email','KEYVAULT_REFERENCE',1,0,1,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='auth.email_verification_hours')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresRestart)
 VALUES('auth.email_verification_hours','1','INTEGER','Authentication',1,0,1,24,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH(UPDLOCK,HOLDLOCK) WHERE ConfigurationKey='security.login_lockout_minutes')
 INSERT cfg.SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresRestart)
 VALUES('security.login_lockout_minutes','15','INTEGER','Security',1,0,5,120,1);
 COMMIT TRANSACTION;
END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH;
GO
