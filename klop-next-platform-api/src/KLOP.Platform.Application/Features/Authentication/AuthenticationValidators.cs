using FluentValidation;

namespace KLOP.Platform.Application;

public abstract class RegistrationFieldsValidator<T> : AbstractValidator<T>
    where T : IRegistrationFields
{
    protected RegistrationFieldsValidator(IPlatformRuntimeSettings settings)
    {
        RuleFor(x => x.Email).Must(UserInput.EmailOkay).WithMessage("A valid email address is required.")
            .MaximumLength(320);
        RuleFor(x => x.DisplayName).NotEmpty().MaximumLength(150);
        RuleFor(x => x.Password).NotEmpty()
            .MinimumLength(settings.MinPasswordLength).MaximumLength(RegistrationLimits.MaxPasswordLength);
        RuleFor(x => x.RegistrationType)
            .Must(value => value is not null && RegistrationTypeCodes.IsSupported(value))
            .WithMessage("A supported registration type is required.");
        RuleFor(x => x.RegistrationType)
            .Must(value => !string.Equals(value?.Trim(), "PERSONAL", StringComparison.OrdinalIgnoreCase) ||
                           settings.PersonalRegistrationEnabled)
            .WithMessage("PERSONAL registration is not currently available.")
            .Must(value => !string.Equals(value?.Trim(), "ORGANIZATION", StringComparison.OrdinalIgnoreCase) ||
                           settings.OrganizationRegistrationEnabled)
            .WithMessage("ORGANIZATION registration is not currently available.");
    }
}

public sealed class DirectRegistrationRequestValidator : RegistrationFieldsValidator<DirectRegistrationRequest>
{
    public DirectRegistrationRequestValidator(IPlatformRuntimeSettings settings) : base(settings) { }
}

public sealed class TermsRequiredRegistrationRequestValidator
    : RegistrationFieldsValidator<TermsRequiredRegistrationRequest>
{
    public TermsRequiredRegistrationRequestValidator(IPlatformRuntimeSettings settings) : base(settings)
    {
        RuleFor(x => x.TermsDocumentVersionId)
            .NotEmpty()
            .WithMessage("The current Terms document version is required for the selected registration type.");
        RuleFor(x => x.TermsAccepted)
            .Equal(true)
            .WithMessage("Explicit Terms acceptance is required for the selected registration type.");
    }
}

public sealed class RegistrationRequestValidator : RegistrationFieldsValidator<RegistrationRequest>
{
    public RegistrationRequestValidator(IPlatformRuntimeSettings settings) : base(settings)
    {
        RuleFor(x => x.TermsDocumentVersionId)
            .Must(value => settings.DevelopmentTermsBypassEnabled
                ? value is null
                : value is not null && value != Guid.Empty)
            .WithMessage(settings.DevelopmentTermsBypassEnabled
                ? "Terms version fields are not accepted while the Development Terms bypass is active."
                : "The current Terms document version is required for the selected registration type.");
        RuleFor(x => x.TermsAccepted)
            .Must(value => settings.DevelopmentTermsBypassEnabled ? value is null : value == true)
            .WithMessage(settings.DevelopmentTermsBypassEnabled
                ? "Terms acceptance fields are not accepted while the Development Terms bypass is active."
                : "Explicit Terms acceptance is required for the selected registration type.");
    }
}

public sealed class ResendVerificationRequestValidator : AbstractValidator<ResendVerificationRequest>
{
    public ResendVerificationRequestValidator()
    {
        RuleFor(x => x.Email).Must(UserInput.EmailOkay).WithMessage("A valid email address is required.")
            .MaximumLength(320);
    }
}

public sealed class VerifyEmailRequestValidator : AbstractValidator<VerifyEmailRequest>
{
    public VerifyEmailRequestValidator()
    {
        RuleFor(x => x.UserId).GreaterThan(0);
        RuleFor(x => x.Token).NotEmpty().MinimumLength(32).MaximumLength(100);
    }
}

public sealed class LoginRequestValidator : AbstractValidator<LoginRequest>
{
    public LoginRequestValidator()
    {
        RuleFor(x => x.Email).Must(UserInput.EmailOkay).WithMessage("A valid email address is required.")
            .MaximumLength(320);
        RuleFor(x => x.Password).NotEmpty().MaximumLength(128);
    }
}