using System.Diagnostics;
using KLOP.Platform.Application;
using KLOP.Platform.Domain;
using Microsoft.Data.SqlClient;
using Serilog.Context;

namespace KLOP.Platform.Api.Logging;

internal sealed class RoutineHealthCheckLoggingMetadata
{
}

public sealed class CorrelationIdMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var supplied = context.Request.Headers["X-Correlation-Id"];
        var correlationId = supplied.Count == 1 && supplied[0]?.Length == 36 &&
            Guid.TryParseExact(supplied[0], "D", out var parsed) && parsed != Guid.Empty
                ? parsed
                : Guid.NewGuid();
        var correlationText = correlationId.ToString("D");
        context.Items[ApiHelpers.CorrelationItemKey] = correlationId;
        context.TraceIdentifier = correlationText;
        context.Response.OnStarting(() =>
        {
            context.Response.Headers["X-Correlation-Id"] = correlationText;
            return Task.CompletedTask;
        });

        using (LogContext.PushProperty("CorrelationId", correlationText))
        using (LogContext.PushProperty("TraceId", Activity.Current?.TraceId.ToString()))
            await next(context);
    }
}

public sealed class CompactRequestCompletionLoggingMiddleware(
    RequestDelegate next,
    ILogger<CompactRequestCompletionLoggingMiddleware> logger)
{
    private static readonly EventId CompletionEventId = new(1001, "HttpRequestCompleted");

    public async Task InvokeAsync(HttpContext context)
    {
        var timer = Stopwatch.StartNew();
        Exception? unhandledException = null;
        try
        {
            await next(context);
        }
        catch (Exception exception)
        {
            unhandledException = exception;
            throw;
        }
        finally
        {
            timer.Stop();
            if (!CompactRequestLogPolicy.IsRoutineHealthyCheck(context))
                WriteCompletion(context, timer.Elapsed.TotalMilliseconds, unhandledException);
        }
    }

    private void WriteCompletion(HttpContext context, double durationMs, Exception? unhandledException)
    {
        var statusCode = context.Response.StatusCode;
        var resultCode = unhandledException is null
            ? CompactRequestLogPolicy.ResultCode(context)
            : "INTERNAL_ERROR";
        var level = unhandledException is null
            ? CompactRequestLogPolicy.LogLevelForStatus(statusCode)
            : LogLevel.Error;
        var correlationId = context.Items.TryGetValue(ApiHelpers.CorrelationItemKey, out var value) &&
            value is Guid id
                ? id.ToString("D")
                : Guid.NewGuid().ToString("D");
        KeyValuePair<string, object?>[] properties =
        [
            new(CompactLogProperties.IsRequestCompletion, true),
            new(CompactLogProperties.SuppressFileLog, false),
            new(CompactLogProperties.HttpMethod, context.Request.Method),
            new(CompactLogProperties.RouteTemplate, CompactRequestLogPolicy.RouteTemplate(context)),
            new(CompactLogProperties.HttpStatusCode, statusCode),
            new(CompactLogProperties.DurationMs, durationMs),
            new(CompactLogProperties.CorrelationId, correlationId),
            new(CompactLogProperties.ResultCode, resultCode),
            new("{OriginalFormat}", "HTTP request completed")
        ];

        try
        {
            logger.Log(level, CompletionEventId, properties, null,
                static (_, _) => "HTTP request completed");
        }
        catch (Exception)
        {
            CompactLoggingFallback.Report("FILE_LOGGING_FAILED", correlationId);
        }
    }
}

