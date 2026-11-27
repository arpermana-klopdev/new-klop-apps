using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using KLOP.Platform.Api.Logging;
using Serilog.Debugging;
using Serilog;

namespace KLOP.Platform.Api.Bootstrap;

public static class ObservabilityRegistration
{
    public static void AddPlatformObservability(this WebApplicationBuilder builder)
    {
        SelfLog.Enable(TextWriter.Synchronized(Console.Error));
        CompactFileLogSettings? fileSettings = null;
        try
        {
            fileSettings = CompactFileLogSettings.Load(builder.Configuration, builder.Environment.ContentRootPath);
        }
        catch (Exception)
        {
            CompactLoggingFallback.Report("FILE_LOGGING_UNAVAILABLE");
        }
        builder.Host.UseSerilog((context, services, logger) =>
        {
            var configuredLogger = logger
                .ReadFrom.Configuration(context.Configuration)
                .ReadFrom.Services(services)
                .Enrich.FromLogContext()
                .Enrich.WithProperty("Application", "KLOP.Platform.Api")
                .Enrich.WithProperty("Environment", context.HostingEnvironment.EnvironmentName)
                .WriteTo.Console(outputTemplate:
                    "[{Timestamp:yyyy-MM-ddTHH:mm:ss.fff}Z {Level:u3}] {Message:lj} {CorrelationId}{NewLine}{Exception}");
            if (fileSettings is not null)
                CompactFileLogSink.TryAdd(configuredLogger, fileSettings,
                    _ => CompactLoggingFallback.Report("FILE_LOGGING_UNAVAILABLE"));
        });

        var openTelemetry = builder.Services.AddOpenTelemetry()
            .ConfigureResource(resource => resource.AddService("KLOP.Platform.Api"))
            .WithTracing(tracing => tracing
                .AddAspNetCoreInstrumentation(options => options.RecordException = false)
                .AddHttpClientInstrumentation(options => options.RecordException = false)
                .AddSqlClientInstrumentation(options => options.RecordException = false))
            .WithMetrics(metrics => metrics
                .AddAspNetCoreInstrumentation()
                .AddHttpClientInstrumentation());

        if (!string.IsNullOrWhiteSpace(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]))
        {
            openTelemetry.WithTracing(tracing => tracing.AddOtlpExporter());
            openTelemetry.WithMetrics(metrics => metrics.AddOtlpExporter());
        }
    }
}