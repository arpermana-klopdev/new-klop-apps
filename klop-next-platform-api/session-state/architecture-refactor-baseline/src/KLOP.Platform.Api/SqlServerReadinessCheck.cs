using KLOP.Platform.Application;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace KLOP.Platform.Api;

public sealed class SqlServerReadinessCheck(
    IPlatformRepository repository,
    ILogger<SqlServerReadinessCheck> logger) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await repository.CheckDatabase(cancellationToken);
            return HealthCheckResult.Healthy();
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            logger.LogWarning("SQL readiness probe failed. FailureType={FailureType}", exception.GetType().Name);
            return HealthCheckResult.Unhealthy();
        }
    }
}
