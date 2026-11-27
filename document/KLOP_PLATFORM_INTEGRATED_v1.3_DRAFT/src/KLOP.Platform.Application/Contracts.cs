namespace KLOP.Platform.Application;

public record RegistrationRequest(string Email, string DisplayName, string Password);
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
