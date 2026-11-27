using System.Data;
using Dapper;

namespace KLOP.Platform.Infrastructure;

// Loaded from SQL cfg.SystemConfigurations via a read-only Stored Procedure.
// Only server, database, authentication, and Key Vault URI are bootstrap appsettings.
public sealed record RuntimeSettings(
    string JwtIssuer, string JwtAudience, string AllowedOrigin,
    int AccessMinutes, int RefreshDays, int MaxLoginAttempts, int MinPasswordLength,
    bool PersonalEnabled, bool OrganizationEnabled,
    string SmtpHost, int SmtpPort, string SmtpFrom, bool SmtpRequireTls,
    string? SmtpUsername, string? SigningKeyReference, string? SmtpPasswordReference,
    int EmailVerificationHours)
{
    private sealed class ConfigRow
    {
        public string ConfigurationValue {get;set;}="";
        public string StorageType {get;set;}="";
    }
    public static async Task<RuntimeSettings> Load(SqlConnectionFactory factory)
    {
        using var conn=factory.Open();
        async Task<ConfigRow?> Row(string key) => await conn.QuerySingleOrDefaultAsync<ConfigRow>(
            new CommandDefinition("cfg.usp_Configuration_GetByKey",new {ConfigurationKey=key},
                commandType:CommandType.StoredProcedure,commandTimeout:20));
        async Task<string> Required(string key)
        {
            var x=await Row(key);
            if(x is null || x.StorageType!="PLAIN" || string.IsNullOrWhiteSpace(x.ConfigurationValue))
                throw new InvalidOperationException($"Required SQL configuration '{key}' is absent or invalid.");
            return x.ConfigurationValue.Trim();
        }
        async Task<string?> Optional(string key)
        {
            var x=await Row(key);
            if(x is null) return null;
            if(x.StorageType!="PLAIN") throw new InvalidOperationException($"Invalid storage type for '{key}'.");
            return string.IsNullOrWhiteSpace(x.ConfigurationValue)?null:x.ConfigurationValue.Trim();
        }
        async Task<string?> VaultReference(string key)
        {
            var x=await Row(key);
            if(x is null) return null;
            if(x.StorageType!="KEYVAULT_REFERENCE") throw new InvalidOperationException($"'{key}' must be a Key Vault reference.");
            return string.IsNullOrWhiteSpace(x.ConfigurationValue)?null:x.ConfigurationValue.Trim();
        }
        async Task<int> Bounded(string key,int min,int max)
        {
            var v=await Required(key);
            if(!int.TryParse(v,out var n)||n<min||n>max)
                throw new InvalidOperationException($"Invalid numeric SQL configuration '{key}'.");
            return n;
        }
        async Task<bool> Flag(string key)
        {
            if(!bool.TryParse(await Required(key),out var b))
                throw new InvalidOperationException($"Invalid boolean SQL configuration '{key}'.");
            return b;
        }
        return new RuntimeSettings(
            await Required("auth.jwt.issuer"),await Required("auth.jwt.audience"),
            await Required("web.allowed_origin"),
            await Bounded("auth.access_token_minutes",5,60),
            await Bounded("auth.refresh_token_days",1,30),
            await Bounded("security.max_login_attempts",3,10),
            await Bounded("security.password.min_length",12,128),
            await Flag("registration.personal.enabled"),
            await Flag("registration.organization.enabled"),
            await Required("smtp.host"), await Bounded("smtp.port",1,65535),
            await Required("smtp.from"), await Flag("smtp.require_tls"),
            await Optional("smtp.username"),await VaultReference("auth.signing_key_ref"),
            await VaultReference("smtp.password_ref"),
            await Bounded("auth.email_verification_hours",1,24));
    }
}
