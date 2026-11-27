using System.Globalization;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Application;

public sealed class LegalDocumentsService(
    ILegalDocumentsRepository legalDocumentsRepository,
    IPlatformPermissionRepository permissionRepository,
    IPlatformRepository platformRepository,
    ILegalDocumentStorage storage)
{
    private const long MaximumSupportedUploadBytes = 52_428_800;

    public async Task<PlatformLegalDocumentPermissionsResponse> GetPermissions(
        long userId, Guid sessionId, CancellationToken cancellationToken)
    {
        var permissions = await permissionRepository.GetPlatformPermissions(userId, sessionId, cancellationToken);
        return new PlatformLegalDocumentPermissionsResponse(
            permissions.Where(PlatformLegalDocumentPermissions.All.Contains)
                .Distinct(StringComparer.Ordinal)
                .Order(StringComparer.Ordinal)
                .ToArray());
    }

    public async Task<IReadOnlyList<LegalDocumentResponse>> List(
        long userId, Guid sessionId, CancellationToken cancellationToken)
    {
        var rows = await legalDocumentsRepository.ListLegalDocuments(userId, sessionId, cancellationToken);
        return MapDocuments(rows);
    }

    public async Task<LegalDocumentResponse> Get(
        Guid legalDocumentId, long userId, Guid sessionId, CancellationToken cancellationToken)
    {
        if (legalDocumentId == Guid.Empty)
            throw new LegalDocumentValidationException("INVALID_DOCUMENT_ID", "A legal document ID is required.");
        var rows = await legalDocumentsRepository.GetLegalDocument(
            legalDocumentId, userId, sessionId, cancellationToken);
        return MapDocuments(rows).SingleOrDefault()
            ?? throw new LegalDocumentNotFoundException();
    }

    public async Task<LegalDocumentResponse> CreateDraft(
        LegalDocumentDraftUpload request, CancellationToken cancellationToken)
    {
        ValidateActor(request.ActorUserId, request.PublicSessionId);
        ValidateDraftMetadata(request.Title, request.VersionIdentifier, request.EffectiveAtUtc,
            request.PersonalScope, request.OrganizationScope);
        if (request.LegalDocumentId == Guid.Empty)
            throw new LegalDocumentValidationException("INVALID_DOCUMENT_ID", "A legal document ID is invalid.");
        if (!string.Equals(request.ContentType.Trim(), "application/pdf", StringComparison.OrdinalIgnoreCase))
            throw new LegalDocumentStorageValidationException("LEGAL_FILE_INVALID", "Only PDF documents can be uploaded.");

        var maximumBytes = await GetMaximumUploadBytes(cancellationToken);
        if (request.ContentLength <= 0 || request.ContentLength > maximumBytes)
            throw new LegalDocumentStorageValidationException("LEGAL_FILE_INVALID", "The PDF size is outside the allowed limit.");

        var storedDocument = await storage.SavePdf(request.Content, request.ContentLength,
            maximumBytes, cancellationToken);
        var savedToDatabase = false;
        try
        {
            var rows = await legalDocumentsRepository.CreateLegalDocumentDraft(request.LegalDocumentId,
                request.Title.Trim(), request.VersionIdentifier.Trim(), request.EffectiveAtUtc,
                request.PersonalScope, request.OrganizationScope, storedDocument, request.ActorUserId,
                request.PublicSessionId, request.Metadata, cancellationToken);
            savedToDatabase = true;
            return MapDocuments(rows).SingleOrDefault()
                ?? throw new LegalDocumentStorageUnavailableException(
                    "The legal document draft could not be read after creation.");
        }
        finally
        {
            if (!savedToDatabase)
                await storage.DeletePdf(storedDocument.StorageReference, CancellationToken.None);
        }
    }

    public async Task<LegalDocumentResponse> UpdateDraft(
        LegalDocumentDraftUpdate request, CancellationToken cancellationToken)
    {
        ValidateActor(request.ActorUserId, request.PublicSessionId);
        ValidateDraftMetadata(request.Title, request.VersionIdentifier, request.EffectiveAtUtc,
            request.PersonalScope, request.OrganizationScope);
        if (request.DocumentVersionId == Guid.Empty)
            throw new LegalDocumentValidationException("INVALID_DOCUMENT_VERSION_ID", "A document version ID is required.");
        if (!RowVersionCodec.TryDecode(request.RowVersion, out var rowVersion))
            throw new LegalDocumentValidationException("INVALID_ROW_VERSION", "The document version token is invalid.");

        var rows = await legalDocumentsRepository.UpdateLegalDocumentDraft(request.DocumentVersionId,
            request.Title.Trim(), request.VersionIdentifier.Trim(), request.EffectiveAtUtc,
            request.PersonalScope, request.OrganizationScope, rowVersion, request.ActorUserId,
            request.PublicSessionId, request.Metadata, cancellationToken);
        return MapDocuments(rows).SingleOrDefault()
            ?? throw new LegalDocumentNotFoundException();
    }

    public async Task<LegalDocumentResponse> Submit(
        Guid documentVersionId, long userId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken)
    {
        await VerifyStoredPdf(documentVersionId, userId, sessionId, cancellationToken);
        var rows = await legalDocumentsRepository.SubmitLegalDocument(documentVersionId, userId, sessionId,
            metadata, cancellationToken);
        return MapDocuments(rows).SingleOrDefault()
            ?? throw new LegalDocumentNotFoundException();
    }

    public async Task<LegalDocumentResponse> Decide(
        Guid documentVersionId, LegalDocumentApprovalDecision request, CancellationToken cancellationToken)
    {
        ValidateActor(request.ActorUserId, request.PublicSessionId);
        var decision = request.DecisionCode.Trim().ToUpperInvariant();
        if (decision is not ("APPROVED" or "REJECTED"))
            throw new LegalDocumentValidationException("INVALID_APPROVAL_DECISION",
                "The approval decision must be APPROVED or REJECTED.");
        if (request.DecisionNote?.Length > 1000)
            throw new LegalDocumentValidationException("INVALID_APPROVAL_NOTE", "The decision note is too long.");

        var rows = await legalDocumentsRepository.DecideLegalDocumentApproval(documentVersionId, decision,
            string.IsNullOrWhiteSpace(request.DecisionNote) ? null : request.DecisionNote.Trim(),
            request.ActorUserId, request.PublicSessionId, request.Metadata, cancellationToken);
        return MapDocuments(rows).SingleOrDefault()
            ?? throw new LegalDocumentNotFoundException();
    }

    public async Task<LegalDocumentResponse> Publish(
        Guid documentVersionId, long userId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken)
    {
        await VerifyStoredPdf(documentVersionId, userId, sessionId, cancellationToken);
        var rows = await legalDocumentsRepository.PublishLegalDocument(documentVersionId, userId, sessionId,
            metadata, cancellationToken);
        return MapDocuments(rows).SingleOrDefault()
            ?? throw new LegalDocumentNotFoundException();
    }

    public async Task<LegalDocumentResponse> Archive(
        Guid documentVersionId, long userId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken)
    {
        var rows = await legalDocumentsRepository.ArchiveLegalDocument(documentVersionId, userId, sessionId,
            metadata, cancellationToken);
        return MapDocuments(rows).SingleOrDefault()
            ?? throw new LegalDocumentNotFoundException();
    }

    public async Task<LegalDocumentPreview> OpenPreview(
        Guid documentVersionId, long userId, Guid sessionId, CancellationToken cancellationToken)
    {
        if (documentVersionId == Guid.Empty)
            throw new LegalDocumentValidationException("INVALID_DOCUMENT_VERSION_ID", "A document version ID is required.");
        var rows = await legalDocumentsRepository.GetLegalDocumentPreview(
            documentVersionId, userId, sessionId, cancellationToken);
        var document = rows.FirstOrDefault()
            ?? throw new LegalDocumentNotFoundException();
        if (document.PublicationStatus is not ("DRAFT" or "PENDING_APPROVAL" or "APPROVED"))
            throw new LegalDocumentConflictException("LEGAL_VERSION_NOT_PREVIEWABLE",
                "This legal document version is not available for draft preview.");
        var maximumBytes = await GetMaximumUploadBytes(cancellationToken);
        var stream = await storage.OpenPdf(document.StorageReference, document.FileSizeBytes,
            maximumBytes, document.ContentHash, cancellationToken);
        return new LegalDocumentPreview(stream, document);
    }

    private async Task VerifyStoredPdf(
        Guid documentVersionId, long userId, Guid sessionId, CancellationToken cancellationToken)
    {
        var rows = await legalDocumentsRepository.GetLegalDocumentVersion(
            documentVersionId, userId, sessionId, cancellationToken);
        var document = rows.FirstOrDefault()
            ?? throw new LegalDocumentNotFoundException();
        var maximumBytes = await GetMaximumUploadBytes(cancellationToken);
        await using var stream = await storage.OpenPdf(document.StorageReference, document.FileSizeBytes,
            maximumBytes, document.ContentHash, cancellationToken);
    }

    private async Task<long> GetMaximumUploadBytes(CancellationToken cancellationToken)
    {
        var setting = await platformRepository.GetConfiguration("legal.maximum_upload_bytes", cancellationToken);
        if (setting is null || setting.ValueType != "INTEGER" || setting.StorageType != "PLAIN" ||
            !long.TryParse(setting.ConfigurationValue, NumberStyles.None, CultureInfo.InvariantCulture,
                out var maximumBytes) || maximumBytes <= 0 || maximumBytes > MaximumSupportedUploadBytes)
            throw new LegalDocumentStorageUnavailableException("The legal document upload policy is unavailable.");
        return maximumBytes;
    }

    private static void ValidateDraftMetadata(
        string title, string versionIdentifier, DateTime effectiveAtUtc,
        bool personalScope, bool organizationScope)
    {
        if (string.IsNullOrWhiteSpace(title) || title.Trim().Length > 300)
            throw new LegalDocumentValidationException("INVALID_LEGAL_DOCUMENT_TITLE",
                "A title of at most 300 characters is required.");
        if (string.IsNullOrWhiteSpace(versionIdentifier) || versionIdentifier.Trim().Length > 50)
            throw new LegalDocumentValidationException("INVALID_LEGAL_DOCUMENT_VERSION",
                "A version identifier of at most 50 characters is required.");
        if (effectiveAtUtc.Kind != DateTimeKind.Utc)
            throw new LegalDocumentValidationException("INVALID_EFFECTIVE_DATE",
                "The effective date must be provided in UTC.");
        if (!personalScope && !organizationScope)
            throw new LegalDocumentValidationException("LEGAL_SCOPE_REQUIRED",
                "At least one registration scope is required.");
    }

    private static void ValidateActor(long userId, Guid sessionId)
    {
        if (userId <= 0 || sessionId == Guid.Empty)
            throw new LegalDocumentValidationException("UNAUTHORIZED", "An authenticated session is required.");
    }

    private static IReadOnlyList<LegalDocumentResponse> MapDocuments(
        IReadOnlyList<LegalDocumentAdminRow> rows) =>
        rows.GroupBy(row => row.LegalDocumentId)
            .Select(document => new LegalDocumentResponse(
                document.Key,
                document.First().DocumentTypeCode,
                document.GroupBy(row => row.DocumentVersionId)
                    .Select(version =>
                    {
                        var row = version.First();
                        return new LegalDocumentVersionResponse(
                            row.DocumentVersionId,
                            row.VersionIdentifier,
                            row.Title,
                            DateTime.SpecifyKind(row.EffectiveAtUtc, DateTimeKind.Utc),
                            row.PublicationStatus,
                            row.FileSizeBytes,
                            Convert.ToHexString(row.ContentHash).ToLowerInvariant(),
                            DateTime.SpecifyKind(row.CreatedAtUtc, DateTimeKind.Utc),
                            ToUtc(row.SubmittedAtUtc),
                            ToUtc(row.ApprovedAtUtc),
                            ToUtc(row.PublishedAtUtc),
                            ToUtc(row.ArchivedAtUtc),
                            row.LatestApprovalDecisionCode,
                            ToUtc(row.LatestApprovalDecisionAtUtc),
                            row.LatestApprovalDecisionNote,
                            version.Select(item => item.RegistrationScopeCode)
                                .Where(scope => !string.IsNullOrWhiteSpace(scope))
                                .Select(scope => scope!)
                                .Distinct(StringComparer.OrdinalIgnoreCase)
                                .Order(StringComparer.Ordinal)
                                .ToArray(),
                            Convert.ToBase64String(row.RowVersion));
                    })
                    .OrderByDescending(version => version.CreatedAtUtc)
                    .ToArray()))
            .OrderByDescending(document => document.Versions.FirstOrDefault()?.CreatedAtUtc)
            .ToArray();

    private static DateTime? ToUtc(DateTime? value) =>
        value is null ? null : DateTime.SpecifyKind(value.Value, DateTimeKind.Utc);
}
