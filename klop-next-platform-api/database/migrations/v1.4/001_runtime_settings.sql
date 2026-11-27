-- KLOP PLATFORM BACKEND 1.4 DRAFT. Additive SQL configuration only.
-- DBA review and Development-only execution are required; never run automatically.
SET XACT_ABORT ON;
SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS
    (
        SELECT 1
        FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK)
        WHERE ConfigurationKey = 'database.command_timeout_seconds'
    )
    BEGIN
        INSERT cfg.SystemConfigurations
            (ConfigurationKey, ConfigurationValue, ValueType, Category,
             IsSystem, IsEditable, MinNumericValue, MaxNumericValue, RequiresApproval)
        VALUES
            ('database.command_timeout_seconds', N'30', 'INTEGER', 'Database',
             1, 0, 1, 120, 1);
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM cfg.SystemConfigurations WITH (UPDLOCK, HOLDLOCK)
        WHERE ConfigurationKey = 'security.auth_requests_per_minute'
    )
    BEGIN
        INSERT cfg.SystemConfigurations
            (ConfigurationKey, ConfigurationValue, ValueType, Category,
             IsSystem, IsEditable, MinNumericValue, MaxNumericValue, RequiresApproval)
        VALUES
            ('security.auth_requests_per_minute', N'8', 'INTEGER', 'Security',
             1, 0, 1, 120, 1);
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
