using KLOP.Platform.Application;
using KLOP.Platform.Api.Logging;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace KLOP.Platform.Api;

public static class ApiHelpers
{
    public const string CorrelationItemKey = "KLOP.CorrelationId";
    public const string ResultCodeItemKey = "KLOP.ResultCode";

    public static IResult Success<T>(HttpContext context, T data, int status = StatusCodes.Status200OK)
    {
        context.Items[ResultCodeItemKey] = CompactRequestLogPolicy.SuccessResultCode(context, status);
        return Results.Json(new ApiEnvelope<T>(true, data, null, new ApiMeta(context.TraceIdentifier)),
            statusCode: status);
    }

    public static IResult Error(HttpContext context, int status, string code, string message,
        IReadOnlyDictionary<string, string[]>? validationErrors = null)
    {
        context.Items[ResultCodeItemKey] = CompactRequestLogPolicy.ErrorResultCode(status, code);
        var problem = new ProblemDetails
        {
            Type = "about:blank",
            Title = code,
            Status = status,
            Detail = message,
            Instance = context.Request.Path
        };
        problem.Extensions["success"] = false;
        problem.Extensions["error"] = new ApiError(code, message);
        problem.Extensions["meta"] = new ApiMeta(context.TraceIdentifier);
        if (validationErrors is not null)
            problem.Extensions["errors"] = validationErrors;
        return Results.Problem(problem);
    }

    public static (long UserId, Guid SessionId)? Identity(HttpContext context)
        => Identity(context.User);

    public static (long UserId, Guid SessionId)? Identity(ClaimsPrincipal principal)
    {
        if (long.TryParse(principal.FindFirst("sub")?.Value, out var userId) &&
            Guid.TryParse(principal.FindFirst("sid")?.Value, out var sessionId))
            return (userId, sessionId);
        return null;
    }

    public static Guid Correlation(HttpContext context) =>
        context.Items.TryGetValue(CorrelationItemKey, out var value) && value is Guid correlationId
            ? correlationId
            : Guid.NewGuid();

    public static RequestMetadata Metadata(HttpContext context) =>
        new(context.TraceIdentifier, Correlation(context));

    public static bool SameOrigin(HttpContext context, IPlatformRuntimeSettings settings)
    {
        var origin = context.Request.Headers["Origin"].ToString();
        return !string.IsNullOrWhiteSpace(origin) &&
            string.Equals(settings.AllowedOrigin, origin.TrimEnd('/'), StringComparison.OrdinalIgnoreCase);
    }

    public static async Task<bool> Can(
        HttpContext context,
        IAuthorizationService authorization,
        long tenantId,
        string permission) =>
        (await authorization.AuthorizeAsync(context.User, context,
            new TenantPermissionRequirement(tenantId, permission))).Succeeded;

    public static (int Status, string Code, string Message) MapSql(SqlException exception) =>
        exception.Number switch
        {
            208 or 2812 =>
                (StatusCodes.Status503ServiceUnavailable, "FEATURE_UNAVAILABLE", "The registration service is not ready."),
            52116 =>
                (StatusCodes.Status409Conflict, "TERMS_VERSION_OUTDATED", "Current Terms changed; retrieve and accept the current version."),
            52115 =>
                (StatusCodes.Status400BadRequest, "REGISTRATION_CONSENT_REQUIRED", "Current Terms acceptance is required."),
            52603 or 52606 or 52607 =>
                (StatusCodes.Status409Conflict, "CONFLICT", "Request conflicts with current state."),
            52601 =>
                (StatusCodes.Status404NotFound, "NOT_FOUND", "The requested resource is unavailable."),
            52602 =>
                (StatusCodes.Status403Forbidden, "FORBIDDEN", "Operation is not permitted."),
            52114 or 52604 =>
                (StatusCodes.Status400BadRequest, "INVALID_REQUEST", "Request parameters are invalid."),
            52118 =>
                (StatusCodes.Status403Forbidden, "REGISTRATION_DISABLED", "This registration type is unavailable."),
            52605 =>
                (StatusCodes.Status503ServiceUnavailable, "ONBOARDING_POLICY_PENDING", "Onboarding submission is not enabled by approved policy."),
            52701 =>
                (StatusCodes.Status400BadRequest, "INVALID_LEGAL_DOCUMENT", "Legal document metadata is invalid."),
            52702 =>
                (StatusCodes.Status404NotFound, "NOT_FOUND", "The requested legal document is unavailable."),
            52703 or 52704 =>
                (StatusCodes.Status409Conflict, "LEGAL_DOCUMENT_CONFLICT", "The legal document changed or is in an invalid state."),
            52705 or 52706 =>
                (StatusCodes.Status503ServiceUnavailable, "LEGAL_DOCUMENT_UNAVAILABLE", "The legal document service is not ready."),
            52910 or 52911 or 52912 or 52913 or 52914 or 52915 =>
                (StatusCodes.Status400BadRequest, "INVALID_REGISTRATION_QUERY", "Registration query parameters are invalid."),
            52916 =>
                (StatusCodes.Status404NotFound, "REGISTRATION_NOT_FOUND", "The registration application is unavailable."),
            52117 or 52608 or 8144 =>
                (StatusCodes.Status503ServiceUnavailable, "FEATURE_UNAVAILABLE", "The registration service is not ready."),
            52113 or 52136 or 52137 or 52142 or 52147 or 52153 or 52157 or 52163 or 52167 or 52168 or
                52173 or 52178 or 52179 or 52183 or 52187 or 52189 or 52190 =>
                (StatusCodes.Status409Conflict, "CONFLICT", "Request conflicts with current state."),
            52123 or 52322 or 52323 or 52330 or 52342 or 52343 or 52344 or 52346 or 52347 or 52351 =>
                (StatusCodes.Status401Unauthorized, "INVALID_CREDENTIALS", "Credentials or session are invalid."),
            52133 or 52144 or 52146 or 52155 or 52156 or 52165 or 52176 or 52177 or 52186 or 52188 or 52331 or 52332 =>
                (StatusCodes.Status403Forbidden, "FORBIDDEN", "Operation is not permitted."),
            52191 =>
                (StatusCodes.Status403Forbidden, "FORBIDDEN", "Operation is not permitted."),
            52192 =>
                (StatusCodes.Status409Conflict, "CONFLICT", "Request conflicts with current state."),
            52152 or 52162 or 52166 or 52172 or 52175 or 52182 or 52185 =>
                (StatusCodes.Status404NotFound, "NOT_FOUND", "The requested resource is unavailable."),
            52111 or 52121 or 52124 or 52131 or 52132 or 52135 or 52141 or 52145 or 52151 or 52161 or
                52171 or 52181 or 52310 or 52311 or 52321 or 52333 =>
                (StatusCodes.Status400BadRequest, "INVALID_REQUEST", "Request parameters are invalid."),
            2601 or 2627 => (StatusCodes.Status409Conflict, "CONFLICT", "Request conflicts with current state."),
            _ => (StatusCodes.Status500InternalServerError, "SERVER_ERROR", "Operation failed.")
        };
}
