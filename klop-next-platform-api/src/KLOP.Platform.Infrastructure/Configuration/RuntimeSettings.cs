using System.Data;
using System.Globalization;
using Dapper;
using KLOP.Platform.Application;

namespace KLOP.Platform.Infrastructure;

public sealed record RuntimeSettings(
    string JwtIssuer,
    string JwtAudience,
    string AllowedOrigin,
    int AccessMinutes,
    int RefreshDays,
    int MaxLoginAttempts,
    int MinPasswordLength,
    int EmailVerificationHours,
    int CommandTimeoutSeconds,
    int AuthRequestsPerMinute,
    string SmtpHost,
    int SmtpPort,
    string SmtpFrom,
    bool SmtpRequireTls,
    string? SmtpUsername,
    string? SigningKeyReference,
    string? SmtpPasswordReference,
    bool LegalConsentEnforcement = true,
    bool DevelopmentTermsBypassEnabled = false,
    bool PersonalRegistrationEnabled = true,
    bool OrganizationRegistrationEnabled = true,
    bool NotificationTemplatesEnabled = false) : IPlatformRuntimeSettings
{
    private sealed class ConfigRow
    {
        public string? ConfigurationValue { get; set; }
        public string ValueType { get; set; } = "";
        public string StorageType { get; set; } = "";
    }

    public static async Task<RuntimeSettings> Load(
        SqlConnectionFactory factory,
        bool developmentTermsBypassEnabled = false,
        CancellationToken cancellationToken = default)
    {
        using var connection = factory.Open();

        async Task<ConfigRow?> Read(string key)
        {
            var parameters = new DynamicParameters();
            parameters.Add("ConfigurationKey", key, DbType.AnsiString, size: 150);
            return await connection.QuerySingleOrDefaultAsync<ConfigRow>(
                new CommandDefinition("cfg.usp_Configuration_GetByKey",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 20,
                    cancellationToken: cancellationToken));
        }

        async Task<string> Required(string key, string expectedType)
        {
            var row = await Read(key);
            if (row is null || row.StorageType != "PLAIN" || row.ValueType != expectedType ||
                string.IsNullOrWhiteSpace(row.ConfigurationValue))
                throw new InvalidOperationException($"Required SQL configuration '{key}' is absent or invalid.");
            return row.ConfigurationValue.Trim();
        }

        async Task<string?> Optional(string key, string expectedType)
        {
            var row = await Read(key);
            if (row is null)
                return null;
            if (row.StorageType != "PLAIN" || row.ValueType != expectedType)
                throw new InvalidOperationException($"Invalid type for SQL configuration '{key}'.");
            return string.IsNullOrWhiteSpace(row.ConfigurationValue) ? null : row.ConfigurationValue.Trim();
        }

        async Task<string?> VaultReference(string key)
        {
            var row = await Read(key);
            if (row is null)
                return null;
            if (row.StorageType != "KEYVAULT_REFERENCE" || row.ValueType != "STRING")
                throw new InvalidOperationException($"SQL configuration '{key}' must be a string Key Vault reference.");
            return string.IsNullOrWhiteSpace(row.ConfigurationValue) ? null : row.ConfigurationValue.Trim();
        }

        async Task<int> Bounded(string key, int minimum, int maximum)
        {
            var raw = await Required(key, "INTEGER");
            if (!int.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out var value) ||
                value < minimum || value > maximum)
                throw new InvalidOperationException($"SQL configuration '{key}' is outside its allowed range.");
            return value;
        }

        async Task<bool> Flag(string key)
        {
            var raw = await Required(key, "BOOLEAN");
            if (!bool.TryParse(raw, out var value))
                throw new InvalidOperationException($"SQL configuration '{key}' must be a boolean.");
            return value;
        }

        async Task<bool> OptionalFlag(string key, bool fallback)
        {
            var row = await Read(key);
            if (row is null)
                return fallback;
            if (row.StorageType != "PLAIN" || row.ValueType != "BOOLEAN" ||
                !bool.TryParse(row.ConfigurationValue, out var value))
                throw new InvalidOperationException($"SQL configuration '{key}' must be a boolean.");
            return value;
        }

        var issuer = await Required("auth.jwt.issuer", "STRING");
        var audience = await Required("auth.jwt.audience", "STRING");
        var allowedOrigin = await Required("web.allowed_origin", "STRING");
        if (!Uri.TryCreate(issuer, UriKind.Absolute, out var issuerUri) ||
            issuerUri.Scheme != Uri.UriSchemeHttps)
            throw new InvalidOperationException("SQL configuration 'auth.jwt.issuer' must be an HTTPS URI.");
        if (!Uri.TryCreate(allowedOrigin, UriKind.Absolute, out var originUri) ||
            originUri.Scheme != Uri.UriSchemeHttps || originUri.AbsolutePath != "/" ||
            !string.IsNullOrEmpty(originUri.Query) || !string.IsNullOrEmpty(originUri.Fragment))
            throw new InvalidOperationException("SQL configuration 'web.allowed_origin' must be an HTTPS origin without a path.");

        var smtpRequireTls = await Flag("smtp.require_tls");
        var smtpUsername = await Optional("smtp.username", "STRING");
        var smtpPasswordReference = await VaultReference("smtp.password_ref");
        if (!string.IsNullOrWhiteSpace(smtpUsername) && string.IsNullOrWhiteSpace(smtpPasswordReference))
            throw new InvalidOperationException("SMTP credentials require a Key Vault secret reference.");

        return new RuntimeSettings(
            issuerUri.AbsoluteUri.TrimEnd('/'),
            audience,
            originUri.GetLeftPart(UriPartial.Authority).TrimEnd('/'),
            await Bounded("auth.access_token_minutes", 5, 60),
            await Bounded("auth.refresh_token_days", 1, 30),
            await Bounded("security.max_login_attempts", 3, 10),
            await Bounded("security.password.min_length", 12, 128),
            await Bounded("auth.email_verification_hours", 1, 24),
            await Bounded("database.command_timeout_seconds", 1, 120),
            await Bounded("security.auth_requests_per_minute", 1, 120),
            await Required("smtp.host", "STRING"),
            await Bounded("smtp.port", 1, 65535),
            await Required("smtp.from", "STRING"),
            smtpRequireTls,
            smtpUsername,
            await VaultReference("auth.signing_key_ref"),
            smtpPasswordReference,
            await Flag("registration.legal_consent_enforcement"),
            developmentTermsBypassEnabled,
            await Flag("registration.personal.enabled"),
            await Flag("registration.organization.enabled"),
            await OptionalFlag("notification.email_verification_templates.enabled", false));
    }
}
