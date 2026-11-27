using KLOP.Platform.Application;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Api.Endpoints.Onboarding;

public static class OnboardingHandlers
{
    public static async Task<IResult> GetMine(HttpContext context, OnboardingService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        var application = await service.GetMine(identity.Value.UserId, cancellationToken);
        return application is null
            ? ApiHelpers.Error(context, StatusCodes.Status404NotFound, "ONBOARDING_NOT_FOUND",
                "No active onboarding application is available.")
            : ApiHelpers.Success(context, application);
    }

    public static async Task<IResult> Get(long applicationId, HttpContext context, OnboardingService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        var application = await service.Get(identity.Value.UserId, applicationId, cancellationToken);
        return application is null
            ? ApiHelpers.Error(context, StatusCodes.Status404NotFound, "ONBOARDING_NOT_FOUND",
                "The onboarding application is unavailable.")
            : ApiHelpers.Success(context, application);
    }

    public static async Task<IResult> SavePersonalDraft(PersonalOnboardingDraftRequest request,
        HttpContext context, OnboardingService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        var application = await service.SavePersonalDraft(identity.Value.UserId, request,
            ApiHelpers.Metadata(context), cancellationToken);
        return application is null
            ? ApiHelpers.Error(context, StatusCodes.Status404NotFound, "ONBOARDING_NOT_FOUND",
                "The Personal onboarding application is unavailable.")
            : ApiHelpers.Success(context, application);
    }

    public static async Task<IResult> SaveOrganizationDraft(OrganizationOnboardingDraftRequest request,
        HttpContext context, OnboardingService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        var application = await service.SaveOrganizationDraft(identity.Value.UserId, request,
            ApiHelpers.Metadata(context), cancellationToken);
        return application is null
            ? ApiHelpers.Error(context, StatusCodes.Status404NotFound, "ONBOARDING_NOT_FOUND",
                "The Organization onboarding application is unavailable.")
            : ApiHelpers.Success(context, application);
    }

    public static async Task<IResult> GetOrganizationRequirements(HttpContext context,
        OnboardingService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        return ApiHelpers.Success(context,
            await service.GetOrganizationRequirements(identity.Value.UserId, cancellationToken));
    }

    public static async Task<IResult> Submit(OnboardingSubmitRequest request, HttpContext context,
        OnboardingService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        var application = await service.Submit(identity.Value.UserId, request,
            ApiHelpers.Metadata(context), cancellationToken);
        return application is null
            ? ApiHelpers.Error(context, StatusCodes.Status404NotFound, "ONBOARDING_NOT_FOUND",
                "The onboarding application is unavailable.")
            : ApiHelpers.Success(context, application);
    }
}
