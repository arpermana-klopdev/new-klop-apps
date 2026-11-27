namespace KLOP.Platform.Application;

public interface IPasswordPolicy
{
    int MinPasswordLength { get; }
}

public interface IPlatformRuntimeSettings : IPasswordPolicy
{
    string JwtIssuer { get; }
    string JwtAudience { get; }
    string AllowedOrigin { get; }
    int AccessMinutes { get; }
    int RefreshDays { get; }
    int MaxLoginAttempts { get; }
    int EmailVerificationHours { get; }
    int CommandTimeoutSeconds { get; }
    int AuthRequestsPerMinute { get; }
    string SmtpHost { get; }
    int SmtpPort { get; }
    string SmtpFrom { get; }
    bool SmtpRequireTls { get; }
    string? SmtpUsername { get; }
    string? SigningKeyReference { get; }
    string? SmtpPasswordReference { get; }
    bool LegalConsentEnforcement { get; }
    bool DevelopmentTermsBypassEnabled { get; }
    bool PersonalRegistrationEnabled { get; }
    bool OrganizationRegistrationEnabled { get; }
    bool NotificationTemplatesEnabled { get; }
    bool NotificationDeliveryAuditEnabled { get; }
}