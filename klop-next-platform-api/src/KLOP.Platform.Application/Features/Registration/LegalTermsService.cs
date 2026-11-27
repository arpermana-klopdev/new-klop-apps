using System.Globalization;
using System.Security.Cryptography;

namespace KLOP.Platform.Application;

public sealed class LegalTermsService(
    IRegistrationRepository registrationRepository,
    IPlatformRepository platformRepository,
    ILegalDocumentStorage storage)
{
    public async Task<LegalTermsMetadata?> GetCurrent(string registrationType, CancellationToken cancellationToken)
    {
        var normalizedType = RegistrationTypeCodes.Normalize(registrationType);
        var terms = await registrationRepository.GetCurrentTerms(normalizedType, cancellationToken);
        if (terms is null)
            return null;

        ValidatePublishedTerms(terms, normalizedType);
        return ToMetadata(terms);
    }

    public async Task<(Stream Stream, LegalTermsMetadata Metadata)> OpenPublishedFile(
        Guid documentVersionId, CancellationToken cancellationToken)
    {
        var terms = await registrationRepository.GetPublicTermsFile(documentVersionId, cancellationToken);
        if (terms is null)
            throw new LegalDocumentStorageUnavailableException("The published legal document is unavailable.");
        ValidatePublishedTerms(terms, null);

        var maximumSize = await platformRepository.GetConfiguration("legal.maximum_upload_bytes", cancellationToken);
        if (maximumSize is null || maximumSize.ValueType != "INTEGER" || maximumSize.StorageType != "PLAIN" ||
            !long.TryParse(maximumSize.ConfigurationValue, NumberStyles.None, CultureInfo.InvariantCulture,
                out var maximumBytes) || maximumBytes <= 0 || terms.FileSizeBytes > maximumBytes)
            throw new LegalDocumentStorageUnavailableException("The legal document storage policy is unavailable.");

        var stream = await storage.OpenPdf(terms.StorageReference, terms.FileSizeBytes, maximumBytes,
            terms.ContentHash, cancellationToken);
        return (stream, ToMetadata(terms));
    }

    private static void ValidatePublishedTerms(LegalTermsDocument terms, string? expectedType)
    {
        if (terms.DocumentVersionId == Guid.Empty || terms.DocumentTypeCode != "TERMS_AND_CONDITIONS" ||
            terms.PublicationStatus != "PUBLISHED" || terms.EffectiveAtUtc > DateTime.UtcNow ||
            (expectedType is not null && !string.Equals(terms.RegistrationTypeCode, expectedType,
                StringComparison.OrdinalIgnoreCase)) || terms.ContentHash.Length != 32 ||
            terms.MimeType != "application/pdf" || terms.FileSizeBytes <= 0 ||
            string.IsNullOrWhiteSpace(terms.StorageReference))
            throw new LegalDocumentStorageUnavailableException("The published legal document metadata is invalid.");
    }

    private static LegalTermsMetadata ToMetadata(LegalTermsDocument terms) => new(
        terms.DocumentVersionId,
        terms.Title,
        terms.RegistrationTypeCode,
        terms.VersionIdentifier,
        DateTime.SpecifyKind(terms.EffectiveAtUtc, DateTimeKind.Utc),
        $"/api/v1/public/legal/terms/{terms.DocumentVersionId:D}/file",
        Convert.ToHexString(terms.ContentHash).ToLowerInvariant(),
        terms.PublicationStatus);
}
