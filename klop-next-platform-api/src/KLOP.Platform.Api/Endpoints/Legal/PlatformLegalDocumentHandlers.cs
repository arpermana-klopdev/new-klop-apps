using System.Globalization;
using KLOP.Platform.Application;
using KLOP.Platform.Domain;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;

namespace KLOP.Platform.Api.Endpoints.Legal;

public sealed record LegalDocumentDraftUpdateRequest(
    string Title,
    string VersionIdentifier,
    DateTimeOffset EffectiveAtUtc,
    IReadOnlyList<string> RegistrationTypes,
    string RowVersion);

public sealed record LegalDocumentApprovalRequest(string DecisionCode, string? DecisionNote);

public static class PlatformLegalDocumentHandlers
{
    public static async Task<IResult> Permissions(
        HttpContext context, LegalDocumentsService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        return ApiHelpers.Success(context,
            await service.GetPermissions(identity.Value.UserId, identity.Value.SessionId, cancellationToken));
    }

    public static async Task<IResult> List(
        HttpContext context, LegalDocumentsService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        return ApiHelpers.Success(context,
            await service.List(identity.Value.UserId, identity.Value.SessionId, cancellationToken));
    }

    public static async Task<IResult> Get(
        Guid legalDocumentId, HttpContext context, LegalDocumentsService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        return ApiHelpers.Success(context, await service.Get(legalDocumentId, identity.Value.UserId,
            identity.Value.SessionId, cancellationToken));
    }

    public static async Task<IResult> CreateDraft(
        HttpContext context, LegalDocumentsService service, CancellationToken cancellationToken)
    {
        if (!context.Request.HasFormContentType)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "LEGAL_FILE_INVALID", "A multipart PDF upload is required.");

