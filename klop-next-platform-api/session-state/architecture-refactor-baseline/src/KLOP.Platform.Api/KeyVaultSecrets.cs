using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

namespace KLOP.Platform.Api;

public sealed record KeyVaultSecretValue(string Value, string? Version);

public interface IKeyVaultSecrets
{
    Task<KeyVaultSecretValue> Get(string secretName, CancellationToken cancellationToken);
}

public sealed class KeyVaultSecrets(IConfiguration configuration) : IKeyVaultSecrets
{
    private readonly Lazy<SecretClient> _client = new(() =>
    {
        var vaultUri = configuration["KeyVault:VaultUri"];
        if (!Uri.TryCreate(vaultUri, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
            throw new InvalidOperationException("A valid HTTPS Key Vault URI is required to read secrets.");
        return new SecretClient(uri, new DefaultAzureCredential());
    }, LazyThreadSafetyMode.ExecutionAndPublication);

    public async Task<KeyVaultSecretValue> Get(string secretName, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(secretName))
            throw new ArgumentException("A Key Vault secret name is required.", nameof(secretName));
        var secret = (await _client.Value.GetSecretAsync(secretName, cancellationToken: cancellationToken)).Value;
        return new KeyVaultSecretValue(secret.Value, secret.Properties.Version);
    }
}
