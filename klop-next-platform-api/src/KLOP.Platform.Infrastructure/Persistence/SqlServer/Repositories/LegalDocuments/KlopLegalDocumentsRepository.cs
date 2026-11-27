using System.Data;
using Dapper;
using KLOP.Platform.Application;

namespace KLOP.Platform.Infrastructure;

public sealed partial class KlopRepository
{
    public Task ValidatePlatformPermission(long userId, Guid sessionId, string permissionCode,
        CancellationToken cancellationToken)
    {
        var parameters = ActorParameters(userId, sessionId);
        parameters.Add("PermissionCode", permissionCode, DbType.AnsiString, size: 150);
        return Execute("iam.usp_ValidatePlatformPermission", parameters, cancellationToken);
    }

    public Task<IReadOnlyList<string>> GetPlatformPermissions(long userId, Guid sessionId,
        CancellationToken cancellationToken) =>
        Many<string>("iam.usp_GetPlatformPermissions", ActorParameters(userId, sessionId), cancellationToken);

    public Task<IReadOnlyList<LegalDocumentAdminRow>> ListLegalDocuments(long userId, Guid sessionId,
        CancellationToken cancellationToken) =>
        Many<LegalDocumentAdminRow>("leg.usp_ListLegalDocuments", ActorParameters(userId, sessionId),
            cancellationToken);

    public Task<IReadOnlyList<LegalDocumentAdminRow>> GetLegalDocument(Guid legalDocumentId, long userId,
        Guid sessionId, CancellationToken cancellationToken)
    {
        var parameters = ActorParameters(userId, sessionId);
        parameters.Add("LegalDocumentId", legalDocumentId, DbType.Guid);
        return Many<LegalDocumentAdminRow>("leg.usp_GetLegalDocument", parameters, cancellationToken);
    }

    public Task<IReadOnlyList<LegalDocumentAdminRow>> GetLegalDocumentVersion(Guid documentVersionId, long userId,
        Guid sessionId, CancellationToken cancellationToken)
    {
        var parameters = ActorParameters(userId, sessionId);
        parameters.Add("DocumentVersionId", documentVersionId, DbType.Guid);
        return Many<LegalDocumentAdminRow>("leg.usp_GetLegalDocumentVersion", parameters, cancellationToken);
    }

    public Task<IReadOnlyList<LegalDocumentAdminRow>> GetLegalDocumentPreview(Guid documentVersionId, long userId,
        Guid sessionId, CancellationToken cancellationToken)
    {
        var parameters = ActorParameters(userId, sessionId);
        parameters.Add("DocumentVersionId", documentVersionId, DbType.Guid);
        return Many<LegalDocumentAdminRow>("leg.usp_GetLegalDocumentPreview", parameters, cancellationToken);
    }

    public Task<IReadOnlyList<LegalDocumentAdminRow>> CreateLegalDocumentDraft(Guid? legalDocumentId,
        string title, string versionIdentifier, DateTime effectiveAtUtc, bool personalScope,
        bool organizationScope, StoredLegalDocument storedDocument, long userId, Guid sessionId,
        RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var parameters = ActorParameters(userId, sessionId);
        parameters.Add("LegalDocumentId", legalDocumentId, DbType.Guid);
        parameters.Add("Title", title, DbType.String, size: 300);
        parameters.Add("VersionIdentifier", versionIdentifier, DbType.String, size: 50);
        parameters.Add("EffectiveAtUtc", effectiveAtUtc, DbType.DateTime2);
        parameters.Add("PersonalScope", personalScope, DbType.Boolean);
        parameters.Add("OrganizationScope", organizationScope, DbType.Boolean);
        parameters.Add("StorageReference", storedDocument.StorageReference, DbType.String, size: 32);
        parameters.Add("ContentHash", storedDocument.ContentHash, DbType.Binary, size: 32);
        parameters.Add("MimeType", "application/pdf", DbType.AnsiString, size: 100);
        parameters.Add("FileSizeBytes", storedDocument.FileSizeBytes, DbType.Int64);
        AddMetadata(parameters, metadata);
        return Many<LegalDocumentAdminRow>("leg.usp_CreateLegalDocumentDraft", parameters, cancellationToken);
    }

