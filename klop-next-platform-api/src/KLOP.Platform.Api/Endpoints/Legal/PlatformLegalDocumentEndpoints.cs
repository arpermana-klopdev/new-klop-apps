using KLOP.Platform.Application;
using KLOP.Platform.Domain;
using Microsoft.AspNetCore.Mvc;

namespace KLOP.Platform.Api.Endpoints.Legal;

public static class PlatformLegalDocumentEndpoints
{
    private const long MaximumMultipartRequestBytes = 52_690_432;

    public static void MapPlatformLegalDocumentEndpoints(RouteGroupBuilder api)
    {
        api.MapGet("/platform/legal-documents/permissions", PlatformLegalDocumentHandlers.Permissions)
            .RequireAuthorization()
            .WithTags("Platform Legal Documents")
            .WithSummary("Get the authenticated user's effective legal document permissions")
            .Produces<ApiEnvelope<PlatformLegalDocumentPermissionsResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        var documents = api.MapGroup("/platform/legal-documents")
            .RequireAuthorization()
            .RequirePlatformPermission(PlatformLegalDocumentPermissions.Read)
            .WithTags("Platform Legal Documents");

        documents.MapGet("", PlatformLegalDocumentHandlers.List)
            .WithSummary("List legal documents and versions")
            .Produces<ApiEnvelope<IReadOnlyList<LegalDocumentResponse>>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden);

        documents.MapGet("/{legalDocumentId:guid}", PlatformLegalDocumentHandlers.Get)
            .WithSummary("Get legal document details and version history")
            .Produces<ApiEnvelope<LegalDocumentResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound);

        documents.MapPost("", PlatformLegalDocumentHandlers.CreateDraft)
            .RequirePlatformPermission(PlatformLegalDocumentPermissions.DraftCreate)
            .WithMetadata(new RequestSizeLimitAttribute(MaximumMultipartRequestBytes))
            .WithSummary("Upload a PDF as a new legal document draft version")
            .Accepts<IFormCollection>("multipart/form-data")
            .Produces<ApiEnvelope<LegalDocumentResponse>>(StatusCodes.Status201Created)
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        documents.MapPut("/versions/{documentVersionId:guid}", PlatformLegalDocumentHandlers.UpdateDraft)
            .RequirePlatformPermission(PlatformLegalDocumentPermissions.DraftEdit)
            .WithSummary("Update draft metadata and registration scopes")
            .Produces<ApiEnvelope<LegalDocumentResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict);

        documents.MapGet("/versions/{documentVersionId:guid}/preview", PlatformLegalDocumentHandlers.Preview)
            .RequirePlatformPermission(PlatformLegalDocumentPermissions.DraftPreview)
            .WithSummary("Preview a private legal document draft PDF")
            .Produces(StatusCodes.Status200OK, contentType: "application/pdf")
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        documents.MapPost("/versions/{documentVersionId:guid}/submit-for-approval",
                PlatformLegalDocumentHandlers.Submit)
            .RequirePlatformPermission(PlatformLegalDocumentPermissions.Submit)
            .WithSummary("Submit a validated draft for approval")
            .Produces<ApiEnvelope<LegalDocumentResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict);

        documents.MapPost("/versions/{documentVersionId:guid}/approve",
                PlatformLegalDocumentHandlers.Decide)
            .RequirePlatformPermission(PlatformLegalDocumentPermissions.Approve)
            .WithSummary("Approve or reject a submitted legal document")
            .Produces<ApiEnvelope<LegalDocumentResponse>>()
            .ProducesProblem(StatusCodes.Status400BadRequest)
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict);

        documents.MapPost("/versions/{documentVersionId:guid}/publish",
                PlatformLegalDocumentHandlers.Publish)
            .RequirePlatformPermission(PlatformLegalDocumentPermissions.Publish)
            .WithSummary("Publish an approved legal document version")
            .Produces<ApiEnvelope<LegalDocumentResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict);

        documents.MapPost("/versions/{documentVersionId:guid}/archive",
                PlatformLegalDocumentHandlers.Archive)
            .RequirePlatformPermission(PlatformLegalDocumentPermissions.Archive)
            .WithSummary("Archive a superseded published legal document version")
            .Produces<ApiEnvelope<LegalDocumentResponse>>()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict);
    }
}
