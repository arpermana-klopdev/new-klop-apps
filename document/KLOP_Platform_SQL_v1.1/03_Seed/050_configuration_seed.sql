SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='auth.access_token_minutes') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'auth.access_token_minutes',N'15',N'INTEGER',N'Authentication',1,0,5,60,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='auth.refresh_token_days') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'auth.refresh_token_days',N'7',N'INTEGER',N'Authentication',1,0,1,30,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='security.max_login_attempts') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'security.max_login_attempts',N'5',N'INTEGER',N'Security',1,0,3,10,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='security.password.min_length') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'security.password.min_length',N'12',N'INTEGER',N'Security',1,0,12,128,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='registration.personal.enabled') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'registration.personal.enabled',N'true',N'BOOLEAN',N'Registration',0,1,NULL,NULL,0);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='registration.organization.enabled') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'registration.organization.enabled',N'true',N'BOOLEAN',N'Registration',0,1,NULL,NULL,0);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='registration.email_verification_required') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'registration.email_verification_required',N'true',N'BOOLEAN',N'Registration',1,0,NULL,NULL,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='tenant.personal.max_members') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'tenant.personal.max_members',N'1',N'INTEGER',N'Tenant',1,0,1,1,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='features.multi_workspace_enabled') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'features.multi_workspace_enabled',N'false',N'BOOLEAN',N'Features',1,0,NULL,NULL,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='audit.retention_days') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'audit.retention_days',N'365',N'INTEGER',N'Audit',1,0,30,3650,1);
 IF NOT EXISTS (SELECT 1 FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK) WHERE ConfigurationKey='upload.max_file_size_mb') INSERT cfg.SystemConfigurations (ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,MinNumericValue,MaxNumericValue,RequiresApproval) VALUES (N'upload.max_file_size_mb',N'20',N'INTEGER',N'Document',0,1,1,100,0);
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
