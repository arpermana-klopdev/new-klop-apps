-- KLOP Platform v1.6 DRAFT public legal reads and immutable-history guards.
-- No document is created, approved, published, or uploaded by this script.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE leg.usp_GetCurrentTerms
	@RegistrationTypeCode VARCHAR(50)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(),@TenantTypeId BIGINT;
	SELECT @TenantTypeId=TenantTypeId FROM mst.TenantTypes
	WHERE Code=UPPER(LTRIM(RTRIM(@RegistrationTypeCode))) AND IsActive=1;
	IF @TenantTypeId IS NULL THROW 52114, 'Registration type is unavailable.', 1;

	SELECT TOP (1) v.DocumentVersionId,d.DocumentTypeCode,v.Title,v.VersionIdentifier,
		   ty.Code AS RegistrationTypeCode,v.EffectiveAtUtc,v.PublicationStatus,
		   v.StorageReference,v.ContentHash,v.MimeType,v.FileSizeBytes
	FROM leg.LegalDocumentVersions v
	JOIN leg.LegalDocuments d ON d.LegalDocumentId=v.LegalDocumentId
	JOIN leg.LegalDocumentVersionScopes scope ON scope.DocumentVersionId=v.DocumentVersionId
	JOIN mst.TenantTypes ty ON ty.TenantTypeId=scope.TenantTypeId
	WHERE scope.TenantTypeId=@TenantTypeId AND d.DocumentTypeCode='TERMS_AND_CONDITIONS'
	  AND v.PublicationStatus='PUBLISHED' AND v.EffectiveAtUtc<=@Now
	ORDER BY v.EffectiveAtUtc DESC,v.PublishedAtUtc DESC,v.CreatedAtUtc DESC;
END;
GO
CREATE OR ALTER PROCEDURE leg.usp_GetPublicTermsFile
	@DocumentVersionId UNIQUEIDENTIFIER
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Now DATETIME2(3)=SYSUTCDATETIME();
	SELECT TOP (1) v.DocumentVersionId,d.DocumentTypeCode,v.Title,v.VersionIdentifier,
		   ty.Code AS RegistrationTypeCode,v.EffectiveAtUtc,v.PublicationStatus,
		   v.StorageReference,v.ContentHash,v.MimeType,v.FileSizeBytes
	FROM leg.LegalDocumentVersions v
	JOIN leg.LegalDocuments d ON d.LegalDocumentId=v.LegalDocumentId
	JOIN leg.LegalDocumentVersionScopes scope ON scope.DocumentVersionId=v.DocumentVersionId
	JOIN mst.TenantTypes ty ON ty.TenantTypeId=scope.TenantTypeId
	WHERE v.DocumentVersionId=@DocumentVersionId AND d.DocumentTypeCode='TERMS_AND_CONDITIONS'
	  AND v.PublicationStatus='PUBLISHED' AND v.EffectiveAtUtc<=@Now
	ORDER BY ty.Code;
END;
GO
CREATE OR ALTER TRIGGER leg.trg_LegalDocumentVersions_Immutable
ON leg.LegalDocumentVersions
AFTER UPDATE,DELETE
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS
	(
		SELECT 1
		FROM deleted d
		LEFT JOIN inserted i ON i.DocumentVersionId=d.DocumentVersionId
		WHERE d.PublicationStatus IN ('PUBLISHED','ARCHIVED')
		  AND (i.DocumentVersionId IS NULL OR i.LegalDocumentId<>d.LegalDocumentId
			   OR i.VersionIdentifier<>d.VersionIdentifier OR i.Title<>d.Title
			   OR i.EffectiveAtUtc<>d.EffectiveAtUtc OR i.StorageReference<>d.StorageReference
			   OR i.ContentHash<>d.ContentHash OR i.MimeType<>d.MimeType OR i.FileSizeBytes<>d.FileSizeBytes
			   OR (d.PublicationStatus='ARCHIVED' AND i.PublicationStatus<>'ARCHIVED')
			   OR (d.PublicationStatus='PUBLISHED' AND i.PublicationStatus NOT IN ('PUBLISHED','ARCHIVED')))
	)
		THROW 51610, 'Published legal document content and scope are immutable.', 1;
END;
GO
CREATE OR ALTER TRIGGER leg.trg_LegalDocumentVersionScopes_Immutable
ON leg.LegalDocumentVersionScopes
AFTER INSERT,UPDATE,DELETE
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS
	(
		SELECT 1
		FROM inserted i
		JOIN leg.LegalDocumentVersions v ON v.DocumentVersionId=i.DocumentVersionId
		WHERE v.PublicationStatus IN ('PUBLISHED','ARCHIVED')
	) OR EXISTS
	(
		SELECT 1
		FROM deleted d
		JOIN leg.LegalDocumentVersions v ON v.DocumentVersionId=d.DocumentVersionId
		WHERE v.PublicationStatus IN ('PUBLISHED','ARCHIVED')
	)
		THROW 51611, 'Published legal document scopes are immutable.', 1;
END;
GO
CREATE OR ALTER TRIGGER leg.trg_UserLegalConsents_AppendOnly
ON leg.UserLegalConsents
AFTER UPDATE,DELETE
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS (SELECT 1 FROM deleted)
		THROW 51612, 'Legal consent history is append-only.', 1;
END;
GO
