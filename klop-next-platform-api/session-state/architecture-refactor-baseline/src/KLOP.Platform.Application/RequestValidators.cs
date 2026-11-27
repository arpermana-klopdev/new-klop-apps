using FluentValidation;

namespace KLOP.Platform.Application;

public sealed class RegistrationRequestValidator : AbstractValidator<RegistrationRequest>
{
    public RegistrationRequestValidator(IPasswordPolicy passwordPolicy)
    {
        RuleFor(x => x.Email).Must(UserInput.EmailOkay).WithMessage("A valid email address is required.")
            .MaximumLength(320);
        RuleFor(x => x.DisplayName).NotEmpty().MaximumLength(150);
        RuleFor(x => x.Password).NotEmpty()
            .MinimumLength(passwordPolicy.MinPasswordLength).MaximumLength(128);
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

public sealed class TenantCreateRequestValidator : AbstractValidator<TenantCreateRequest>
{
    public TenantCreateRequestValidator()
    {
        RuleFor(x => x.TenantCode).NotEmpty().MaximumLength(50);
        RuleFor(x => x.TenantTypeCode).NotEmpty().MaximumLength(50);
        RuleFor(x => x.DisplayName).NotEmpty().MaximumLength(200);
        RuleFor(x => x.OrganizationTypeId).GreaterThan(0).When(x => x.OrganizationTypeId.HasValue);
        RuleFor(x => x.RegisteredName).MaximumLength(250);
        RuleFor(x => x).Must(x => x.OrganizationTypeId.HasValue == !string.IsNullOrWhiteSpace(x.RegisteredName))
            .WithMessage("Organization type and registered name must be supplied together.");
    }
}

public sealed class InviteRequestValidator : AbstractValidator<InviteRequest>
{
    public InviteRequestValidator() => RuleFor(x => x.InviteeUserId).GreaterThan(0);
}

public sealed class RoleRequestValidator : AbstractValidator<RoleRequest>
{
    public RoleRequestValidator() => RuleFor(x => x.RoleCode).NotEmpty().MaximumLength(50);
}
