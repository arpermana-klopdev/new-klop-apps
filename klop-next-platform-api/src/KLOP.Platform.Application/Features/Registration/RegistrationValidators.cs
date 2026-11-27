using FluentValidation;

namespace KLOP.Platform.Application;

public sealed class PersonalOnboardingDraftRequestValidator : AbstractValidator<PersonalOnboardingDraftRequest>
{
    public PersonalOnboardingDraftRequestValidator()
    {
        RuleFor(request => request.RowVersion).Must(value => RowVersionCodec.TryDecode(value, out _));
        RuleFor(request => request.PhoneNumber).MaximumLength(30);
        RuleFor(request => request.CountryCode).Must(value => value is null || value.Trim().Length == 2);
        RuleFor(request => request.Region).MaximumLength(120);
        RuleFor(request => request.City).MaximumLength(120);
        RuleFor(request => request.PostalCode).MaximumLength(30);
        RuleFor(request => request.AddressLine).MaximumLength(500);
    }
}

public sealed class OrganizationOnboardingDraftRequestValidator : AbstractValidator<OrganizationOnboardingDraftRequest>
{
    public OrganizationOnboardingDraftRequestValidator()
    {
        RuleFor(request => request.RowVersion).Must(value => RowVersionCodec.TryDecode(value, out _));
        RuleFor(request => request.OrganizationTypeId).GreaterThan(0).When(request => request.OrganizationTypeId.HasValue);
        RuleFor(request => request.CountryCode).Must(value => value is null || value.Trim().Length == 2);
        RuleFor(request => request.RegisteredName).MaximumLength(250);
        RuleFor(request => request.ContactEmail).MaximumLength(320)
            .Must(value => value is null || UserInput.EmailOkay(value)).When(request => !string.IsNullOrWhiteSpace(request.ContactEmail));
        RuleFor(request => request.ContactPhone).MaximumLength(30);
        RuleFor(request => request.Region).MaximumLength(120);
        RuleFor(request => request.City).MaximumLength(120);
        RuleFor(request => request.PostalCode).MaximumLength(30);
        RuleFor(request => request.AddressLine).MaximumLength(500);
    }
}

public sealed class OnboardingSubmitRequestValidator : AbstractValidator<OnboardingSubmitRequest>
{
    public OnboardingSubmitRequestValidator() =>
        RuleFor(request => request.RowVersion).Must(value => RowVersionCodec.TryDecode(value, out _));
}
