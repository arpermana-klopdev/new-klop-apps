using KLOP.Platform.Application;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class NotificationTemplateRendererTests
{
    private const string Subject = "Verify your KLOP account";
    private const string Body = "Open {{verification_link}}. The link expires in {{expiry_hours}} hours.";

    [Fact]
    public void PreviewUsesOnlySyntheticVerificationValues()
    {
        var result = NotificationTemplateRenderer.Preview(Subject, Body);

        Assert.Contains("https://preview.invalid/", result.Body, StringComparison.Ordinal);
        Assert.Contains("token=PREVIEW_ONLY", result.Body, StringComparison.Ordinal);
        Assert.Contains("24 hours", result.Body, StringComparison.Ordinal);
    }

    [Fact]
    public void RenderVerificationAcceptsOnlyHttpsLinksAndBoundedExpiry()
    {
        var result = NotificationTemplateRenderer.RenderVerification(
            Subject, Body, "https://app.example.test/verify-email#token=sample", 4);

        Assert.Contains("https://app.example.test/verify-email#token=sample", result.Body, StringComparison.Ordinal);
        Assert.Contains("4 hours", result.Body, StringComparison.Ordinal);
        Assert.Throws<ArgumentException>(() =>
            NotificationTemplateRenderer.RenderVerification(Subject, Body, "http://example.test/x", 4));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            NotificationTemplateRenderer.RenderVerification(Subject, Body, "https://example.test/x", 0));
    }

    [Theory]
    [InlineData("Verify your account", "{{verification_link}}")]
    [InlineData("{{verification_link}}", "This template omits the expiry value.")]
    [InlineData("Verify\r\nBcc: attacker@example.test", Body)]
    [InlineData("{{verification_link}}", "{{unknown_value}} {{expiry_hours}}")]
    public void PreviewRejectsMissingUnknownOrHeaderInjection(string subject, string body)
    {
        Assert.Throws<ArgumentException>(() => NotificationTemplateRenderer.Preview(subject, body));
    }

    [Fact]
    public void RenderedSubjectRemainsWithinHeaderAndLengthLimits()
    {
        var subject = new string('a', 280) + "{{expiry_hours}}";
        var rendered = NotificationTemplateRenderer.RenderVerification(
            subject, Body, "https://app.example.test/verify-email", 24);
        Assert.True(rendered.Subject.Length <= 300);
        Assert.DoesNotContain('\r', rendered.Subject);
        Assert.DoesNotContain('\n', rendered.Subject);
    }

    [Fact]
    public void ExpiryMayBeRenderedInSubjectButVerificationLinkMayNot()
    {
        var result = NotificationTemplateRenderer.RenderVerification(
            "Verify within {{expiry_hours}} hours", Body, "https://app.example.test/verify-email", 4);

        Assert.Equal("Verify within 4 hours", result.Subject);
        Assert.Throws<ArgumentException>(() => NotificationTemplateRenderer.RenderVerification(
            "{{verification_link}}", Body, "https://app.example.test/verify-email", 4));
    }

    [Fact]
    public void PreviewUsesOrdinalPlaceholderNames()
    {
        Assert.Throws<ArgumentException>(() => NotificationTemplateRenderer.Preview(
            Subject, "{{Verification_link}} {{expiry_hours}}"));
    }
}
