using System.Globalization;
using System.Security.Cryptography;

namespace KLOP.Platform.Application;

public static class RegistrationLimits
{
    public const int MaxPasswordLength = 128;
}

// PBKDF2-HMAC-SHA256, random salt, versioned storage format. No password/hash logging.
public sealed class PasswordCodec
{
    private const int Iterations = 600_000;
    private const int MinimumIterations = 100_000;
    private const int MaximumIterations = 1_500_000;
    private const int LegacyIterations = 100_000;
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
            int rounds;
            int saltLength;
            string saltText;
            string digestText;

            if (encoded.Contains('$'))
            {
                var parts = encoded.Split('$');
                if (parts.Length != 4 || parts[0] != "pbkdf2-sha256" ||
                    !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out rounds) ||
                    rounds < MinimumIterations || rounds > MaximumIterations ||
                    parts[1] != rounds.ToString(CultureInfo.InvariantCulture))
                    return false;

                saltLength = 32;
                saltText = parts[2];
                digestText = parts[3];
            }
            else if (encoded.Contains('.'))
            {
                var parts = encoded.Split('.');
                if (parts.Length != 3 || parts[0] != LegacyIterations.ToString(CultureInfo.InvariantCulture) ||
                    !int.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out rounds) ||
                    rounds != LegacyIterations)
                    return false;

                saltLength = 16;
                saltText = parts[1];
                digestText = parts[2];
            }
            else
            {
                return false;
            }

            if (saltText.Length != ((saltLength + 2) / 3) * 4 || digestText.Length != 44)
                return false;

            var salt = DecodeCanonicalBase64(saltText);
            var expected = DecodeCanonicalBase64(digestText);
            if (salt is null || expected is null || salt.Length != saltLength || expected.Length != 32)
                return false;

            var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, rounds, HashAlgorithmName.SHA256, 32);
            return CryptographicOperations.FixedTimeEquals(actual, expected);
        }
        catch (FormatException) { return false; }
        catch (ArgumentException) { return false; }
    }

    private static byte[]? DecodeCanonicalBase64(string encoded)
    {
        var decoded = Convert.FromBase64String(encoded);
        return Convert.ToBase64String(decoded) == encoded ? decoded : null;
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
