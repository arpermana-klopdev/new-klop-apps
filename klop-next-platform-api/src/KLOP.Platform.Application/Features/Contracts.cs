using System.Text.Json.Serialization;

namespace KLOP.Platform.Application;

public interface IRegistrationFields
{
    string Email { get; }
    string? DisplayName { get; }
    string Password { get; }
    string? RegistrationType { get; }
}

public sealed record DirectRegistrationRequest(
    string Email,
    [property: JsonPropertyName("displayName")] string DisplayName,
    string Password,
    string RegistrationType) : IRegistrationFields
{
    string? IRegistrationFields.DisplayName => DisplayName;
    string? IRegistrationFields.RegistrationType => RegistrationType;
}

public sealed record TermsRequiredRegistrationRequest(
    string Email,
    [property: JsonPropertyName("displayName")] string DisplayName,
    string Password,
    string RegistrationType,
    Guid TermsDocumentVersionId,
    bool TermsAccepted) : IRegistrationFields
{
    string? IRegistrationFields.DisplayName => DisplayName;
    string? IRegistrationFields.RegistrationType => RegistrationType;
}

public record RegistrationRequest(
    string Email,
    [property: JsonPropertyName("displayName")] string? DisplayName,
    string Password) : IRegistrationFields
{
    [JsonPropertyName("registrationType")]
    public string? RegistrationType { get; init; }

    [JsonPropertyName("termsDocumentVersionId")]
    public Guid? TermsDocumentVersionId { get; init; }

    [JsonPropertyName("termsAccepted")]
    public bool? TermsAccepted { get; init; }

}
public record RegistrationPolicyResponse(
    bool TermsRequired,
    int PasswordMinLength,
    int PasswordMaxLength,
    IReadOnlyList<string> AllowedRegistrationTypes);
public static class RegistrationPolicyRules
{
    public static void ValidateRuntime(IPlatformRuntimeSettings settings, bool isDevelopment)
    {
        if (settings.DevelopmentTermsBypassEnabled && !isDevelopment)
            throw new InvalidOperationException("The Development Terms bypass cannot be enabled outside Development.");
        if (!isDevelopment && !settings.LegalConsentEnforcement)
            throw new InvalidOperationException("Production requires Terms consent enforcement.");
        if (settings.DevelopmentTermsBypassEnabled && settings.LegalConsentEnforcement)
            throw new InvalidOperationException(
                "The Development Terms bypass requires registration.legal_consent_enforcement to be false.");
    }

    public static RegistrationPolicyResponse GetEffective(IPlatformRuntimeSettings settings)
    {
        var allowedTypes = new List<string>(2);
        if (settings.PersonalRegistrationEnabled)
            allowedTypes.Add("PERSONAL");
        if (settings.OrganizationRegistrationEnabled)
            allowedTypes.Add("ORGANIZATION");
        return new RegistrationPolicyResponse(
            !settings.DevelopmentTermsBypassEnabled,
            settings.MinPasswordLength,
            RegistrationLimits.MaxPasswordLength,
            allowedTypes);
    }
}
public record VerifyEmailRequest(long UserId, string Token);
public record ResendVerificationRequest(string Email);
public record LoginRequest(string Email, string Password);
public record TenantCreateRequest(string TenantCode, string TenantTypeCode, string DisplayName,
    long? OrganizationTypeId, string? RegisteredName);
public record InviteRequest(long InviteeUserId);
public record RoleRequest(string RoleCode);
public record ApiError(string Code, string Message);
public record ApiMeta(string RequestId);
public record ApiEnvelope<T>(bool Success, T? Data, ApiError? Error, ApiMeta Meta);
public record AccessResult(string AccessToken, int ExpiresInSeconds, string TokenType = "Bearer");
public record RegistrationResult(long UserId, long ChallengeId);
public record TenantCreateResult(long TenantId, long MembershipId);
public record AuthenticatedSession(AccessResult Access, Guid SessionId, string RefreshToken, int RefreshDays);
public record RequestMetadata(string RequestId, Guid CorrelationId);
public sealed class DuplicateRegistrationException() : Exception("Registration already exists.");
public sealed class UnknownTenantTypeException() : Exception("Tenant type is unavailable.");
public sealed class TenantRegistrationDisabledException() : Exception("Tenant registration is disabled.");
