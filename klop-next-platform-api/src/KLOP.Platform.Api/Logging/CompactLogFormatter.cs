using System.Globalization;
using System.Text;
using Microsoft.AspNetCore.Routing;
using Serilog;
using Serilog.Events;
using Serilog.Formatting;

namespace KLOP.Platform.Api.Logging;

internal static class CompactLogProperties
{
    public const string IsRequestCompletion = "IsRequestCompletion";
    public const string IsImportantProcessEvent = "IsImportantProcessEvent";
    public const string SuppressFileLog = "SuppressFileLog";
    public const string HttpMethod = "HttpMethod";
    public const string RouteTemplate = "RouteTemplate";
    public const string HttpStatusCode = "HttpStatusCode";
    public const string DurationMs = "DurationMs";
    public const string CorrelationId = "CorrelationId";
    public const string ResultCode = "ResultCode";
    public const string Component = "Component";
}

internal static class CompactRequestLogPolicy
{
    public static string RouteTemplate(HttpContext context) =>
        context.GetEndpoint() is RouteEndpoint routeEndpoint &&
        !string.IsNullOrWhiteSpace(routeEndpoint.RoutePattern.RawText)
            ? routeEndpoint.RoutePattern.RawText
            : "UNMATCHED_ROUTE";

    public static string SuccessResultCode(HttpContext context, int statusCode)
    {
        var route = RouteTemplate(context);
        if (statusCode == StatusCodes.Status202Accepted &&
            route.Equals("/api/v1/auth/register", StringComparison.Ordinal))
            return "REGISTER_ACCEPTED";
        if (statusCode is >= 200 and < 300 &&
            route.Equals("/api/v1/auth/verify-email", StringComparison.Ordinal))
            return "EMAIL_VERIFIED";
        if (statusCode is >= 200 and < 300 &&
            route.Equals("/api/v1/auth/login", StringComparison.Ordinal))
            return "LOGIN_SUCCESS";
        return "REQUEST_SUCCESS";
    }

    public static string ErrorResultCode(int statusCode, string? publicCode = null) => statusCode switch
    {
        StatusCodes.Status400BadRequest or StatusCodes.Status422UnprocessableEntity => "INVALID_REQUEST",
        StatusCodes.Status401Unauthorized when publicCode == "INVALID_CREDENTIALS" => "INVALID_CREDENTIALS",
        StatusCodes.Status401Unauthorized => "UNAUTHORIZED",
        StatusCodes.Status403Forbidden => "FORBIDDEN",
        StatusCodes.Status404NotFound => "RESOURCE_NOT_FOUND",
        StatusCodes.Status409Conflict => "CONFLICT",
        StatusCodes.Status429TooManyRequests => "RATE_LIMITED",
        StatusCodes.Status503ServiceUnavailable => "SERVICE_UNAVAILABLE",
        >= StatusCodes.Status500InternalServerError => "INTERNAL_ERROR",
        _ => "REQUEST_FAILED"
    };

    public static bool IsRoutineHealthyCheck(HttpContext context) =>
        context.Response.StatusCode is >= 200 and < 300 &&
        context.GetEndpoint()?.Metadata.GetMetadata<RoutineHealthCheckLoggingMetadata>() is not null;

    public static string ResultCode(HttpContext context)
    {
        if (context.Response.StatusCode >= 400)
        {
            var publicCode = context.Items.TryGetValue(ApiHelpers.ResultCodeItemKey, out var errorValue)
                ? errorValue as string
                : null;
            return ErrorResultCode(context.Response.StatusCode, publicCode);
        }
        if (context.Items.TryGetValue(ApiHelpers.ResultCodeItemKey, out var value) && value is string code)
            return code;
        return context.Response.StatusCode is >= 200 and < 400
            ? SuccessResultCode(context, context.Response.StatusCode)
            : ErrorResultCode(context.Response.StatusCode);
    }

    public static LogLevel LogLevelForStatus(int statusCode) => statusCode switch
    {
        >= 500 => LogLevel.Error,
        >= 400 => LogLevel.Warning,
        _ => LogLevel.Information
    };
}

