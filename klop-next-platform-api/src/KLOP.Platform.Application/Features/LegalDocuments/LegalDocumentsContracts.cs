namespace KLOP.Platform.Application;

public static class PlatformLegalDocumentPermissions
{
    public const string Read = "platform.legal_documents.read";
    public const string DraftCreate = "platform.legal_documents.draft.create";
    public const string DraftEdit = "platform.legal_documents.draft.edit";
    public const string DraftPreview = "platform.legal_documents.draft.preview";
    public const string Submit = "platform.legal_documents.submit";
    public const string Approve = "platform.legal_documents.approve";
    public const string Publish = "platform.legal_documents.publish";
    public const string Archive = "platform.legal_documents.archive";

    public static readonly string[] All =
    [
        Read,
        DraftCreate,
        DraftEdit,
        DraftPreview,
        Submit,
        Approve,
        Publish,
        Archive
    ];
}

public sealed class LegalDocumentAdminRow
{
    public Guid LegalDocumentId { get; set; }
    public Guid DocumentVersionId { get; set; }
    public string DocumentTypeCode { get; set; } = "";
    public string Title { get; set; } = "";
    public string VersionIdentifier { get; set; } = "";
    public DateTime EffectiveAtUtc { get; set; }
    public string PublicationStatus { get; set; } = "";
    public string StorageReference { get; set; } = "";
    public byte[] ContentHash { get; set; } = [];
    public string MimeType { get; set; } = "";
    public long FileSizeBytes { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime? SubmittedAtUtc { get; set; }
    public DateTime? ApprovedAtUtc { get; set; }
    public DateTime? PublishedAtUtc { get; set; }
    public DateTime? ArchivedAtUtc { get; set; }
    public string? LatestApprovalDecisionCode { get; set; }
    public DateTime? LatestApprovalDecisionAtUtc { get; set; }
    public string? LatestApprovalDecisionNote { get; set; }
    public byte[] RowVersion { get; set; } = [];
    public string? RegistrationScopeCode { get; set; }
}

public sealed record LegalDocumentVersionResponse(
    Guid DocumentVersionId,
    string VersionIdentifier,
    string Title,
    DateTime EffectiveAtUtc,
    string PublicationStatus,
    long FileSizeBytes,
    string ContentHash,
    DateTime CreatedAtUtc,
    DateTime? SubmittedAtUtc,
    DateTime? ApprovedAtUtc,
    DateTime? PublishedAtUtc,
    DateTime? ArchivedAtUtc,
    string? LatestApprovalDecisionCode,
    DateTime? LatestApprovalDecisionAtUtc,
    string? LatestApprovalDecisionNote,
    IReadOnlyList<string> RegistrationScopes,
    string RowVersion);

public sealed record LegalDocumentResponse(
    Guid LegalDocumentId,
    string DocumentTypeCode,
    IReadOnlyList<LegalDocumentVersionResponse> Versions);

public sealed record PlatformLegalDocumentPermissionsResponse(IReadOnlyList<string> Permissions);

public sealed record LegalDocumentDraftUpload(
    Guid? LegalDocumentId,
    string Title,
    string VersionIdentifier,
    DateTime EffectiveAtUtc,
    bool PersonalScope,
    bool OrganizationScope,
    string ContentType,
    long ContentLength,
    Stream Content,
    long ActorUserId,
    Guid PublicSessionId,
    RequestMetadata Metadata);

public sealed record LegalDocumentDraftUpdate(
    Guid DocumentVersionId,
    string Title,
    string VersionIdentifier,
    DateTime EffectiveAtUtc,
    bool PersonalScope,
    bool OrganizationScope,
    string RowVersion,
    long ActorUserId,
    Guid PublicSessionId,
    RequestMetadata Metadata);

public sealed record LegalDocumentApprovalDecision(
    string DecisionCode,
    string? DecisionNote,
    long ActorUserId,
    Guid PublicSessionId,
    RequestMetadata Metadata);

public sealed record StoredLegalDocument(string StorageReference, long FileSizeBytes, byte[] ContentHash);

public sealed record LegalDocumentPreview(Stream Stream, LegalDocumentAdminRow Document);

public interface IPlatformPermissionRepository
{
    Task ValidatePlatformPermission(long userId, Guid sessionId, string permissionCode,
        CancellationToken cancellationToken);
    Task<IReadOnlyList<string>> GetPlatformPermissions(long userId, Guid sessionId,
        CancellationToken cancellationToken);
}

public interface ILegalDocumentsRepository
{
    Task<IReadOnlyList<LegalDocumentAdminRow>> ListLegalDocuments(long userId, Guid sessionId,
        CancellationToken cancellationToken);
    Task<IReadOnlyList<LegalDocumentAdminRow>> GetLegalDocument(Guid legalDocumentId, long userId,
        Guid sessionId, CancellationToken cancellationToken);
    Task<IReadOnlyList<LegalDocumentAdminRow>> GetLegalDocumentVersion(Guid documentVersionId, long userId,
        Guid sessionId, CancellationToken cancellationToken);
    Task<IReadOnlyList<LegalDocumentAdminRow>> GetLegalDocumentPreview(Guid documentVersionId, long userId,
        Guid sessionId, CancellationToken cancellationToken);
    Task<IReadOnlyList<LegalDocumentAdminRow>> CreateLegalDocumentDraft(Guid? legalDocumentId, string title,
        string versionIdentifier, DateTime effectiveAtUtc, bool personalScope, bool organizationScope,
        StoredLegalDocument storedDocument, long userId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken);
    Task<IReadOnlyList<LegalDocumentAdminRow>> UpdateLegalDocumentDraft(Guid documentVersionId, string title,
        string versionIdentifier, DateTime effectiveAtUtc, bool personalScope, bool organizationScope,
        byte[] expectedRowVersion, long userId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken);
    Task<IReadOnlyList<LegalDocumentAdminRow>> SubmitLegalDocument(Guid documentVersionId, long userId,
        Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken);
    Task<IReadOnlyList<LegalDocumentAdminRow>> DecideLegalDocumentApproval(Guid documentVersionId,
        string decisionCode, string? decisionNote, long userId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken);
    Task<IReadOnlyList<LegalDocumentAdminRow>> PublishLegalDocument(Guid documentVersionId, long userId,
        Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken);
    Task<IReadOnlyList<LegalDocumentAdminRow>> ArchiveLegalDocument(Guid documentVersionId, long userId,
        Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken);
}

public sealed class LegalDocumentValidationException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

public sealed class LegalDocumentNotFoundException() : Exception("The legal document is unavailable.");
public sealed class LegalDocumentConflictException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

public sealed class LegalDocumentStorageValidationException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