        IFormCollection form;
        try
        {
            form = await context.Request.ReadFormAsync(cancellationToken);
        }
        catch (InvalidDataException)
        {
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "LEGAL_FILE_INVALID", "The multipart PDF upload is invalid.");
        }

        var files = form.Files.Where(file =>
            string.Equals(file.Name, "file", StringComparison.OrdinalIgnoreCase)).ToArray();
        if (files.Length != 1 || form.Files.Count != 1)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "LEGAL_FILE_INVALID", "Upload exactly one PDF file.");

        var title = ReadSingleValue(form, "title");
        var version = ReadSingleValue(form, "versionIdentifier");
        var effectiveAt = ReadEffectiveAtUtc(ReadSingleValue(form, "effectiveAtUtc"));
        var requestedScopes = form["registrationTypes"]
            .Select(scope => scope?.Trim().ToUpperInvariant())
            .Where(scope => !string.IsNullOrEmpty(scope))
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        var documentIdText = ReadSingleValue(form, "legalDocumentId");
        if (title is null || version is null || effectiveAt is null ||
            (documentIdText is not null && !Guid.TryParse(documentIdText, out _)) ||
            requestedScopes.Any(scope => scope is not ("PERSONAL" or "ORGANIZATION")))
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_LEGAL_DOCUMENT", "Legal document metadata is invalid.");

        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");

        await using var content = files[0].OpenReadStream();
        var result = await service.CreateDraft(new LegalDocumentDraftUpload(
            documentIdText is null ? null : Guid.Parse(documentIdText),
            title,
            version,
            effectiveAt.Value,
            requestedScopes.Contains("PERSONAL", StringComparer.Ordinal),
            requestedScopes.Contains("ORGANIZATION", StringComparer.Ordinal),
            files[0].ContentType,
            files[0].Length,
            content,
            identity.Value.UserId,
            identity.Value.SessionId,
            ApiHelpers.Metadata(context)), cancellationToken);
        return ApiHelpers.Success(context, result, StatusCodes.Status201Created);
    }

    public static async Task<IResult> UpdateDraft(
        Guid documentVersionId, LegalDocumentDraftUpdateRequest request, HttpContext context,
        LegalDocumentsService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        if (!TryScopes(request.RegistrationTypes, out var personal, out var organization))
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_LEGAL_DOCUMENT", "At least one supported registration scope is required.");
        if (request.EffectiveAtUtc.Offset != TimeSpan.Zero)
            return ApiHelpers.Error(context, StatusCodes.Status400BadRequest,
                "INVALID_EFFECTIVE_DATE", "The effective date must use UTC.");

        return ApiHelpers.Success(context, await service.UpdateDraft(new LegalDocumentDraftUpdate(
            documentVersionId, request.Title, request.VersionIdentifier, request.EffectiveAtUtc.UtcDateTime,
            personal, organization, request.RowVersion, identity.Value.UserId, identity.Value.SessionId,
            ApiHelpers.Metadata(context)), cancellationToken));
    }

    public static async Task<IResult> Preview(
        Guid documentVersionId, HttpContext context, LegalDocumentsService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        var preview = await service.OpenPreview(documentVersionId, identity.Value.UserId,
            identity.Value.SessionId, cancellationToken);
        context.Response.Headers.CacheControl = "no-store";
        context.Response.Headers.ETag = $"\"{Convert.ToHexString(preview.Document.ContentHash).ToLowerInvariant()}\"";
        return Results.File(preview.Stream, "application/pdf", enableRangeProcessing: true,
            entityTag: new EntityTagHeaderValue(context.Response.Headers.ETag.ToString()));
    }

    public static async Task<IResult> Submit(
        Guid documentVersionId, HttpContext context, LegalDocumentsService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        return ApiHelpers.Success(context, await service.Submit(documentVersionId, identity.Value.UserId,
            identity.Value.SessionId, ApiHelpers.Metadata(context), cancellationToken));
    }

    public static async Task<IResult> Decide(
        Guid documentVersionId, LegalDocumentApprovalRequest request, HttpContext context,
        LegalDocumentsService service, CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        return ApiHelpers.Success(context, await service.Decide(documentVersionId,
            new LegalDocumentApprovalDecision(request.DecisionCode, request.DecisionNote,
                identity.Value.UserId, identity.Value.SessionId, ApiHelpers.Metadata(context)),
            cancellationToken));
    }

    public static async Task<IResult> Publish(
        Guid documentVersionId, HttpContext context, LegalDocumentsService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        return ApiHelpers.Success(context, await service.Publish(documentVersionId, identity.Value.UserId,
            identity.Value.SessionId, ApiHelpers.Metadata(context), cancellationToken));
    }

    public static async Task<IResult> Archive(
        Guid documentVersionId, HttpContext context, LegalDocumentsService service,
        CancellationToken cancellationToken)
    {
        var identity = ApiHelpers.Identity(context);
        if (identity is null)
            return ApiHelpers.Error(context, StatusCodes.Status401Unauthorized, "UNAUTHORIZED", "Login required.");
        return ApiHelpers.Success(context, await service.Archive(documentVersionId, identity.Value.UserId,
            identity.Value.SessionId, ApiHelpers.Metadata(context), cancellationToken));
    }

    private static string? ReadSingleValue(IFormCollection form, string name)
    {
        var values = form[name];
        return values.Count == 1 && !string.IsNullOrWhiteSpace(values[0]) ? values[0] : null;
    }

    private static DateTime? ReadEffectiveAtUtc(string? value) =>
        DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None,
            out var parsed) && parsed.Offset == TimeSpan.Zero
            ? parsed.UtcDateTime
            : null;

    private static bool TryScopes(
        IReadOnlyList<string>? requested, out bool personal, out bool organization)
    {
        var scopes = requested?
            .Select(scope => scope?.Trim().ToUpperInvariant())
            .Where(scope => !string.IsNullOrEmpty(scope))
            .Distinct(StringComparer.Ordinal)
            .ToArray() ?? [];
        personal = scopes.Contains("PERSONAL", StringComparer.Ordinal);
        organization = scopes.Contains("ORGANIZATION", StringComparer.Ordinal);
        return scopes.Length is 1 or 2 &&
            scopes.All(scope => scope is "PERSONAL" or "ORGANIZATION");
    }
}