internal sealed class CompactLogFormatter : ITextFormatter
{
    public void Format(LogEvent logEvent, TextWriter output)
    {
        if (GetBoolean(logEvent, CompactLogProperties.SuppressFileLog))
            return;

        if (GetBoolean(logEvent, CompactLogProperties.IsRequestCompletion))
        {
            WriteRequest(logEvent, output);
            return;
        }

        if (GetBoolean(logEvent, CompactLogProperties.IsImportantProcessEvent))
            WriteProcessEvent(logEvent, output);
    }

    private static void WriteRequest(LogEvent logEvent, TextWriter output)
    {
        var fields = new[]
        {
            Timestamp(logEvent),
            Level(logEvent.Level),
            $"{Clean(GetString(logEvent, CompactLogProperties.HttpMethod), "UNKNOWN_METHOD", 16)} {Clean(GetString(logEvent, CompactLogProperties.RouteTemplate), "UNMATCHED_ROUTE", 180)}",
            GetInteger(logEvent, CompactLogProperties.HttpStatusCode).ToString(CultureInfo.InvariantCulture),
            $"{GetDuration(logEvent)}ms",
            Correlation(logEvent),
            SafeResultCode(GetString(logEvent, CompactLogProperties.ResultCode))
        };
        output.WriteLine(string.Join(" | ", fields));
    }

    private static void WriteProcessEvent(LogEvent logEvent, TextWriter output)
    {
        var fields = new[]
        {
            Timestamp(logEvent),
            Level(logEvent.Level),
            "EVENT",
            Clean(GetString(logEvent, CompactLogProperties.Component), "Application", 64),
            Correlation(logEvent),
            SafeResultCode(GetString(logEvent, CompactLogProperties.ResultCode))
        };
        output.WriteLine(string.Join(" | ", fields));
    }

    private static string Timestamp(LogEvent logEvent) =>
        logEvent.Timestamp.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);

    private static string Level(LogEventLevel level) => level switch
    {
        LogEventLevel.Verbose => "TRACE",
        LogEventLevel.Debug => "DEBUG",
        LogEventLevel.Information => "INFO",
        LogEventLevel.Warning => "WARN",
        LogEventLevel.Error => "ERROR",
        LogEventLevel.Fatal => "FATAL",
        _ => "INFO"
    };

    private static string Correlation(LogEvent logEvent)
    {
        var value = GetString(logEvent, CompactLogProperties.CorrelationId);
        return Guid.TryParseExact(value, "D", out var correlationId)
            ? correlationId.ToString("D")
            : "UNAVAILABLE";
    }

    private static string SafeResultCode(string? value) => value is not null &&
        ResultCodes.Contains(value) ? value : "REQUEST_FAILED";

    private static readonly HashSet<string> ResultCodes = new(StringComparer.Ordinal)
    {
        "REQUEST_SUCCESS", "REGISTER_ACCEPTED", "EMAIL_VERIFIED", "LOGIN_SUCCESS",
        "INVALID_REQUEST", "INVALID_CREDENTIALS", "UNAUTHORIZED", "FORBIDDEN",
        "RATE_LIMITED", "RESOURCE_NOT_FOUND", "CONFLICT", "INTERNAL_ERROR",
        "SERVICE_UNAVAILABLE", "REQUEST_FAILED", "SQL_OPERATION_FAILED",
        "SQL_OPERATION_REJECTED", "SMTP_DELIVERY_FAILED", "DEPENDENCY_UNAVAILABLE",
        "AUTHENTICATION_FAILED", "AUTHENTICATION_HEADER_MISSING", "SESSION_CLAIMS_INVALID",
        "SESSION_INACTIVE",
        "FILE_LOGGING_UNAVAILABLE", "FILE_LOGGING_FAILED"
    };

    private static bool GetBoolean(LogEvent logEvent, string name) =>
        logEvent.Properties.TryGetValue(name, out var value) && value is ScalarValue { Value: true };

    private static string? GetString(LogEvent logEvent, string name) =>
        logEvent.Properties.TryGetValue(name, out var value) && value is ScalarValue scalar
            ? Convert.ToString(scalar.Value, CultureInfo.InvariantCulture)
            : null;

    private static int GetInteger(LogEvent logEvent, string name) =>
        int.TryParse(GetString(logEvent, name), NumberStyles.None, CultureInfo.InvariantCulture, out var value)
            ? value
            : StatusCodes.Status500InternalServerError;

    private static string GetDuration(LogEvent logEvent)
    {
        if (!double.TryParse(GetString(logEvent, CompactLogProperties.DurationMs), NumberStyles.Float,
                CultureInfo.InvariantCulture, out var duration) || !double.IsFinite(duration))
            return "0";
        return Math.Max(0, Math.Round(duration, MidpointRounding.AwayFromZero))
            .ToString("0", CultureInfo.InvariantCulture);
    }

    private static string Clean(string? value, string fallback, int maximumLength)
    {
        if (string.IsNullOrWhiteSpace(value))
            return fallback;

        var builder = new StringBuilder(Math.Min(value.Length, maximumLength));
        foreach (var character in value)
        {
            if (builder.Length == maximumLength)
                break;
            builder.Append(character is '|' or '\r' or '\n' || char.IsControl(character) ? '_' : character);
        }
        return builder.Length == 0 ? fallback : builder.ToString();
    }
}

