using System.Text.RegularExpressions;

namespace KLOP.Platform.Application;

public sealed record RenderedNotification(string Subject, string Body);

public static partial class NotificationTemplateRenderer
{
    private static readonly IReadOnlyDictionary<string, string> PreviewValues =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["verification_link"] = "https://preview.invalid/verify-email#userId=0&token=PREVIEW_ONLY",
            ["expiry_hours"] = "24"
        };

    public static RenderedNotification Preview(string subject, string body) =>
        Render(subject, body, PreviewValues);

    public static RenderedNotification RenderVerification(string subject, string body,
        string verificationLink, int expiryHours)
    {
        if (!Uri.TryCreate(verificationLink, UriKind.Absolute, out var link) ||
            link.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(link.UserInfo) ||
            verificationLink.Contains('\r') || verificationLink.Contains('\n'))
            throw new ArgumentException("The verification link must be a safe HTTPS URL.", nameof(verificationLink));
        if (expiryHours is < 1 or > 24)
            throw new ArgumentOutOfRangeException(nameof(expiryHours));

        return Render(subject, body, new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["verification_link"] = link.AbsoluteUri,
            ["expiry_hours"] = expiryHours.ToString(System.Globalization.CultureInfo.InvariantCulture)
        });
    }

    private static RenderedNotification Render(string subject, string body,
        IReadOnlyDictionary<string, string> values)
    {
        if (string.IsNullOrWhiteSpace(subject) || subject.Length > 300 ||
            subject.Contains('\r') || subject.Contains('\n') || subject.Contains('\0'))
            throw new ArgumentException("The notification subject is invalid.", nameof(subject));
        if (string.IsNullOrWhiteSpace(body) || body.Length > 20_000 || body.Contains('\0'))
            throw new ArgumentException("The plain-text notification body is invalid.", nameof(body));

        var matches = PlaceholderPattern().Matches(subject + "\n" + body);
        var names = matches.Select(match => match.Groups[1].Value).ToHashSet(StringComparer.Ordinal);
        if (names.Any(name => !values.ContainsKey(name)))
            throw new ArgumentException("The template contains an unsupported variable.", nameof(body));
        var unresolved = PlaceholderPattern().Replace(subject + "\n" + body, "");
        if (unresolved.Contains("{{", StringComparison.Ordinal) ||
            unresolved.Contains("}}", StringComparison.Ordinal))
            throw new ArgumentException("The template contains a malformed variable.", nameof(body));
        if (!names.Contains("verification_link") || !names.Contains("expiry_hours"))
            throw new ArgumentException("The template is missing a required variable.", nameof(body));

        string Replace(string value) => PlaceholderPattern().Replace(value, match =>
            values.TryGetValue(match.Groups[1].Value, out var replacement)
                ? replacement
                : throw new ArgumentException("The template contains an unsupported variable.", nameof(body)));

        return new RenderedNotification(Replace(subject), Replace(body));
    }

    [GeneratedRegex(@"\{\{([a-z][a-z0-9_]*)\}\}", RegexOptions.CultureInvariant)]
    private static partial Regex PlaceholderPattern();
}
