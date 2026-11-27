using KLOP.Platform.Api;
using KLOP.Platform.Application;
using KLOP.Platform.Api.Logging;

namespace KLOP.Platform.Api.Bootstrap;

public static class RequestPipeline
{
    public static void UsePlatformRequestPipeline(this WebApplication app, IHostEnvironment environment)
    {
        app.UseForwardedHeaders();
        app.UseMiddleware<CorrelationIdMiddleware>();
        app.UseMiddleware<CompactRequestCompletionLoggingMiddleware>();
        app.UseMiddleware<ApiExceptionHandlingMiddleware>();
        app.UseStatusCodePages(async statusContext =>
        {
            var context = statusContext.HttpContext;
            var status = context.Response.StatusCode;
            var (code, message) = status switch
            {
                StatusCodes.Status404NotFound => ("NOT_FOUND", "The requested resource was not found."),
                StatusCodes.Status405MethodNotAllowed => ("METHOD_NOT_ALLOWED", "The HTTP method is not supported."),
                _ => ("REQUEST_FAILED", "The request could not be completed.")
            };
            await ApiHelpers.Error(context, status, code, message).ExecuteAsync(context);
        });
        app.Use(async (context, next) =>
        {
            context.Response.OnStarting(() =>
            {
                context.Response.Headers["X-Content-Type-Options"] = "nosniff";
                context.Response.Headers["X-Frame-Options"] = "DENY";
                context.Response.Headers["Referrer-Policy"] = "no-referrer";
                context.Response.Headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()";
                return Task.CompletedTask;
            });
            await next();
        });
        if (environment.IsProduction())
            app.UseHsts();
        app.UseHttpsRedirection();
        app.UseRouting();
        app.UseCors("spa");
        app.UseRateLimiter();
        app.UseAuthentication();
        app.UseAuthorization();

        if (environment.IsDevelopment())
        {
            app.MapOpenApi();
            app.UseSwaggerUI(options => options.SwaggerEndpoint("../openapi/v1.json", "KLOP Platform API v1"));
        }
    }
}