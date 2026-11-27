using FluentValidation;

namespace KLOP.Platform.Application;

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