public sealed class ApiExceptionHandlingMiddleware(
    RequestDelegate next,
    ILogger<ApiExceptionHandlingMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (TenantRegistrationDisabledException)
        {
            await ApiHelpers.Error(context, StatusCodes.Status403Forbidden,
                "REGISTRATION_DISABLED", "Tenant registration is disabled.").ExecuteAsync(context);
        }
        catch (UnknownTenantTypeException)
        {
            await ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_TENANT_TYPE", "Tenant type is not available.").ExecuteAsync(context);
        }
        catch (LegalDocumentStorageUnavailableException)
        {
            logger.LogWarning(
                "Legal document dependency unavailable. IsImportantProcessEvent={IsImportantProcessEvent} Component={Component} ResultCode={ResultCode} CorrelationId={CorrelationId}",
                true, "LegalDocument", "LEGAL_DOCUMENT_UNAVAILABLE", ApiHelpers.Correlation(context).ToString("D"));
            await ApiHelpers.Error(context, StatusCodes.Status503ServiceUnavailable,
                "LEGAL_DOCUMENT_UNAVAILABLE", "The legal document is temporarily unavailable.").ExecuteAsync(context);
        }
        catch (LegalDocumentStorageValidationException exception)
        {
            await ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                exception.Code, exception.Message).ExecuteAsync(context);
        }
        catch (LegalDocumentValidationException exception)
        {
            await ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                exception.Code, exception.Message).ExecuteAsync(context);
        }
        catch (LegalDocumentNotFoundException)
        {
            await ApiHelpers.Error(context, StatusCodes.Status404NotFound,
                "NOT_FOUND", "The requested legal document is unavailable.").ExecuteAsync(context);
        }
        catch (LegalDocumentConflictException exception)
        {
            await ApiHelpers.Error(context, StatusCodes.Status409Conflict,
                exception.Code, exception.Message).ExecuteAsync(context);
        }
        catch (OrganizationRequirementsUnavailableException)
        {
            await ApiHelpers.Error(context, StatusCodes.Status503ServiceUnavailable,
                "ORGANIZATION_REQUIREMENTS_UNAVAILABLE", "Organization requirements are not configured.").ExecuteAsync(context);
        }
        catch (SqlException exception)
        {
            var mapped = ApiHelpers.MapSql(exception);
            var resultCode = mapped.Status >= StatusCodes.Status500InternalServerError
                ? "SQL_OPERATION_FAILED"
                : "SQL_OPERATION_REJECTED";
            logger.Log(mapped.Status >= StatusCodes.Status500InternalServerError
                    ? LogLevel.Error
                    : LogLevel.Warning,
                "SQL request failed. IsImportantProcessEvent={IsImportantProcessEvent} Component={Component} ResultCode={ResultCode} CorrelationId={CorrelationId} SqlErrorNumber={SqlErrorNumber}",
                true, SqlFailureComponent(context), resultCode, ApiHelpers.Correlation(context).ToString("D"), exception.Number);
            if (context.Response.HasStarted)
                throw;
            await ApiHelpers.Error(context, mapped.Status, mapped.Code, mapped.Message).ExecuteAsync(context);
        }
        catch (Exception exception)
        {
            logger.LogError(
                "Unhandled request failure. IsImportantProcessEvent={IsImportantProcessEvent} Component={Component} ResultCode={ResultCode} CorrelationId={CorrelationId} FailureType={FailureType}",
                true, "Request", "INTERNAL_ERROR", ApiHelpers.Correlation(context).ToString("D"),
                exception.GetType().Name);
            if (context.Response.HasStarted)
                throw;
            await ApiHelpers.Error(context, StatusCodes.Status500InternalServerError,
                "SERVER_ERROR", "Request could not be completed.").ExecuteAsync(context);
        }
    }

    private static string SqlFailureComponent(HttpContext context) =>
        CompactRequestLogPolicy.RouteTemplate(context) switch
        {
            "/api/v1/auth/register" => "Registration",
            "/api/v1/auth/verify-email" or "/api/v1/auth/resend-verification" => "EmailVerification",
            "/api/v1/public/legal/terms/current" or "/api/v1/public/legal/terms/{documentVersionId:guid}/file" => "LegalDocument",
            var route when route.StartsWith("/api/v1/platform/legal-documents", StringComparison.Ordinal) => "LegalDocumentAdministration",
            "/api/v1/onboarding/personal/draft" => "PersonalDraftUpdate",
            "/api/v1/onboarding/organization/draft" => "OrganizationDraftUpdate",
            "/api/v1/onboarding/organization/requirements" => "OrganizationRequirements",
            "/api/v1/onboarding/submit" => "OnboardingSubmission",
            _ => "Database"
        };
    }

internal static class CompactLoggingFallback
{
    private static readonly object SyncRoot = new();

    public static void Report(string resultCode, string? correlationId = null)
    {
        try
        {
            var id = Guid.TryParseExact(correlationId, "D", out var parsed)
                ? parsed.ToString("D")
                : "UNAVAILABLE";
            var line = $"{DateTimeOffset.UtcNow:yyyy-MM-dd'T'HH:mm:ss.fff'Z'} | ERROR | EVENT | Logging | {id} | {resultCode}";
            lock (SyncRoot)
                Console.Error.WriteLine(line);
        }
        catch
        {
        }
    }
}