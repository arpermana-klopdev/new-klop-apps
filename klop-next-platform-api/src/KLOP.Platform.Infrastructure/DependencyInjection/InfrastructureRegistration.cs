using KLOP.Platform.Application;
using Microsoft.Extensions.DependencyInjection;

namespace KLOP.Platform.Infrastructure;

public static class InfrastructureRegistration
{
    public static IServiceCollection AddPlatformInfrastructure(
        this IServiceCollection services,
        SqlConnectionFactory connectionFactory,
        RuntimeSettings runtimeSettings,
        IKeyVaultSecrets keyVaultSecrets,
        KeyMaterial keyMaterial)
    {
        services.AddSingleton(connectionFactory);
        services.AddSingleton(runtimeSettings);
        services.AddSingleton<IPlatformRuntimeSettings>(runtimeSettings);
        services.AddSingleton<IPasswordPolicy>(runtimeSettings);
        services.AddSingleton(keyVaultSecrets);
        services.AddSingleton(keyMaterial);
        services.AddSingleton<TokenIssuer>();
        services.AddSingleton<IAccessTokenIssuer>(provider => provider.GetRequiredService<TokenIssuer>());
        services.AddScoped<IPlatformRepository, KlopRepository>();
        services.AddScoped<ITenantPermissionRepository>(provider =>
            provider.GetRequiredService<IPlatformRepository>());
        services.AddScoped<IRegistrationRepository, KlopRepository>();
        services.AddScoped<IPlatformRegistrationRepository, KlopRepository>();
        services.AddScoped<IPlatformPermissionRepository, KlopRepository>();
        services.AddScoped<IRolePermissionMatrixRepository, KlopRepository>();
        services.AddScoped<ILegalDocumentsRepository, KlopRepository>();
        services.AddScoped<INotificationManagementRepository, KlopRepository>();
        services.AddScoped<ISystemConfigurationRepository, KlopRepository>();
        services.AddSingleton<ISmtpMailTransport, SmtpMailTransport>();
        services.AddSingleton<ILegalDocumentStorage, FileSystemLegalDocumentStorage>();
        services.AddTransient<IVerificationEmailSender, SmtpVerificationEmailSender>();
        return services;
    }
}