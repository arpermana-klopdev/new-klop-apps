using System.Globalization;
using System.Security.Cryptography;

namespace KLOP.Platform.Application;

// PBKDF2-HMAC-SHA256, random salt, versioned storage format. No password/hash logging.
public sealed class PasswordCodec
{
    private const int Iterations = 600_000;
    private const int MinimumPasswordLength = 12;

    public string Hash(string password, int minimumLength = MinimumPasswordLength)
    {
        if (minimumLength is < MinimumPasswordLength or > 128)
            throw new ArgumentOutOfRangeException(nameof(minimumLength));
        if (string.IsNullOrWhiteSpace(password) || password.Length < minimumLength || password.Length > 128)
            throw new ArgumentException($"Password length must be {minimumLength}..128 characters.", nameof(password));
        var salt = RandomNumberGenerator.GetBytes(32);
        var digest = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, 32);
        return $"pbkdf2-sha256${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(digest)}";
    }
    public bool Verify(string password, string? encoded)
    {
        if (string.IsNullOrEmpty(password) || string.IsNullOrWhiteSpace(encoded)) return false;
        try
        {
            var parts = encoded.Split('$');
            if (parts.Length != 4 || parts[0] != "pbkdf2-sha256") return false;
            if (!int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var rounds)
                 || rounds < 100_000 || rounds > 1_500_000) return false;
            var salt = Convert.FromBase64String(parts[2]);
            var expected = Convert.FromBase64String(parts[3]);
            if (salt.Length != 32 || expected.Length != 32) return false;
            var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, rounds, HashAlgorithmName.SHA256, 32);
            return CryptographicOperations.FixedTimeEquals(actual, expected);
        }
        catch (FormatException) { return false; }
        catch (ArgumentException) { return false; }
    }
}
public static class SecretTokens
{
    public static string NewToken() => Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
    public static byte[] Sha256(string token) => SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(token));
    private static string Base64UrlEncode(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    public static string NormalizeEmail(string email) => email.Trim().ToUpperInvariant();
}
public static class UserInput
{
    public static bool EmailOkay(string email)
    {
        if (string.IsNullOrWhiteSpace(email) || email.Length > 320) return false;
        try
        {
            var parsed = new System.Net.Mail.MailAddress(email.Trim());
            return string.Equals(parsed.Address, email.Trim(), StringComparison.OrdinalIgnoreCase);
        }
        catch (FormatException) { return false; }
    }
}