    public Task<IReadOnlyList<LegalDocumentAdminRow>> UpdateLegalDocumentDraft(Guid documentVersionId,
        string title, string versionIdentifier, DateTime effectiveAtUtc, bool personalScope,
        bool organizationScope, byte[] expectedRowVersion, long userId, Guid sessionId,
        RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var parameters = ActorParameters(userId, sessionId);
        parameters.Add("DocumentVersionId", documentVersionId, DbType.Guid);
        parameters.Add("Title", title, DbType.String, size: 300);
        parameters.Add("VersionIdentifier", versionIdentifier, DbType.String, size: 50);
        parameters.Add("EffectiveAtUtc", effectiveAtUtc, DbType.DateTime2);
        parameters.Add("PersonalScope", personalScope, DbType.Boolean);
        parameters.Add("OrganizationScope", organizationScope, DbType.Boolean);
        parameters.Add("ExpectedRowVersion", expectedRowVersion, DbType.Binary, size: 8);
        AddMetadata(parameters, metadata);
        return Many<LegalDocumentAdminRow>("leg.usp_UpdateLegalDocumentDraft", parameters, cancellationToken);
    }

    public Task<IReadOnlyList<LegalDocumentAdminRow>> SubmitLegalDocument(Guid documentVersionId, long userId,
        Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var parameters = VersionActorParameters(documentVersionId, userId, sessionId);
        AddMetadata(parameters, metadata);
        return Many<LegalDocumentAdminRow>("leg.usp_SubmitLegalDocument", parameters, cancellationToken);
    }

    public Task<IReadOnlyList<LegalDocumentAdminRow>> DecideLegalDocumentApproval(Guid documentVersionId,
        string decisionCode, string? decisionNote, long userId, Guid sessionId, RequestMetadata metadata,
        CancellationToken cancellationToken)
    {
        var parameters = VersionActorParameters(documentVersionId, userId, sessionId);
        parameters.Add("DecisionCode", decisionCode, DbType.AnsiString, size: 20);
        parameters.Add("DecisionNote", decisionNote, DbType.String, size: 1000);
        AddMetadata(parameters, metadata);
        return Many<LegalDocumentAdminRow>("leg.usp_DecideLegalDocumentApproval", parameters, cancellationToken);
    }

    public Task<IReadOnlyList<LegalDocumentAdminRow>> PublishLegalDocument(Guid documentVersionId, long userId,
        Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var parameters = VersionActorParameters(documentVersionId, userId, sessionId);
        AddMetadata(parameters, metadata);
        return Many<LegalDocumentAdminRow>("leg.usp_PublishLegalDocument", parameters, cancellationToken);
    }

    public Task<IReadOnlyList<LegalDocumentAdminRow>> ArchiveLegalDocument(Guid documentVersionId, long userId,
        Guid sessionId, RequestMetadata metadata, CancellationToken cancellationToken)
    {
        var parameters = VersionActorParameters(documentVersionId, userId, sessionId);
        AddMetadata(parameters, metadata);
        return Many<LegalDocumentAdminRow>("leg.usp_ArchiveLegalDocument", parameters, cancellationToken);
    }

    private static DynamicParameters ActorParameters(long userId, Guid sessionId)
    {
        var parameters = new DynamicParameters();
        parameters.Add("ActorUserId", userId, DbType.Int64);
        parameters.Add("PublicSessionId", sessionId, DbType.Guid);
        return parameters;
    }

    private static DynamicParameters VersionActorParameters(Guid documentVersionId, long userId, Guid sessionId)
    {
        var parameters = ActorParameters(userId, sessionId);
        parameters.Add("DocumentVersionId", documentVersionId, DbType.Guid);
        return parameters;
    }

    private static void AddMetadata(DynamicParameters parameters, RequestMetadata metadata)
    {
        parameters.Add("RequestId", metadata.RequestId, DbType.AnsiString, size: 100);
        parameters.Add("CorrelationId", metadata.CorrelationId, DbType.Guid);
    }
}
