using System.Security.Cryptography;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using KLOP.Platform.Infrastructure;
using Microsoft.IdentityModel.Tokens;

namespace KLOP.Platform.Api;

public sealed class KeyMaterial(RSA rsa, string keyId)
{
    public RSA Rsa { get; } = rsa;
    public RsaSecurityKey SigningKey { get; } = new RsaSecurityKey(rsa) { KeyId = keyId };
    public object PublicJwks()
    {
        var pk = rsa.ExportParameters(false);
        string Url(byte[] bytes) => Base64UrlEncoder.Encode(bytes);
        return new { keys = new[] { new { kty = "RSA", use = "sig", alg = "RS256", kid = keyId,
                     n = Url(pk.Modulus!), e = Url(pk.Exponent!) } } };
    }
    public static async Task<KeyMaterial> Load(IConfiguration cfg, IHostEnvironment env, RuntimeSettings settings)
    {
        if (env.IsDevelopment() && string.IsNullOrWhiteSpace(cfg["KeyVault:VaultUri"]))
        {
            // Development only; ephemeral JWT signatures invalidate tokens on restart.
            return new KeyMaterial(RSA.Create(3072), "development-ephemeral");
        }
        var uri = cfg["KeyVault:VaultUri"];
        var name = settings.SigningKeyReference;
        if (string.IsNullOrWhiteSpace(uri) || string.IsNullOrWhiteSpace(name))
            throw new InvalidOperationException("Key Vault signing key reference is required.");
        var client = new SecretClient(new Uri(uri), new DefaultAzureCredential());
        var secret = (await client.GetSecretAsync(name)).Value;
        var rsa = RSA.Create();
        rsa.ImportFromPem(secret.Value);
        if (rsa.KeySize < 3072) throw new InvalidOperationException("RSA signing key too small.");
        return new KeyMaterial(rsa, secret.Properties.Version ?? name);
    }
}
