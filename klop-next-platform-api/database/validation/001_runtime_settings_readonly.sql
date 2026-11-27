-- Read-only validation for the additive backend v1.4 runtime settings.
SELECT expected.ConfigurationKey,
       CASE WHEN actual.ConfigurationId IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS Status,
       actual.ValueType,
       actual.StorageType
FROM (VALUES
    ('database.command_timeout_seconds'),
    ('security.auth_requests_per_minute')
) AS expected(ConfigurationKey)
LEFT JOIN cfg.SystemConfigurations AS actual
    ON actual.ConfigurationKey = expected.ConfigurationKey
   AND actual.IsActive = 1
ORDER BY expected.ConfigurationKey;
