using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using System.Text.Json;
using Xunit;

namespace KLOP.Platform.UnitTests;
public sealed class SecurityTests
{
    private const string LegacyPassword = "KLOP-Legacy-Test-Only!";
    private const string LegacyHash = "100000.AAECAwQFBgcICQoLDA0ODw==.H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c=";
    private readonly PasswordCodec _codec=new();
    [Fact] public void PasswordRoundTrip()
    {
        var encoded=_codec.Hash("SafeDevelopmentPassword+456");
        Assert.StartsWith("pbkdf2-sha256$",encoded);
        Assert.True(_codec.Verify("SafeDevelopmentPassword+456",encoded));
        Assert.False(_codec.Verify("wrong password",encoded));
    }
    [Fact] public void SaltIsRandom()
    {
        Assert.NotEqual(_codec.Hash("SafeDevelopmentPassword+456"), _codec.Hash("SafeDevelopmentPassword+456"));
    }
    [Theory]
    [InlineData("")]
    [InlineData("short")]
    [InlineData("password123")]
    public void WeakLengthRejected(string password)
    {
        Assert.Throws<ArgumentException>(()=>_codec.Hash(password));
    }
    [Fact] public void MalformedPasswordHashRejected()
    {
        Assert.False(_codec.Verify("SafeDevelopmentPassword+456","pbkdf2-sha256$600000$AA==$AA=="));
        Assert.False(_codec.Verify("SafeDevelopmentPassword+456","nonsense"));
    }
    [Fact] public void VerifiedLegacyPasswordHashIsAccepted()
    {
        Assert.True(_codec.Verify(LegacyPassword, LegacyHash));
        Assert.False(_codec.Verify("wrong password", LegacyHash));
    }
    [Fact] public void InvalidIterationCountsAreRejected()
    {
        Assert.False(_codec.Verify(LegacyPassword,
            "99999.AAECAwQFBgcICQoLDA0ODw==.H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
        Assert.False(_codec.Verify(LegacyPassword,
            "100001.AAECAwQFBgcICQoLDA0ODw==.H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
        Assert.False(_codec.Verify("SafeDevelopmentPassword+456",
            "pbkdf2-sha256$99999$AAECAwQFBgcICQoLDA0ODw==$H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
        Assert.False(_codec.Verify("SafeDevelopmentPassword+456",
            "pbkdf2-sha256$1500001$AAECAwQFBgcICQoLDA0ODw==$H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
    }
    [Fact] public void InvalidBase64IsRejected()
    {
        Assert.False(_codec.Verify(LegacyPassword, "100000.invalid.H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
        Assert.False(_codec.Verify("SafeDevelopmentPassword+456", "pbkdf2-sha256$600000$invalid$AA=="));
    }
    [Fact] public void NonCanonicalBase64IsRejected()
    {
        Assert.False(_codec.Verify(LegacyPassword,
            "100000.AAECAwQFBgcICQoLDA0ODw==\n.H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
    }
    [Fact] public void InvalidSaltAndDigestLengthsAreRejected()
    {
        Assert.False(_codec.Verify(LegacyPassword, "100000.AAECAwQFBgc=.H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
        Assert.False(_codec.Verify(LegacyPassword, "100000.AAECAwQFBgcICQoLDA0ODw==.AAECAwQFBgcICQoLDA0ODw=="));
        Assert.False(_codec.Verify("SafeDevelopmentPassword+456",
            "pbkdf2-sha256$600000$AAECAwQFBgcICQoLDA0ODw==$H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
        Assert.False(_codec.Verify("SafeDevelopmentPassword+456",
            "pbkdf2-sha256$600000$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=$AAECAwQFBgcICQoLDA0ODw=="));
    }
    [Fact] public void UnsupportedOrNonCanonicalFormatsAreRejected()
    {
        Assert.False(_codec.Verify(LegacyPassword,
            "1000000.AAECAwQFBgcICQoLDA0ODw==.H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
        Assert.False(_codec.Verify("SafeDevelopmentPassword+456",
            "PBKDF2-SHA256$600000$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=$H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
        Assert.False(_codec.Verify("SafeDevelopmentPassword+456",
            "pbkdf2-sha512$600000$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=$H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
        Assert.False(_codec.Verify(LegacyPassword,
            "0100000.AAECAwQFBgcICQoLDA0ODw==.H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c="));
        Assert.False(_codec.Verify(LegacyPassword, LegacyHash.Replace('.', '$')));
        Assert.False(_codec.Verify(LegacyPassword, LegacyHash + ".extra"));
    }
    [Fact] public void EmptyAndNullHashesAreRejected()
    {
        Assert.False(_codec.Verify(LegacyPassword, ""));
        Assert.False(_codec.Verify(LegacyPassword, null));
    }
    [Fact] public void RandomVerificationTokensAreDistinct()
    {
        var a=SecretTokens.NewToken();var b=SecretTokens.NewToken();
        Assert.NotEqual(a,b);
        Assert.Equal(32,SecretTokens.Sha256(a).Length);
        Assert.NotEqual(Convert.ToHexString(SecretTokens.Sha256(a)),Convert.ToHexString(SecretTokens.Sha256(b)));
    }
    [Fact] public void ConfiguredMinimumPasswordLengthIsApplied()
    {
        Assert.Throws<ArgumentException>(() => _codec.Hash("TwelveChars!", 14));
        Assert.StartsWith("pbkdf2-sha256$", _codec.Hash("FourteenChars!", 14));
    }
    [Fact] public void RegistrationValidationUsesConfiguredPasswordPolicy()
    {
        var settings = new RuntimeSettings(
            "https://issuer.example", "klop-test", "https://app.example", 15, 30, 5, 14, 24, 30, 30,
            "smtp.example", 25, "no-reply@example.com", true, null, null, null);
        var validator = new RegistrationRequestValidator(settings);
        var result = validator.Validate(new RegistrationRequest(
            "valid@example.com", "A valid user", "TwelveChars!")
        {
            RegistrationType = "PERSONAL",
            TermsDocumentVersionId = Guid.NewGuid(),
            TermsAccepted = true
        });
        Assert.Contains(result.Errors, error => error.PropertyName == nameof(RegistrationRequest.Password));
    }
    [Fact] public void TenantValidationRequiresOrganizationFieldsTogether()
    {
        var validator = new TenantCreateRequestValidator();
        var result = validator.Validate(new TenantCreateRequest(
            "ORG-001", "ORGANIZATION", "Organization", 17, null));
        Assert.Contains(result.Errors, error => error.PropertyName == "");
    }
    [Theory]
    [InlineData("hello@example.com",true)]
    [InlineData("bad",false)]
    [InlineData("",false)]
    public void EmailValidation(string email,bool expected) => Assert.Equal(expected,UserInput.EmailOkay(email));

    [Fact] public void EmailNormalizationTrimsAndUsesInvariantUppercase() =>
        Assert.Equal("USER@EXAMPLE.COM", SecretTokens.NormalizeEmail(" user@example.com "));

    [Fact] public void DirectRegistrationRequestContainsOnlyTheFourDevelopmentFields()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var request = JsonSerializer.Deserialize<DirectRegistrationRequest>(
            """{"email":"user@example.com","displayName":"User Name","password":"StrongPassword!456","registrationType":"PERSONAL"}""",
            options);

        Assert.Equal("User Name", request?.DisplayName);
        var serialized = JsonSerializer.Serialize(request, options);
        using var document = JsonDocument.Parse(serialized);
        Assert.Equal("User Name", document.RootElement.GetProperty("displayName").GetString());
        Assert.Equal(
            ["displayName", "email", "password", "registrationType"],
            document.RootElement.EnumerateObject().Select(property => property.Name).Order(StringComparer.Ordinal));
        Assert.DoesNotContain(typeof(DirectRegistrationRequest).GetProperties(), property =>
            property.Name is "FullName" or "TermsDocumentVersionId" or "TermsAccepted");
    }

    [Fact] public void DirectRegistrationRequestDoesNotTreatFullNameAsAnAlias()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var request = JsonSerializer.Deserialize<DirectRegistrationRequest>(
            """{"email":"user@example.com","fullName":"User Name","password":"StrongPassword!456","registrationType":"PERSONAL"}""",
            options);

        Assert.Null(request?.DisplayName);
    }

    [Fact] public void VerificationEmailLinkUsesConfiguredHttpsOriginAndKeepsTokenInFragment()
    {
        var link = new Uri(VerificationEmailLink.Build("https://app.example", 42, "token/with+chars"));

        Assert.Equal("https", link.Scheme);
        Assert.Equal("app.example", link.Host);
        Assert.Equal("/verify-email", link.AbsolutePath);
        Assert.Empty(link.Query);
        Assert.Equal("#userId=42&token=token%2Fwith%2Bchars", link.Fragment);
    }

}
