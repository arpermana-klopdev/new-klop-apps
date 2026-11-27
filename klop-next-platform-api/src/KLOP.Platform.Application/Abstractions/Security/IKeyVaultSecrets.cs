namespace KLOP.Platform.Application;

public sealed record KeyVaultSecretValue(string Value, string? Version);

public interface IKeyVaultSecrets
{
    Task<KeyVaultSecretValue> Get(string secretName, CancellationToken cancellationToken);
}