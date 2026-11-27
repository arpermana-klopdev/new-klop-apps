using Microsoft.Net.Http.Headers;
using KLOP.Platform.Application;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Api.Endpoints.Legal;

public static class PublicLegalHandlers
{
    public static async Task<IResult> Current(string? registrationType, HttpContext context,
        LegalTermsService service, CancellationToken cancellationToken)
    {
        if (!RegistrationTypeCodes.IsSupported(registrationType))
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_REGISTRATION_TYPE", "A supported registration type is required.");

        var document = await service.GetCurrent(registrationType!, cancellationToken);
        if (document is null)
            return ApiHelpers.Error(context, StatusCodes.Status404NotFound,
                "TERMS_UNAVAILABLE", "Current Terms and Conditions are unavailable.");

        context.Response.Headers.CacheControl = "public, max-age=60, must-revalidate";
        context.Response.Headers.ETag = $"\"{document.ContentHash}\"";
        return ApiHelpers.Success(context, document);
    }

    public static async Task<IResult> File(Guid documentVersionId, HttpContext context,
        LegalTermsService service, CancellationToken cancellationToken)
    {
        var (stream, metadata) = await service.OpenPublishedFile(documentVersionId, cancellationToken);
        context.Response.Headers.CacheControl = "public, max-age=31536000, immutable";
        context.Response.Headers.ETag = $"\"{metadata.ContentHash}\"";
        return Results.File(stream, "application/pdf", enableRangeProcessing: true,
            entityTag: new EntityTagHeaderValue($"\"{metadata.ContentHash}\""),
            lastModified: new DateTimeOffset(metadata.EffectiveAtUtc, TimeSpan.Zero));
    }
}
