using System.Security.Cryptography;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class InfrastructureRegistrationTests
{
    [Fact]
    public void InfrastructureRegistrationResolvesTheRepositoryWithoutOpeningSqlConnections()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection().Build();
        var connectionFactory = new SqlConnectionFactory(configuration);
        var runtimeSettings = new RuntimeSettings(
            "https://issuer.example", "klop-test", "https://app.example", 15, 30, 5, 12, 24, 30, 30,
            "smtp.example", 25, "no-reply@example.com", true, null, null, null);
        var keyVaultSecrets = new KeyVaultSecrets(configuration);
        var keyMaterial = new KeyMaterial(RSA.Create(3072), "di-test");
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<IHostEnvironment>(new TestHostEnvironment());
        services.AddPlatformInfrastructure(connectionFactory, runtimeSettings, keyVaultSecrets, keyMaterial);
        services.AddSingleton<PasswordCodec>();
        services.AddScoped<AuthenticationService>();

        using var provider = services.BuildServiceProvider();
        using var scope = provider.CreateScope();

        Assert.IsType<KlopRepository>(scope.ServiceProvider.GetRequiredService<IPlatformRepository>());
        Assert.IsType<AuthenticationService>(scope.ServiceProvider.GetRequiredService<AuthenticationService>());
        Assert.IsType<TokenIssuer>(scope.ServiceProvider.GetRequiredService<IAccessTokenIssuer>());
        Assert.Same(runtimeSettings, scope.ServiceProvider.GetRequiredService<IPlatformRuntimeSettings>());
        Assert.Same(runtimeSettings, provider.GetRequiredService<RuntimeSettings>());
        Assert.Same(connectionFactory, provider.GetRequiredService<SqlConnectionFactory>());
    }

    private sealed class TestHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = Environments.Development;
        public string ApplicationName { get; set; } = "KLOP.Platform.UnitTests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}