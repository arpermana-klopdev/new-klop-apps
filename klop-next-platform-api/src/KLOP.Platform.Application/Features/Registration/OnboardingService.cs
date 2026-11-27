namespace KLOP.Platform.Application;

public sealed class OnboardingService(IRegistrationRepository repository)
{
    public async Task<OnboardingApplicationResponse?> GetMine(long userId, CancellationToken cancellationToken) =>
        ToResponse(await repository.GetMyOnboarding(userId, cancellationToken));

    public async Task<OnboardingApplicationResponse?> Get(long userId, long applicationId,
        CancellationToken cancellationToken) =>
        ToResponse(await repository.GetOnboarding(userId, applicationId, cancellationToken));

    public async Task<OnboardingApplicationResponse?> SavePersonalDraft(long userId,
        PersonalOnboardingDraftRequest request, RequestMetadata metadata, CancellationToken cancellationToken) =>
        ToResponse(await repository.SavePersonalDraft(userId, request, metadata, cancellationToken));

    public async Task<OnboardingApplicationResponse?> SaveOrganizationDraft(long userId,
        OrganizationOnboardingDraftRequest request, RequestMetadata metadata, CancellationToken cancellationToken) =>
        ToResponse(await repository.SaveOrganizationDraft(userId, request, metadata, cancellationToken));

    public async Task<IReadOnlyList<OrganizationRequirementResponse>> GetOrganizationRequirements(long userId,
        CancellationToken cancellationToken)
    {
        var requirements = await repository.GetOrganizationRequirements(userId, cancellationToken);
        if (requirements.Count == 0)
            throw new OrganizationRequirementsUnavailableException();
        return requirements.Select(requirement => new OrganizationRequirementResponse(
            requirement.RequirementGroupId,
            requirement.RequirementGroupCode,
            requirement.SelectionMode,
            requirement.MinimumRequired,
            requirement.IdentityDocumentTypeId,
            requirement.IdentityDocumentTypeCode,
            requirement.RequiresNumber,
            requirement.AllowsFileUpload,
            requirement.RequirementLevel,
            requirement.GroupEffectiveFromUtc,
            requirement.GroupEffectiveToUtc,
            requirement.RequirementEffectiveFromUtc,
            requirement.RequirementEffectiveToUtc)).ToArray();
    }

    public async Task<OnboardingApplicationResponse?> Submit(long userId, OnboardingSubmitRequest request,
        RequestMetadata metadata, CancellationToken cancellationToken) =>
        ToResponse(await repository.SubmitOnboarding(userId, request, metadata, cancellationToken));

    private static OnboardingApplicationResponse? ToResponse(OnboardingApplication? application) => application is null
        ? null
        : new OnboardingApplicationResponse(
            application.ApplicationId,
            application.RegistrationType,
            application.OnboardingStatus,
            DateTime.SpecifyKind(application.CreatedAtUtc, DateTimeKind.Utc),
            DateTime.SpecifyKind(application.UpdatedAtUtc, DateTimeKind.Utc),
            application.CompletedAtUtc is { } completedAtUtc
                ? DateTime.SpecifyKind(completedAtUtc, DateTimeKind.Utc)
                : null,
            application.TenantId,
            Convert.ToBase64String(application.RowVersion));
}
