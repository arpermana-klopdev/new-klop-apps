using KLOP.Platform.Application;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Api.Endpoints.Onboarding;

public static class OnboardingEndpoints
{
    public static void MapOnboardingEndpoints(RouteGroupBuilder api)
    {
        var onboarding = api.MapGroup("/onboarding").RequireAuthorization().WithTags("Onboarding");
        onboarding.MapGet("/me", OnboardingHandlers.GetMine)
            .WithSummary("Get the current user's registration and onboarding status")
            .Produces<ApiEnvelope<OnboardingApplicationResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        onboarding.MapPut("/personal/draft", OnboardingHandlers.SavePersonalDraft)
            .WithSummary("Save the current user's Personal onboarding draft")
            .Produces<ApiEnvelope<OnboardingApplicationResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        onboarding.MapPut("/organization/draft", OnboardingHandlers.SaveOrganizationDraft)
            .WithSummary("Save the current user's Organization onboarding draft")
            .Produces<ApiEnvelope<OnboardingApplicationResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        onboarding.MapGet("/organization/requirements", OnboardingHandlers.GetOrganizationRequirements)
            .WithSummary("Get database-driven Organization identity requirements")
            .Produces<ApiEnvelope<IReadOnlyList<OrganizationRequirementResponse>>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        onboarding.MapPost("/submit", OnboardingHandlers.Submit)
            .WithSummary("Submit the current user's onboarding application")
            .Produces<ApiEnvelope<OnboardingApplicationResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        onboarding.MapGet("/{applicationId:long}", OnboardingHandlers.Get)
            .WithSummary("Get an onboarding application owned by the current user")
            .Produces<ApiEnvelope<OnboardingApplicationResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
    }
}
