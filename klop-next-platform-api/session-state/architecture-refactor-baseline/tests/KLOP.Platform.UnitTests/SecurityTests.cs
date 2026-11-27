using KLOP.Platform.Application;
using Xunit;

namespace KLOP.Platform.UnitTests;
public sealed class SecurityTests
{
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
        var validator = new RegistrationRequestValidator(new TestPasswordPolicy(14));
        var result = validator.Validate(new RegistrationRequest(
            "valid@example.com", "A valid user", "TwelveChars!"));
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

    private sealed class TestPasswordPolicy(int minPasswordLength) : IPasswordPolicy
    {
        public int MinPasswordLength { get; } = minPasswordLength;
    }
}
