using System.Globalization;
using System.Net;
using KLOP.Platform.Api;
using KLOP.Platform.Api.Logging;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.Routing.Patterns;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Serilog.Parsing;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class CompactLoggingTests
{
    private static readonly DateTimeOffset EventTimestamp =
        new(2026, 11, 22, 6, 5, 10, 125, TimeSpan.FromHours(7));

    [Fact]
    public void FormatterWritesUtcSingleLineWithSevenRequestFields()
    {
        var correlationId = Guid.NewGuid();
        var output = Format(RequestEvent((CompactLogProperties.CorrelationId, correlationId.ToString("D"))));
        var fields = output.TrimEnd('\r', '\n').Split(" | ");

        Assert.Equal(7, fields.Length);
        Assert.Equal("2026-11-21T23:05:10.125Z", fields[0]);
        Assert.Equal("INFO", fields[1]);
        Assert.Equal("GET /records/{recordId:int}", fields[2]);
        Assert.Equal("202", fields[3]);
        Assert.Equal("135ms", fields[4]);
        Assert.Equal(correlationId.ToString("D"), fields[5]);
        Assert.Equal("REQUEST_SUCCESS", fields[6]);
        Assert.EndsWith(Environment.NewLine, output);
        Assert.Equal(1, output.Count(character => character == '\n'));
    }

    [Fact]
    public void FormatterIgnoresUnmarkedEvents()
    {
        Assert.Empty(Format(CreateEvent(LogEventLevel.Information)));
    }

    [Fact]
    public void FormatterSkipsExplicitlySuppressedHealthSuccess()
    {
        Assert.Empty(Format(RequestEvent((CompactLogProperties.SuppressFileLog, true))));
    }

    [Fact]
    public void FormatterUsesRouteTemplateInsteadOfRawPathOrQuery()
    {
        var output = Format(RequestEvent(("RequestPath", "/records/87?token=do-not-log"),
            (CompactLogProperties.RouteTemplate, "/records/{recordId:int}")));

        Assert.Contains("GET /records/{recordId:int}", output);
        Assert.DoesNotContain("/records/87", output);
        Assert.DoesNotContain("do-not-log", output);
    }

    [Fact]
    public void FormatterSanitizesPipeAndNewlineCharacters()
    {
        var output = Format(RequestEvent((CompactLogProperties.RouteTemplate, "/unsafe|route\r\nnext")));
        var line = output.TrimEnd('\r', '\n');
        var fields = line.Split(" | ");

        Assert.Equal(7, fields.Length);
        Assert.DoesNotContain('\r', line);
        Assert.Equal(1, output.Count(character => character == '\n'));
        Assert.Contains("/unsafe_route__next", fields[2]);
    }

    [Fact]
    public void FormatterPreservesFullLengthCorrelationId()
    {
        var correlationId = Guid.NewGuid();
        var output = Format(RequestEvent((CompactLogProperties.CorrelationId, correlationId.ToString("D"))));

        Assert.Contains($" | {correlationId:D} | ", output);
        Assert.Equal(36, correlationId.ToString("D").Length);
    }

    [Fact]
    public void FormatterDoesNotWriteSensitiveProperties()
    {
        var output = Format(RequestEvent(
            ("Password", "password-secret"),
            ("AccessToken", "access-token-secret"),
            ("RefreshToken", "refresh-token-secret"),
            ("Authorization", "Bearer auth-secret"),
            ("Cookie", "cookie-secret"),
            ("Email", "person@example.com"),
            ("RequestPath", "/verify?token=verify-secret")));

        Assert.DoesNotContain("secret", output, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("person@example.com", output);
        Assert.DoesNotContain("verify?", output);
    }

    [Fact]
    public void FormatterWritesImportantProcessEventsAsCompactCorrelatedLines()
    {
        var correlationId = Guid.NewGuid();
        var output = Format(CreateEvent(LogEventLevel.Warning,
            (CompactLogProperties.IsImportantProcessEvent, true),
            (CompactLogProperties.Component, "EmailVerification"),
            (CompactLogProperties.CorrelationId, correlationId.ToString("D")),
            (CompactLogProperties.ResultCode, "SMTP_DELIVERY_FAILED")));
        var fields = output.TrimEnd('\r', '\n').Split(" | ");

        Assert.Equal(6, fields.Length);
        Assert.Equal("WARN", fields[1]);
        Assert.Equal("EVENT", fields[2]);
        Assert.Equal("EmailVerification", fields[3]);
        Assert.Equal(correlationId.ToString("D"), fields[4]);
        Assert.Equal("SMTP_DELIVERY_FAILED", fields[5]);
    }

    [Fact]
    public void FormatterUsesSafeFallbacksForInvalidProcessProperties()
    {
        var output = Format(CreateEvent(LogEventLevel.Error,
            (CompactLogProperties.IsImportantProcessEvent, true),
            (CompactLogProperties.Component, "Bad|Component\n"),
            (CompactLogProperties.CorrelationId, "not-a-guid"),
            (CompactLogProperties.ResultCode, "password=private")));
        var fields = output.TrimEnd('\r', '\n').Split(" | ");

        Assert.Equal(6, fields.Length);
        Assert.Equal("Bad_Component_", fields[3]);
        Assert.Equal("UNAVAILABLE", fields[4]);
        Assert.Equal("REQUEST_FAILED", fields[5]);
    }

    [Fact]
    public async Task CorrelationMiddlewarePreservesValidFullGuidAcrossRequestAndResponse()
    {
        var supplied = Guid.NewGuid();
        var context = new DefaultHttpContext();
        context.Request.Headers["X-Correlation-Id"] = supplied.ToString("D");
        var middleware = new CorrelationIdMiddleware(_ => Task.CompletedTask);

        await middleware.InvokeAsync(context);

        Assert.Equal(supplied, Assert.IsType<Guid>(context.Items[ApiHelpers.CorrelationItemKey]));
        Assert.Equal(supplied.ToString("D"), context.TraceIdentifier);
    }

    [Theory]
    [InlineData("bad")]
    [InlineData("00000000-0000-0000-0000-000000000000")]
    [InlineData("00000000-0000-0000-0000-000000000000,00000000-0000-0000-0000-000000000000")]
    [InlineData("00000000-0000-0000-0000-000000000000\r\nInjected: yes")]
    public async Task CorrelationMiddlewareReplacesInvalidOrOversizedIds(string invalidHeader)
    {
        var context = new DefaultHttpContext();
        context.Request.Headers["X-Correlation-Id"] = invalidHeader;

        await new CorrelationIdMiddleware(_ => Task.CompletedTask).InvokeAsync(context);

        var correlationId = Assert.IsType<Guid>(context.Items[ApiHelpers.CorrelationItemKey]);
        Assert.NotEqual(Guid.Empty, correlationId);
        Assert.Equal(36, correlationId.ToString("D").Length);
        Assert.Equal(correlationId.ToString("D"), context.TraceIdentifier);
    }

    [Theory]
    [InlineData("GET")]
    [InlineData("POST")]
    public async Task CompletionMiddlewareWritesOneEventForGetAndPost(string method)
    {
        var (context, logger) = await RunCompletion(method, StatusCodes.Status200OK);

        var entry = Assert.Single(logger.Entries);
        Assert.Equal(LogLevel.Information, entry.Level);
        Assert.Equal(method, Value<string>(entry, CompactLogProperties.HttpMethod));
        Assert.Equal(StatusCodes.Status200OK, Value<int>(entry, CompactLogProperties.HttpStatusCode));
        Assert.Equal(36, Value<string>(entry, CompactLogProperties.CorrelationId).Length);
        var correlationId = Assert.IsType<Guid>(context.Items[ApiHelpers.CorrelationItemKey]);
        Assert.Equal(correlationId.ToString("D"), Value<string>(entry, CompactLogProperties.CorrelationId));
    }

    [Theory]
    [InlineData(200, LogLevel.Information)]
    [InlineData(201, LogLevel.Information)]
    [InlineData(202, LogLevel.Information)]
    [InlineData(204, LogLevel.Information)]
    [InlineData(302, LogLevel.Information)]
    [InlineData(400, LogLevel.Warning)]
    [InlineData(401, LogLevel.Warning)]
    [InlineData(403, LogLevel.Warning)]
    [InlineData(404, LogLevel.Warning)]
    [InlineData(409, LogLevel.Warning)]
    [InlineData(422, LogLevel.Warning)]
    [InlineData(429, LogLevel.Warning)]
    [InlineData(500, LogLevel.Error)]
    [InlineData(503, LogLevel.Error)]
    public async Task CompletionLevelMatchesFinalHttpStatus(int statusCode, LogLevel expectedLevel)
    {
        var (_, logger) = await RunCompletion("GET", statusCode);

        Assert.Equal(expectedLevel, Assert.Single(logger.Entries).Level);
    }

    [Fact]
    public async Task CompletionUsesRegisterAcceptedResultCode()
    {
        var (_, logger) = await RunCompletion("POST", StatusCodes.Status202Accepted,
            "/api/v1/auth/register");

        Assert.Equal("REGISTER_ACCEPTED", Value<string>(Assert.Single(logger.Entries),
            CompactLogProperties.ResultCode));
    }

    [Fact]
    public void ExistingInvalidCredentialsErrorCodeIsRetainedForLogging()
    {
        var context = new DefaultHttpContext();
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;

        ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "INVALID_CREDENTIALS",
            "Email or password is incorrect.");

        Assert.Equal("INVALID_CREDENTIALS", CompactRequestLogPolicy.ResultCode(context));
    }

    [Fact]
    public async Task CompletionUsesUnmatchedRouteFallbackWithoutRawRequestPath()
    {
        var (_, logger) = await RunCompletion("GET", StatusCodes.Status404NotFound,
            routePattern: null, requestPath: "/users/991?access_token=secret");
        var entry = Assert.Single(logger.Entries);

        Assert.Equal("UNMATCHED_ROUTE", Value<string>(entry, CompactLogProperties.RouteTemplate));
        Assert.DoesNotContain(entry.Properties.Keys, key => key.Contains("Query", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain("secret", entry.Message);
    }

    [Fact]
    public async Task SuccessfulHealthCheckIsExcludedButFailedHealthCheckIsLogged()
    {
        var (_, successLogger) = await RunCompletion("GET", StatusCodes.Status200OK,
            "/health/live", metadata: [new RoutineHealthCheckLoggingMetadata()]);
        var (_, failureLogger) = await RunCompletion("GET", StatusCodes.Status503ServiceUnavailable,
            "/health/ready", metadata: [new RoutineHealthCheckLoggingMetadata()]);

        Assert.Empty(successLogger.Entries);
        var failure = Assert.Single(failureLogger.Entries);
        Assert.Equal(LogLevel.Error, failure.Level);
        Assert.Equal(StatusCodes.Status503ServiceUnavailable,
            Value<int>(failure, CompactLogProperties.HttpStatusCode));
    }

    [Fact]
    public async Task ExceptionMapperProducesSafe500BeforeCompletionIsLogged()
    {
        var correlationId = Guid.NewGuid();
        using var services = new ServiceCollection().AddLogging().BuildServiceProvider();
        var context = NewContext("GET", "/fault", "/fault", []);
        context.RequestServices = services;
        context.Items[ApiHelpers.CorrelationItemKey] = correlationId;
        var completionLogger = new RecordingLogger<CompactRequestCompletionLoggingMiddleware>();
        var exceptionLogger = new RecordingLogger<ApiExceptionHandlingMiddleware>();
        var exceptionHandler = new ApiExceptionHandlingMiddleware(
            _ => throw new InvalidOperationException("do-not-return-or-log-this-message"), exceptionLogger);
        var completion = new CompactRequestCompletionLoggingMiddleware(exceptionHandler.InvokeAsync, completionLogger);

        await completion.InvokeAsync(context);

        var completionEntry = Assert.Single(completionLogger.Entries);
        Assert.Equal(StatusCodes.Status500InternalServerError,
            Value<int>(completionEntry, CompactLogProperties.HttpStatusCode));
        Assert.Equal(LogLevel.Error, completionEntry.Level);
        Assert.Equal("INTERNAL_ERROR", Value<string>(completionEntry, CompactLogProperties.ResultCode));
        Assert.Contains(exceptionLogger.Entries, entry =>
            Value<bool>(entry, CompactLogProperties.IsImportantProcessEvent) &&
            Value<string>(entry, CompactLogProperties.ResultCode) == "INTERNAL_ERROR");
        Assert.DoesNotContain("do-not-return-or-log-this-message", exceptionLogger.Entries[0].Message);
        Assert.DoesNotContain("do-not-return-or-log-this-message", await ReadBody(context.Response));
    }

    [Fact]
    public async Task CompletionMiddlewareDoesNotEmitDuplicateEntries()
    {
        var (_, logger) = await RunCompletion("GET", StatusCodes.Status204NoContent);

        Assert.Single(logger.Entries);
    }

    [Fact]
    public void FileSettingsResolveRelativePathAndValidateLimits()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Logging:File:Path"] = "logs/log.txt",
            ["Logging:File:MaximumFileSizeBytes"] = "20971520",
            ["Logging:File:RetainedArchiveCount"] = "10"
        }).Build();

        var settings = CompactFileLogSettings.Load(configuration, root);

        Assert.Equal(Path.GetFullPath(Path.Combine(root, "logs", "log.txt")), settings.Path);
        Assert.Equal(20 * 1024 * 1024, settings.MaximumFileSizeBytes);
        Assert.Equal(10, settings.RetainedArchiveCount);
        var invalid = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Logging:File:Path"] = "logs/log.txt",
            ["Logging:File:MaximumFileSizeBytes"] = "0",
            ["Logging:File:RetainedArchiveCount"] = "10"
        }).Build();
        Assert.Throws<InvalidOperationException>(() => CompactFileLogSettings.Load(invalid, root));
    }

    [Fact]
    public async Task LocalHttpRequestWritesVerifiedCompactFileOutput()
    {
        var temporaryRoot = Path.Combine(Path.GetTempPath(), $"klop-compact-{Guid.NewGuid():N}");
        Directory.CreateDirectory(temporaryRoot);
        var logPath = Path.Combine(temporaryRoot, "logs", "log.txt");
        var loggerConfiguration = new LoggerConfiguration().MinimumLevel.Information();
        Assert.True(CompactFileLogSink.TryAdd(loggerConfiguration,
            new CompactFileLogSettings(logPath, 20 * 1024 * 1024, 10), _ => { }));
        var serilog = loggerConfiguration.CreateLogger();
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions
        {
            ContentRootPath = temporaryRoot,
            EnvironmentName = "Development"
        });
        builder.WebHost.ConfigureKestrel(options => options.Listen(IPAddress.Loopback, 0));
        builder.Host.UseSerilog(serilog, dispose: false);
        await using var app = builder.Build();
        app.UseRouting();
        app.UseMiddleware<CorrelationIdMiddleware>();
        app.UseMiddleware<CompactRequestCompletionLoggingMiddleware>();
        app.MapGet("/diagnostic/{recordId:int}", () => Results.Ok(new { okay = true }));

        try
        {
            await app.StartAsync();
            var address = app.Services.GetRequiredService<IServer>().Features
                .Get<IServerAddressesFeature>()!.Addresses.Single();
            using var client = new HttpClient();
            var correlationId = Guid.NewGuid();
            using var request = new HttpRequestMessage(HttpMethod.Get,
                $"{address}/diagnostic/123?token=do-not-write-this");
            request.Headers.Add("X-Correlation-Id", correlationId.ToString("D"));
            using var response = await client.SendAsync(request);
            await app.StopAsync();
            serilog.Dispose();

            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            Assert.Equal(correlationId.ToString("D"), response.Headers.GetValues("X-Correlation-Id").Single());
            Assert.True(File.Exists(logPath));
            var lines = await File.ReadAllLinesAsync(logPath);
            var line = Assert.Single(lines);
            var fields = line.Split(" | ");
            Assert.Equal(7, fields.Length);
            Assert.Equal("INFO", fields[1]);
            Assert.Equal("GET /diagnostic/{recordId:int}", fields[2]);
            Assert.Equal("200", fields[3]);
            Assert.Equal(correlationId.ToString("D"), fields[5]);
            Assert.Equal("REQUEST_SUCCESS", fields[6]);
            Assert.DoesNotContain("/diagnostic/123", line);
            Assert.DoesNotContain("do-not-write-this", line);
        }
        finally
        {
            await app.StopAsync();
            await app.DisposeAsync();
            serilog.Dispose();
            Directory.Delete(temporaryRoot, recursive: true);
        }
    }

    [Fact]
    public void ConcurrentFileSinkWritesRemainSeparateAndWellFormed()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"klop-concurrent-{Guid.NewGuid():N}");
        var path = Path.Combine(directory, "log.txt");
        var configuration = new LoggerConfiguration().MinimumLevel.Information();
        Assert.True(CompactFileLogSink.TryAdd(configuration,
            new CompactFileLogSettings(path, 20 * 1024 * 1024, 10), _ => { }));

        using (var logger = configuration.CreateLogger())
            Parallel.For(0, 100, _ => logger.Write(RequestEvent()));

        try
        {
            var lines = File.ReadAllLines(path);
            Assert.Equal(100, lines.Length);
            Assert.All(lines, line => Assert.Equal(7, line.Split(" | ").Length));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void FileSinkRollsBySizeAndRetainsOnlyConfiguredArchivesPlusCurrent()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"klop-roll-{Guid.NewGuid():N}");
        var path = Path.Combine(directory, "log.txt");
        var configuration = new LoggerConfiguration().MinimumLevel.Information();
        Assert.True(CompactFileLogSink.TryAdd(configuration,
            new CompactFileLogSettings(path, 500, 2), _ => { }));
        Assert.True(File.Exists(path));

        using (var logger = configuration.CreateLogger())
        {
            for (var index = 0; index < 30; index++)
                logger.Write(RequestEvent((CompactLogProperties.RouteTemplate, $"/{index:D3}/" + new string('a', 150))));
        }

        try
        {
            var files = Directory.GetFiles(directory, "log*.txt");
            Assert.InRange(files.Length, 2, 3);
            Assert.All(files, file =>
            {
                Assert.StartsWith("log", Path.GetFileName(file));
                Assert.EndsWith(".txt", file);
            });
            Assert.All(files, file => Assert.True(new FileInfo(file).Length <= 700));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void FileSinkFailureUsesSafeFallbackWithoutThrowing()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"klop-file-failure-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        var blocker = Path.Combine(directory, "not-a-directory");
        File.WriteAllText(blocker, "fixture");
        var configuration = new LoggerConfiguration();
        var reportedFailure = "";

        var result = CompactFileLogSink.TryAdd(configuration,
            new CompactFileLogSettings(Path.Combine(blocker, "log.txt"), 1024 * 1024, 1),
            failureType => reportedFailure = failureType);

        Assert.False(result);
        Assert.False(string.IsNullOrWhiteSpace(reportedFailure));
        Directory.Delete(directory, recursive: true);
    }

    private static async Task<(DefaultHttpContext Context, RecordingLogger<CompactRequestCompletionLoggingMiddleware> Logger)> RunCompletion(
        string method,
        int statusCode,
        string? routePattern = "/records/{recordId:int}",
        string requestPath = "/records/123?token=private",
        object[]? metadata = null)
    {
        var logger = new RecordingLogger<CompactRequestCompletionLoggingMiddleware>();
        var context = NewContext(method, requestPath, routePattern, metadata ?? []);
        var middleware = new CompactRequestCompletionLoggingMiddleware(_ =>
        {
            context.Response.StatusCode = statusCode;
            return Task.CompletedTask;
        }, logger);
        await middleware.InvokeAsync(context);
        return (context, logger);
    }

    private static DefaultHttpContext NewContext(string method, string requestPath, string? routePattern,
        object[] metadata)
    {
        var context = new DefaultHttpContext();
        context.Request.Method = method;
        var queryStart = requestPath.IndexOf('?');
        context.Request.Path = queryStart < 0 ? requestPath : requestPath[..queryStart];
        if (queryStart >= 0)
            context.Request.QueryString = new QueryString(requestPath[queryStart..]);
        if (routePattern is not null)
            context.SetEndpoint(CreateEndpoint(routePattern, metadata));
        context.Items[ApiHelpers.CorrelationItemKey] = Guid.NewGuid();
        return context;
    }

    private static RouteEndpoint CreateEndpoint(string template, object[] metadata) =>
        new(_ => Task.CompletedTask, RoutePatternFactory.Parse(template), 0,
            new EndpointMetadataCollection(metadata), template);

    private static LogEvent RequestEvent(params (string Name, object? Value)[] overrides)
    {
        var properties = new Dictionary<string, object?>
        {
            [CompactLogProperties.IsRequestCompletion] = true,
            [CompactLogProperties.SuppressFileLog] = false,
            [CompactLogProperties.HttpMethod] = "GET",
            [CompactLogProperties.RouteTemplate] = "/records/{recordId:int}",
            [CompactLogProperties.HttpStatusCode] = 202,
            [CompactLogProperties.DurationMs] = 135.2,
            [CompactLogProperties.CorrelationId] = Guid.NewGuid().ToString("D"),
            [CompactLogProperties.ResultCode] = "REQUEST_SUCCESS"
        };
        foreach (var (name, value) in overrides)
            properties[name] = value;
        return CreateEvent(LogEventLevel.Information, properties.Select(pair => (pair.Key, pair.Value)).ToArray());
    }

    private static LogEvent CreateEvent(LogEventLevel level, params (string Name, object? Value)[] properties) =>
        new(EventTimestamp, level, null, new MessageTemplateParser().Parse("test"),
            properties.Select(pair => new LogEventProperty(pair.Name, new ScalarValue(pair.Value))));

    private static string Format(LogEvent logEvent)
    {
        using var writer = new StringWriter(CultureInfo.InvariantCulture);
        new CompactLogFormatter().Format(logEvent, writer);
        return writer.ToString();
    }

    private static T Value<T>(CapturedLog entry, string name) => (T)entry.Properties[name]!;

    private static async Task<string> ReadBody(HttpResponse response)
    {
        response.Body.Position = 0;
        using var reader = new StreamReader(response.Body);
        return await reader.ReadToEndAsync();
    }

    private sealed record CapturedLog(
        LogLevel Level,
        string Message,
        IReadOnlyDictionary<string, object?> Properties);

    private sealed class RecordingLogger<T> : ILogger<T>
    {
        public List<CapturedLog> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            var properties = state is IEnumerable<KeyValuePair<string, object?>> pairs
                ? pairs.Where(pair => pair.Key != "{OriginalFormat}")
                    .ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.Ordinal)
                : new Dictionary<string, object?>();
            Entries.Add(new CapturedLog(logLevel, formatter(state, exception), properties));
        }
    }
}