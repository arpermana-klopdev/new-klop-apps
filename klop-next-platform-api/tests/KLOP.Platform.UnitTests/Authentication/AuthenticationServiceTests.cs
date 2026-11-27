using KLOP.Platform.Application;
using KLOP.Platform.Api.Endpoints.Authentication;
using KLOP.Platform.Domain;
using KLOP.Platform.Infrastructure;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class AuthenticationServiceTests
{
    private const string TestPassword = "Authentication-Test-Password-456!";
    private const string LegacyPassword = "KLOP-Legacy-Test-Only!";
    private const string LegacyPasswordHash = "100000.AAECAwQFBgcICQoLDA0ODw==.H21AyGlXYICmLKkA0n7cuDrwMxZS9HIUR1zNr5gfL0c=";
    private static readonly Lazy<string> TestPasswordHash =
        new(() => new PasswordCodec().Hash(TestPassword));

    [Fact]
    public async Task LoginRejectsInactiveAccountWithoutCreatingSession()
    {
        await AssertIneligibleAccountRejected(candidate => candidate.IsActive = false);
    }

    [Fact]
    public async Task LoginRejectsUnverifiedAccountWithoutCreatingSession()
    {
        await AssertIneligibleAccountRejected(candidate => candidate.EmailVerifiedAtUtc = null);
    }

    [Fact]
    public async Task LoginRejectsLockedAccountWithoutCreatingSession()
    {
        await AssertIneligibleAccountRejected(candidate => candidate.LockoutUntilUtc = DateTime.UtcNow.AddMinutes(5));
    }

    [Fact]
    public async Task LoginFailureRecordsBadPasswordWithoutCreatingSession()
    {
        var repository = new TestRepository { Candidate = EligibleCandidate() };
        var tokenIssuer = new TestTokenIssuer();
        var service = CreateService(repository, tokenIssuer);

        var session = await service.Login(new LoginRequest("user@example.com", "Wrong-Password-456!"), Metadata(),
            CancellationToken.None);

        Assert.Null(session);
        Assert.Equal(1, repository.LoginFailureCount);
        Assert.Equal(repository.Candidate.UserId, repository.LastFailedUserId);
        Assert.Equal(0, repository.CreateSessionCount);
        Assert.Null(tokenIssuer.LastUserId);
    }

    [Fact]
    public async Task RegisterPassesNormalizedIntentAndSelectedTermsToAtomicRepositoryOperation()
    {
        var repository = new TestRepository();
        var service = CreateService(repository, new TestTokenIssuer());
        var versionId = Guid.NewGuid();

        await service.Register(new RegistrationRequest("user@example.com", "User", TestPassword)
        {
            RegistrationType = " organization ",
            TermsDocumentVersionId = versionId,
            TermsAccepted = true
        }, Metadata(), CancellationToken.None);

        Assert.Equal("ORGANIZATION", repository.LastRegistrationType);
        Assert.Equal(versionId, repository.LastTermsDocumentVersionId);
        Assert.True(repository.LastTermsAccepted);
        Assert.Equal(1, repository.RegisterCount);
    }

    [Fact]
    public async Task RegisterPersistsCurrentHashAndHashedVerificationTokenWithoutTenantOrAccess()
    {
        var repository = new TestRepository();
        var tokenIssuer = new TestTokenIssuer();
        var emailSender = new TestEmailSender();
        var service = CreateService(repository, tokenIssuer, emailSender);
        var metadata = Metadata();
        var request = new RegistrationRequest(" User@Example.com ", null, "  StrongPassword!456  ")
        {
            DisplayName = " Example User "
        };

        await service.Register(request, metadata, CancellationToken.None);

        Assert.Equal(1, repository.RegisterCount);
        Assert.Equal("User@Example.com", repository.LastRegisteredEmail);
        Assert.Equal("Example User", repository.LastRegisteredDisplayName);
        Assert.StartsWith("pbkdf2-sha256$600000$", repository.LastRegisteredPasswordHash);
        var hashParts = repository.LastRegisteredPasswordHash!.Split('$');
        Assert.Equal(4, hashParts.Length);
        Assert.Equal(600_000, int.Parse(hashParts[1], System.Globalization.CultureInfo.InvariantCulture));
        Assert.Equal(32, Convert.FromBase64String(hashParts[2]).Length);
        Assert.Equal(32, Convert.FromBase64String(hashParts[3]).Length);
        Assert.True(new PasswordCodec().Verify(request.Password, repository.LastRegisteredPasswordHash));
        Assert.Equal(32, repository.LastRegistrationTokenHash!.Length);
        Assert.Equal(1, emailSender.SendCount);
        Assert.Equal("User@Example.com", emailSender.LastEmail);
        Assert.Equal(43, emailSender.LastVerificationCode!.Length);
        Assert.True(System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
            SecretTokens.Sha256(emailSender.LastVerificationCode), repository.LastRegistrationTokenHash));
        Assert.Equal(metadata.RequestId, repository.LastRegistrationRequestId);
        Assert.Equal(metadata.CorrelationId, repository.LastRegistrationCorrelationId);
        Assert.Equal(0, repository.CreateSessionCount);
        Assert.Null(tokenIssuer.LastUserId);
    }

    [Fact]
    public void RegistrationValidatorRequiresACompleteTermsAcceptanceSet()
    {
        var validator = new RegistrationRequestValidator(new RuntimeSettings("https://issuer.example", "klop-test",
            "https://app.example", 15, 30, 5, 12, 24, 30, 30, "smtp.example", 25,
            "no-reply@example.com", true, null, null, null));

        var incomplete = validator.Validate(new RegistrationRequest("user@example.com", "User", TestPassword)
        {
            RegistrationType = "PERSONAL",
            TermsAccepted = true
        });
        var unsupportedType = validator.Validate(new RegistrationRequest("user@example.com", "User", TestPassword)
        {
            RegistrationType = "ADMIN",
            TermsDocumentVersionId = Guid.NewGuid(),
            TermsAccepted = true
        });

        Assert.Contains(incomplete.Errors,
            error => error.PropertyName == nameof(RegistrationRequest.TermsDocumentVersionId));
        Assert.Contains(unsupportedType.Errors,
            error => error.PropertyName == nameof(RegistrationRequest.RegistrationType));
        Assert.True(validator.Validate(new RegistrationRequest("user@example.com", "User", TestPassword)
        {
            RegistrationType = "PERSONAL",
            TermsDocumentVersionId = Guid.NewGuid(),
            TermsAccepted = true
        }).IsValid);
    }

    [Fact]
    public void DevelopmentTermsBypassAcceptsTypedRegistrationWithoutConsentAndProductionFailsClosed()
    {
        var developmentSettings = new RuntimeSettings(
            "https://issuer.example", "klop-test", "https://app.example", 15, 30, 5, 12, 24, 30, 30,
            "smtp.example", 25, "no-reply@example.com", true, null, null, null,
            LegalConsentEnforcement: false,
            DevelopmentTermsBypassEnabled: true);
        var developmentValidator = new RegistrationRequestValidator(developmentSettings);
        var request = new RegistrationRequest("user@example.com", "User", TestPassword)
        {
            RegistrationType = "PERSONAL"
        };

        Assert.True(developmentValidator.Validate(request).IsValid);
        Assert.Equal(["PERSONAL", "ORGANIZATION"],
            RegistrationPolicyRules.GetEffective(developmentSettings).AllowedRegistrationTypes);
        Assert.False(RegistrationPolicyRules.GetEffective(developmentSettings).TermsRequired);
        RegistrationPolicyRules.ValidateRuntime(developmentSettings, isDevelopment: true);
        Assert.Throws<InvalidOperationException>(() =>
            RegistrationPolicyRules.ValidateRuntime(developmentSettings, isDevelopment: false));

        var productionSettings = developmentSettings with
        {
            LegalConsentEnforcement = true,
            DevelopmentTermsBypassEnabled = false
        };
        var productionValidator = new RegistrationRequestValidator(productionSettings);
        Assert.Contains(productionValidator.Validate(request).Errors,
            error => error.PropertyName == nameof(RegistrationRequest.TermsDocumentVersionId));
        Assert.True(RegistrationPolicyRules.GetEffective(productionSettings).TermsRequired);
    }

    [Fact]
    public void DevelopmentTermsBypassRejectsFabricatedTermsFields()
    {
        var settings = new RuntimeSettings(
            "https://issuer.example", "klop-test", "https://app.example", 15, 30, 5, 12, 24, 30, 30,
            "smtp.example", 25, "no-reply@example.com", true, null, null, null,
            LegalConsentEnforcement: false,
            DevelopmentTermsBypassEnabled: true);
        var validator = new RegistrationRequestValidator(settings);
        var request = new RegistrationRequest("user@example.com", "User", TestPassword)
        {
            RegistrationType = "ORGANIZATION",
            TermsDocumentVersionId = Guid.NewGuid(),
            TermsAccepted = true
        };

        Assert.Contains(validator.Validate(request).Errors,
            error => error.PropertyName == nameof(RegistrationRequest.TermsDocumentVersionId));
        Assert.Contains(validator.Validate(request).Errors,
            error => error.PropertyName == nameof(RegistrationRequest.TermsAccepted));
    }

    [Fact]
    public void DirectAndTermsRequiredRegistrationContractsUseSeparateConsentValidation()
    {
        var developmentSettings = new RuntimeSettings(
            "https://issuer.example", "klop-test", "https://app.example", 15, 30, 5, 12, 24, 30, 30,
            "smtp.example", 25, "no-reply@example.com", true, null, null, null,
            LegalConsentEnforcement: false,
            DevelopmentTermsBypassEnabled: true);
        var directRequest = new DirectRegistrationRequest(
            "user@example.com", "User", TestPassword, "PERSONAL");

        Assert.True(new DirectRegistrationRequestValidator(developmentSettings).Validate(directRequest).IsValid);

        var productionSettings = developmentSettings with
        {
            LegalConsentEnforcement = true,
            DevelopmentTermsBypassEnabled = false
        };
        var incompleteTermsRequest = new TermsRequiredRegistrationRequest(
            "user@example.com", "User", TestPassword, "PERSONAL", Guid.Empty, false);
        var completeTermsRequest = incompleteTermsRequest with
        {
            TermsDocumentVersionId = Guid.NewGuid(),
            TermsAccepted = true
        };
        var termsValidator = new TermsRequiredRegistrationRequestValidator(productionSettings);

        Assert.Contains(termsValidator.Validate(incompleteTermsRequest).Errors,
            error => error.PropertyName == nameof(TermsRequiredRegistrationRequest.TermsDocumentVersionId));
        Assert.Contains(termsValidator.Validate(incompleteTermsRequest).Errors,
            error => error.PropertyName == nameof(TermsRequiredRegistrationRequest.TermsAccepted));
        Assert.True(termsValidator.Validate(completeTermsRequest).IsValid);
    }

    [Fact]
    public async Task DirectRegistrationPassesNoConsentToRepositoryAndKeepsTheDevelopmentBypass()
    {
        var settings = new RuntimeSettings(
            "https://issuer.example", "klop-test", "https://app.example", 15, 30, 5, 12, 24, 30, 30,
            "smtp.example", 25, "no-reply@example.com", true, null, null, null,
            LegalConsentEnforcement: false,
            DevelopmentTermsBypassEnabled: true);
        var repository = new TestRepository();
        var service = CreateService(repository, new TestTokenIssuer(), settings: settings);

        var result = await AuthenticationHandlers.RegisterDirect(
            new DirectRegistrationRequest("user@example.com", "User", TestPassword, "ORGANIZATION"),
            new DefaultHttpContext(), service, CancellationToken.None);

        Assert.Equal(StatusCodes.Status202Accepted, Assert.IsAssignableFrom<IStatusCodeHttpResult>(result).StatusCode);
        Assert.Equal("ORGANIZATION", repository.LastRegistrationType);
        Assert.True(repository.LastDevelopmentTermsBypassEnabled);
        Assert.Null(repository.LastTermsDocumentVersionId);
        Assert.Null(repository.LastTermsAccepted);
    }

    [Fact]
    public async Task RegisterTreatsDuplicateEmailLikeAcceptedRequestWithoutSendingEmail()
    {
        var repository = new TestRepository { RegisterException = new DuplicateRegistrationException() };
        var emailSender = new TestEmailSender();
        var service = CreateService(repository, new TestTokenIssuer(), emailSender);

        await service.Register(new RegistrationRequest("user@example.com", "User", TestPassword), Metadata(),
            CancellationToken.None);

        Assert.Equal(1, repository.RegisterCount);
        Assert.Equal(0, emailSender.SendCount);
        Assert.Equal(0, repository.CreateSessionCount);
    }

    [Fact]
    public async Task RegisterEndpointReturnsGenericAcceptedResponseForDuplicateAddress()
    {
        var repository = new TestRepository { RegisterException = new DuplicateRegistrationException() };
        var emailSender = new TestEmailSender();
        var service = CreateService(repository, new TestTokenIssuer(), emailSender);

        var result = await AuthenticationHandlers.Register(
            new RegistrationRequest("user@example.com", "User", TestPassword),
            new DefaultHttpContext(), service, CancellationToken.None);

        var response = Assert.IsAssignableFrom<IStatusCodeHttpResult>(result);
        Assert.Equal(StatusCodes.Status202Accepted, response.StatusCode);
        Assert.Equal(0, emailSender.SendCount);
    }

    [Fact]
    public async Task RegisterPropagatesRepositoryFailuresAndDoesNotSendEmail()
    {
        var repository = new TestRepository { RegisterException = new InvalidOperationException("Database unavailable.") };
        var emailSender = new TestEmailSender();
        var service = CreateService(repository, new TestTokenIssuer(), emailSender);

        await Assert.ThrowsAsync<InvalidOperationException>(() => service.Register(
            new RegistrationRequest("user@example.com", "User", TestPassword), Metadata(), CancellationToken.None));

        Assert.Equal(0, emailSender.SendCount);
    }

    [Fact]
    public async Task ResendPropagatesRepositoryFailureWithoutSendingEmail()
    {
        var repository = new TestRepository { ResendException = new InvalidOperationException("Database unavailable.") };
        var emailSender = new TestEmailSender();
        var service = CreateService(repository, new TestTokenIssuer(), emailSender);

        await Assert.ThrowsAsync<InvalidOperationException>(() => service.ResendVerification(
            new ResendVerificationRequest("user@example.com"), Metadata(), CancellationToken.None));

        Assert.Equal(0, emailSender.SendCount);
    }

    [Fact]
    public async Task RegisterEmailFailureIsLoggedWithCorrelationButDoesNotFailCommittedRegistration()
    {
        var repository = new TestRepository();
        var emailSender = new TestEmailSender { Failure = new InvalidOperationException("SMTP unavailable.") };
        var logger = new TestLogger();
        var service = CreateService(repository, new TestTokenIssuer(), emailSender, logger);
        var metadata = Metadata();
        const string email = "user@example.com";

        await service.Register(new RegistrationRequest(email, "User", TestPassword), metadata, CancellationToken.None);

        Assert.Equal(1, repository.RegisterCount);
        Assert.Equal(1, emailSender.SendCount);
        Assert.Single(logger.Messages);
        Assert.Contains("Operation=registration", logger.Messages[0]);
        Assert.Contains(metadata.CorrelationId.ToString(), logger.Messages[0]);
        Assert.Contains(nameof(InvalidOperationException), logger.Messages[0]);
        Assert.DoesNotContain(email, logger.Messages[0]);
        Assert.DoesNotContain(TestPassword, logger.Messages[0]);
        Assert.DoesNotContain(emailSender.LastVerificationCode!, logger.Messages[0]);
    }

    [Fact]
    public async Task ResendSendsVerificationOnlyForEligibleUserAndHashesTheToken()
    {
        var repository = new TestRepository { ResendUserId = 42 };
        var emailSender = new TestEmailSender();
        var service = CreateService(repository, new TestTokenIssuer(), emailSender);
        var metadata = Metadata();

        await service.ResendVerification(new ResendVerificationRequest(" User@Example.com "), metadata,
            CancellationToken.None);

        Assert.Equal(1, repository.ResendCount);
        Assert.Equal("User@Example.com", repository.LastResendEmail);
        Assert.Equal(metadata.RequestId, repository.LastResendRequestId);
        Assert.Equal(metadata.CorrelationId, repository.LastResendCorrelationId);
        Assert.Equal(42, emailSender.LastUserId);
        Assert.Equal("User@Example.com", emailSender.LastEmail);
        Assert.True(System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
            SecretTokens.Sha256(emailSender.LastVerificationCode!), repository.LastResendTokenHash!));
    }

    [Fact]
    public async Task RegisterEmailFailureCanBeRecoveredByResendingVerification()
    {
        var repository = new TestRepository { ResendUserId = 42 };
        var emailSender = new TestEmailSender { Failure = new InvalidOperationException("SMTP unavailable.") };
        var service = CreateService(repository, new TestTokenIssuer(), emailSender);

        await service.Register(new RegistrationRequest("user@example.com", "User", TestPassword), Metadata(),
            CancellationToken.None);
        var registrationToken = emailSender.LastVerificationCode;
        emailSender.Failure = null;

        await service.ResendVerification(new ResendVerificationRequest("user@example.com"), Metadata(),
            CancellationToken.None);

        Assert.Equal(2, emailSender.SendCount);
        Assert.NotEqual(registrationToken, emailSender.LastVerificationCode);
        Assert.True(System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
            SecretTokens.Sha256(emailSender.LastVerificationCode!), repository.LastResendTokenHash!));
    }

    [Fact]
    public async Task ResendDoesNotSendEmailWhenDatabaseSaysUserIsNotEligible()
    {
        var repository = new TestRepository { ResendUserId = null };
        var emailSender = new TestEmailSender();
        var service = CreateService(repository, new TestTokenIssuer(), emailSender);

        await service.ResendVerification(new ResendVerificationRequest("user@example.com"), Metadata(),
            CancellationToken.None);

        Assert.Equal(1, repository.ResendCount);
        Assert.Equal(0, emailSender.SendCount);
    }

    [Fact]
    public async Task ConfirmEmailPassesOnlyTokenHashAndPreservesRequestMetadata()
    {
        var repository = new TestRepository();
        var service = CreateService(repository, new TestTokenIssuer());
        var metadata = Metadata();
        const string token = "a-valid-verification-token-value-1234567890";

        await service.ConfirmEmail(new VerifyEmailRequest(42, token), metadata, CancellationToken.None);

        Assert.Equal(42, repository.LastConfirmedUserId);
        Assert.Equal(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(token)),
            repository.LastConfirmationTokenHash);
        Assert.Equal(metadata.RequestId, repository.LastConfirmationRequestId);
        Assert.Equal(metadata.CorrelationId, repository.LastConfirmationCorrelationId);
    }

    [Fact]
    public async Task ConfirmEmailPropagatesInvalidOrExpiredChallengeFailure()
    {
        var repository = new TestRepository { ConfirmationException = new InvalidOperationException("Challenge rejected.") };
        var service = CreateService(repository, new TestTokenIssuer());

        await Assert.ThrowsAsync<InvalidOperationException>(() => service.ConfirmEmail(
            new VerifyEmailRequest(42, "invalid-or-expired-token"), Metadata(), CancellationToken.None));
    }

    [Fact]
    public void RegistrationValidatorRejectsMissingInvalidAndWhitespaceOnlyFields()
    {
        var validator = new RegistrationRequestValidator(new RuntimeSettings("https://issuer.example", "klop-test",
            "https://app.example", 15, 30, 5, 12, 24, 30, 30, "smtp.example", 25,
            "no-reply@example.com", true, null, null, null));

        var result = validator.Validate(new RegistrationRequest(null!, "   ", "            "));

        Assert.Contains(result.Errors, error => error.PropertyName == nameof(RegistrationRequest.Email));
        Assert.Contains(result.Errors, error => error.PropertyName == nameof(RegistrationRequest.DisplayName));
        Assert.Contains(result.Errors, error => error.PropertyName == nameof(RegistrationRequest.Password));
        Assert.True(validator.Validate(new RegistrationRequest(" USER@example.com ", " User ",
            "  ValidPassword!456  ")
        {
            RegistrationType = "PERSONAL",
            TermsDocumentVersionId = Guid.NewGuid(),
            TermsAccepted = true
        }).IsValid);
        Assert.True(validator.Validate(new RegistrationRequest(" USER@example.com ", null,
            "  ValidPassword!456  ")
        {
            DisplayName = " User ",
            RegistrationType = "PERSONAL",
            TermsDocumentVersionId = Guid.NewGuid(),
            TermsAccepted = true
        }).IsValid);
    }

    [Theory]
    [InlineData("not-an-email")]
    [InlineData("")]
    [InlineData("bad@@example.com")]
    public void RegistrationValidatorRejectsInvalidEmail(string email)
    {
        var validator = new RegistrationRequestValidator(new RuntimeSettings("https://issuer.example", "klop-test",
            "https://app.example", 15, 30, 5, 12, 24, 30, 30, "smtp.example", 25,
            "no-reply@example.com", true, null, null, null));

        Assert.Contains(validator.Validate(new RegistrationRequest(email, "User", TestPassword)).Errors,
            error => error.PropertyName == nameof(RegistrationRequest.Email));
    }

    [Fact]
    public void RegistrationValidatorRejectsEmptyDisplayNameAndPassword()
    {
        var validator = new RegistrationRequestValidator(new RuntimeSettings("https://issuer.example", "klop-test",
            "https://app.example", 15, 30, 5, 12, 24, 30, 30, "smtp.example", 25,
            "no-reply@example.com", true, null, null, null));

        var result = validator.Validate(new RegistrationRequest("user@example.com", null, "")
        {
            DisplayName = ""
        });

        Assert.Contains(result.Errors, error => error.PropertyName == nameof(RegistrationRequest.DisplayName));
        Assert.Contains(result.Errors, error => error.PropertyName == nameof(RegistrationRequest.Password));
    }

    [Fact]
    public void RegistrationValidatorRejectsFieldsExceedingDatabaseContractLengths()
    {
        var validator = new RegistrationRequestValidator(new RuntimeSettings("https://issuer.example", "klop-test",
            "https://app.example", 15, 30, 5, 12, 24, 30, 30, "smtp.example", 25,
            "no-reply@example.com", true, null, null, null));

        var result = validator.Validate(new RegistrationRequest("user@example.com", new string('A', 151),
            new string('P', 129)));

        Assert.Contains(result.Errors, error => error.PropertyName == nameof(RegistrationRequest.DisplayName));
        Assert.Contains(result.Errors, error => error.PropertyName == nameof(RegistrationRequest.Password));
        Assert.Contains(validator.Validate(new RegistrationRequest(new string('a', 321), "User", TestPassword)).Errors,
            error => error.PropertyName == nameof(RegistrationRequest.Email));
    }

    [Fact]
    public void RegistrationValidatorUsesCanonicalDisplayName()
    {
        var validator = new RegistrationRequestValidator(new RuntimeSettings("https://issuer.example", "klop-test",
            "https://app.example", 15, 30, 5, 12, 24, 30, 30, "smtp.example", 25,
            "no-reply@example.com", true, null, null, null));

        var request = new RegistrationRequest("user@example.com", "Other Name", TestPassword)
        {
            DisplayName = " User Name ",
            RegistrationType = "PERSONAL",
            TermsDocumentVersionId = Guid.NewGuid(),
            TermsAccepted = true
        };

        Assert.True(validator.Validate(request).IsValid);
        Assert.Equal(" User Name ", request.DisplayName);
    }

    [Fact]
    public async Task LoginCreatesSessionAndIssuesAccessTokenForEligibleAccount()
    {
        var repository = new TestRepository { Candidate = EligibleCandidate() };
        var tokenIssuer = new TestTokenIssuer();
        var service = CreateService(repository, tokenIssuer);
        var metadata = Metadata();

        var session = await service.Login(new LoginRequest(" User@Example.com ", TestPassword), metadata,
            CancellationToken.None);

        Assert.NotNull(session);
        Assert.Equal("USER@EXAMPLE.COM", repository.LastNormalizedEmail);
        Assert.Equal(1, repository.CreateSessionCount);
        Assert.Equal(repository.Candidate.UserId, repository.LastSessionUserId);
        Assert.Equal(repository.SessionId, session.SessionId);
        Assert.Equal(tokenIssuer.IssuedAccess, session.Access);
        Assert.Equal(repository.Candidate.UserId, tokenIssuer.LastUserId);
        Assert.Equal(repository.SessionId, tokenIssuer.LastSessionId);
        Assert.Equal(30, session.RefreshDays);
        Assert.NotEmpty(session.RefreshToken);
        Assert.Equal(32, repository.LastRefreshTokenHash!.Length);
        Assert.True(System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
            SecretTokens.Sha256(session.RefreshToken), repository.LastRefreshTokenHash));
        Assert.Equal(0, repository.LoginFailureCount);
    }

    [Fact]
    public async Task LoginAcceptsVerifiedLegacyPasswordHashThroughPasswordCodec()
    {
        var repository = new TestRepository { Candidate = EligibleCandidate(LegacyPasswordHash) };
        var tokenIssuer = new TestTokenIssuer();
        var service = CreateService(repository, tokenIssuer);

        var session = await service.Login(new LoginRequest("user@example.com", LegacyPassword), Metadata(),
            CancellationToken.None);

        Assert.NotNull(session);
        Assert.Equal(1, repository.CreateSessionCount);
        Assert.Equal(0, repository.LoginFailureCount);
        Assert.Equal(repository.Candidate.UserId, tokenIssuer.LastUserId);
    }

    [Fact]
    public async Task LoginRejectsWrongPasswordForLegacyHashAndRecordsFailure()
    {
        var repository = new TestRepository { Candidate = EligibleCandidate(LegacyPasswordHash) };
        var tokenIssuer = new TestTokenIssuer();
        var service = CreateService(repository, tokenIssuer);

        var session = await service.Login(new LoginRequest("user@example.com", "Wrong-Password-456!"), Metadata(),
            CancellationToken.None);

        Assert.Null(session);
        Assert.Equal(1, repository.LoginFailureCount);
        Assert.Equal(repository.Candidate.UserId, repository.LastFailedUserId);
        Assert.Equal(0, repository.CreateSessionCount);
        Assert.Null(tokenIssuer.LastUserId);
    }

    private static async Task AssertIneligibleAccountRejected(Action<LoginCandidate> makeIneligible)
    {
        var candidate = EligibleCandidate();
        makeIneligible(candidate);
        var repository = new TestRepository { Candidate = candidate };
        var tokenIssuer = new TestTokenIssuer();
        var service = CreateService(repository, tokenIssuer);

        var session = await service.Login(new LoginRequest("user@example.com", TestPassword), Metadata(),
            CancellationToken.None);

        Assert.Null(session);
        Assert.Equal(0, repository.LoginFailureCount);
        Assert.Equal(0, repository.CreateSessionCount);
        Assert.Null(tokenIssuer.LastUserId);
    }

    private static LoginCandidate EligibleCandidate(string? passwordHash = null) => new()
    {
        UserId = 42,
        PasswordHash = passwordHash ?? TestPasswordHash.Value,
        IsActive = true,
        EmailVerifiedAtUtc = DateTime.UtcNow.AddDays(-1)
    };

    private static RequestMetadata Metadata() => new("auth-unit-test", Guid.NewGuid());

    private static AuthenticationService CreateService(TestRepository repository, TestTokenIssuer tokenIssuer,
        TestEmailSender? emailSender = null, ILogger<AuthenticationService>? logger = null,
        RuntimeSettings? settings = null)
    {
        settings ??= new RuntimeSettings("https://issuer.example", "klop-test", "https://app.example", 15, 30,
            5, 12, 24, 30, 30, "smtp.example", 25, "no-reply@example.com", true, null, null, null);
        return new AuthenticationService(repository, new PasswordCodec(), tokenIssuer,
            emailSender ?? new TestEmailSender(), settings, logger ?? NullLogger<AuthenticationService>.Instance);
    }

    private sealed class TestTokenIssuer : IAccessTokenIssuer
    {
        public long? LastUserId { get; private set; }
        public Guid? LastSessionId { get; private set; }
        public AccessResult IssuedAccess { get; } = new("unit-test-access-token", 900);

        public AccessResult Issue(long userId, Guid sessionId)
        {
            LastUserId = userId;
            LastSessionId = sessionId;
            return IssuedAccess;
        }
    }

    private sealed class TestEmailSender : IVerificationEmailSender
    {
        public int SendCount { get; private set; }
        public long? LastUserId { get; private set; }
        public string? LastEmail { get; private set; }
        public string? LastVerificationCode { get; private set; }
        public Exception? Failure { get; set; }

        public Task Send(string email, long userId, string verificationCode, Guid correlationId,
            CancellationToken cancellationToken)
        {
            SendCount++;
            LastUserId = userId;
            LastEmail = email;
            LastVerificationCode = verificationCode;
            return Failure is null ? Task.CompletedTask : Task.FromException(Failure);
        }
    }

    private sealed class TestLogger : ILogger<AuthenticationService>
    {
        public List<string> Messages { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            if (logLevel == LogLevel.Warning)
                Messages.Add(formatter(state, exception));
        }
    }

    private sealed class TestRepository : IPlatformRepository
    {
        public LoginCandidate? Candidate { get; init; }
        public Exception? RegisterException { get; init; }
        public Exception? ResendException { get; init; }
        public Exception? ConfirmationException { get; init; }
        public long? ResendUserId { get; init; }
        public Guid SessionId { get; } = Guid.NewGuid();
        public int RegisterCount { get; private set; }
        public int ResendCount { get; private set; }
        public int LoginFailureCount { get; private set; }
        public int CreateSessionCount { get; private set; }
        public long? LastFailedUserId { get; private set; }
        public long? LastSessionUserId { get; private set; }
        public string? LastNormalizedEmail { get; private set; }
        public byte[]? LastRefreshTokenHash { get; private set; }
        public string? LastRegisteredEmail { get; private set; }
        public string? LastRegisteredDisplayName { get; private set; }
        public string? LastRegisteredPasswordHash { get; private set; }
        public bool LastDevelopmentTermsBypassEnabled { get; private set; }
        public byte[]? LastRegistrationTokenHash { get; private set; }
        public string? LastRegistrationRequestId { get; private set; }
        public Guid LastRegistrationCorrelationId { get; private set; }
        public string? LastRegistrationType { get; private set; }
        public Guid? LastTermsDocumentVersionId { get; private set; }
        public bool? LastTermsAccepted { get; private set; }
        public string? LastResendEmail { get; private set; }
        public byte[]? LastResendTokenHash { get; private set; }
        public string? LastResendRequestId { get; private set; }
        public Guid LastResendCorrelationId { get; private set; }
        public long? LastConfirmedUserId { get; private set; }
        public byte[]? LastConfirmationTokenHash { get; private set; }
        public string? LastConfirmationRequestId { get; private set; }
        public Guid LastConfirmationCorrelationId { get; private set; }

        public Task<LoginCandidate?> GetLoginCandidate(string email, CancellationToken cancellationToken)
        {
            LastNormalizedEmail = email;
            return Task.FromResult(Candidate);
        }

        public Task RecordLoginFailure(long userId, Guid correlationId, CancellationToken cancellationToken)
        {
            LoginFailureCount++;
            LastFailedUserId = userId;
            return Task.CompletedTask;
        }

        public Task<Guid> CreateSession(long userId, byte[] refreshHash, Guid correlationId, string requestId,
            CancellationToken cancellationToken)
        {
            CreateSessionCount++;
            LastSessionUserId = userId;
            LastRefreshTokenHash = refreshHash;
            return Task.FromResult(SessionId);
        }

        public Task<(long UserId, long ChallengeId)> Register(string email, string displayName, string passwordHash,
            byte[] tokenHash, string requestId, Guid correlationId, string? registrationTypeCode,
            Guid? termsDocumentVersionId, bool? termsAccepted, bool developmentTermsBypassEnabled,
            CancellationToken cancellationToken)
        {
            RegisterCount++;
            LastRegisteredEmail = email;
            LastRegisteredDisplayName = displayName;
            LastRegisteredPasswordHash = passwordHash;
            LastDevelopmentTermsBypassEnabled = developmentTermsBypassEnabled;
            LastRegistrationTokenHash = tokenHash.ToArray();
            LastRegistrationRequestId = requestId;
            LastRegistrationCorrelationId = correlationId;
            LastRegistrationType = registrationTypeCode;
            LastTermsDocumentVersionId = termsDocumentVersionId;
            LastTermsAccepted = termsAccepted;
            if (RegisterException is not null)
                return Task.FromException<(long UserId, long ChallengeId)>(RegisterException);
            return Task.FromResult((UserId: 42L, ChallengeId: 84L));
        }
        public Task ConfirmEmail(long userId, byte[] tokenHash, string requestId, Guid correlationId,
            CancellationToken cancellationToken)
        {
            LastConfirmedUserId = userId;
            LastConfirmationTokenHash = tokenHash.ToArray();
            LastConfirmationRequestId = requestId;
            LastConfirmationCorrelationId = correlationId;
            return ConfirmationException is null ? Task.CompletedTask : Task.FromException(ConfirmationException);
        }
        public Task<long?> Resend(string email, byte[] hash, string requestId, Guid correlationId,
            CancellationToken cancellationToken)
        {
            ResendCount++;
            LastResendEmail = email;
            LastResendTokenHash = hash.ToArray();
            LastResendRequestId = requestId;
            LastResendCorrelationId = correlationId;
            return ResendException is null ? Task.FromResult(ResendUserId) : Task.FromException<long?>(ResendException);
        }
        public Task ValidateSession(long userId, Guid sessionId, long? tenantId, string? permission,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<long> RotateRefresh(Guid sessionId, byte[] oldHash, byte[] newHash, Guid correlationId,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task RevokeSession(long userId, Guid sessionId, Guid correlationId,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<Profile?> GetProfile(long userId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public Task<IReadOnlyList<TenantSummary>> MyTenants(long userId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public Task<IReadOnlyList<string>> GetTenantPermissions(long userId, Guid sessionId, long tenantId,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<IReadOnlyList<OrganizationType>> OrganizationTypes(CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public Task<IReadOnlyList<TenantType>> TenantTypes(CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public Task<ConfigurationEntry?> GetConfiguration(string key, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public Task<(long TenantId, long MembershipId)> CreateTenant(long userId, string code, string type,
            string name, long? organizationTypeId, string? registeredName, string requestId, Guid correlationId,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<long> Invite(long tenantId, long actorUserId, long inviteeUserId, string requestId,
            Guid correlationId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task Accept(long membershipId, long actorUserId, string requestId, Guid correlationId,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task Remove(long membershipId, long actorUserId, string requestId, Guid correlationId,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task AssignRole(long membershipId, long actorUserId, string roleCode, string requestId,
            Guid correlationId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task RevokeRole(long membershipId, long actorUserId, string roleCode, string requestId,
            Guid correlationId, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task CheckDatabase(CancellationToken cancellationToken) => throw new NotSupportedException();
    }
}