internal sealed record CompactFileLogSettings(string Path, long MaximumFileSizeBytes, int RetainedArchiveCount)
{
    public static CompactFileLogSettings Load(IConfiguration configuration, string contentRoot)
    {
        var configuredPath = configuration["Logging:File:Path"];
        if (string.IsNullOrWhiteSpace(configuredPath))
            throw new InvalidOperationException("Logging:File:Path must be configured.");

        if (!long.TryParse(configuration["Logging:File:MaximumFileSizeBytes"], NumberStyles.None,
                CultureInfo.InvariantCulture, out var maximumFileSizeBytes) ||
            maximumFileSizeBytes is < 1_048_576 or > 1_073_741_824)
            throw new InvalidOperationException("Logging:File:MaximumFileSizeBytes is outside its allowed range.");

        if (!int.TryParse(configuration["Logging:File:RetainedArchiveCount"], NumberStyles.None,
                CultureInfo.InvariantCulture, out var retainedArchiveCount) ||
            retainedArchiveCount is < 1 or > 100)
            throw new InvalidOperationException("Logging:File:RetainedArchiveCount is outside its allowed range.");

        var fullPath = System.IO.Path.IsPathRooted(configuredPath)
            ? System.IO.Path.GetFullPath(configuredPath)
            : System.IO.Path.GetFullPath(configuredPath, contentRoot);
        return new CompactFileLogSettings(fullPath, maximumFileSizeBytes, retainedArchiveCount);
    }
}

internal static class CompactFileLogSink
{
    public static bool TryAdd(LoggerConfiguration logger, CompactFileLogSettings settings, Action<string> reportFailure)
    {
        try
        {
            var directory = Path.GetDirectoryName(settings.Path) ??
                throw new InvalidOperationException("The configured log file has no parent directory.");
            Directory.CreateDirectory(directory);
            using (new FileStream(settings.Path, FileMode.Append, FileAccess.Write,
                       FileShare.ReadWrite | FileShare.Delete)) { }

            logger.WriteTo.File(new CompactLogFormatter(), settings.Path,
                restrictedToMinimumLevel: LogEventLevel.Information,
                fileSizeLimitBytes: settings.MaximumFileSizeBytes,
                rollOnFileSizeLimit: true,
                retainedFileCountLimit: settings.RetainedArchiveCount + 1,
                shared: true,
                encoding: new UTF8Encoding(false),
                buffered: false,
                flushToDiskInterval: TimeSpan.FromSeconds(1));
            return true;
        }
        catch (Exception exception)
        {
            try
            {
                reportFailure(exception.GetType().Name);
            }
            catch
            {
            }
            return false;
        }
    }
}