using System.Security.Cryptography;
using KLOP.Platform.Application;
using Microsoft.IdentityModel.Tokens;

namespace KLOP.Platform.Api;

public sealed class KeyMaterial(RSA rsa, string keyId) : IDisposable
{
    public RsaSecurityKey SigningKey { get; } = new(rsa) { KeyId = keyId };

    public object PublicJwks()
    {
        var parameters = rsa.ExportParameters(false);
        return new
        {
            keys = new[]
            {
                new
                {
                    kty = "RSA",
                    use = "sig",
                    alg = "RS256",
                    kid = keyId,
                    n = Base64UrlEncoder.Encode(parameters.Modulus ??
                        throw new CryptographicException("RSA modulus is unavailable.")),
                    e = Base64UrlEncoder.Encode(parameters.Exponent ??
                        throw new CryptographicException("RSA exponent is unavailable."))
                }
            }
        };
    }

    public static async Task<KeyMaterial> Load(
        IConfiguration configuration,
        IHostEnvironment environment,
        IPlatformRuntimeSettings settings,
        IKeyVaultSecrets secrets,
        CancellationToken cancellationToken)
    {
        if (environment.IsDevelopment() && string.IsNullOrWhiteSpace(configuration["KeyVault:VaultUri"]))
            return new KeyMaterial(RSA.Create(3072), "development-ephemeral");

        if (string.IsNullOrWhiteSpace(settings.SigningKeyReference))
            throw new InvalidOperationException("A Key Vault signing-key reference is required.");

        var secret = await secrets.Get(settings.SigningKeyReference, cancellationToken);
        var rsa = RSA.Create();
        try
        {
            rsa.ImportFromPem(secret.Value);
            if (rsa.KeySize < 3072 || rsa.ExportParameters(true).D is null)
                throw new InvalidOperationException("The Key Vault RSA signing key must be private and at least 3072 bits.");
            return new KeyMaterial(rsa, secret.Version ?? settings.SigningKeyReference);
        }
        catch
        {
            rsa.Dispose();
            throw;
        }
    }

    public void Dispose() => rsa.Dispose();
}
