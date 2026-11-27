using KLOP.Platform.Domain;

namespace KLOP.Platform.Application;

public static class RegistrationTypeCodes
{
    public const string Personal = "PERSONAL";
    public const string Organization = "ORGANIZATION";

    public static bool IsSupported(string? value) =>
        string.Equals(value?.Trim(), Personal, StringComparison.OrdinalIgnoreCase) ||
        string.Equals(value?.Trim(), Organization, StringComparison.OrdinalIgnoreCase);

    public static string Normalize(string value) => value.Trim().ToUpperInvariant();
}

public sealed class LegalTermsDocument
{
    public Guid DocumentVersionId { get; set; }
    public string DocumentTypeCode { get; set; } = "";
    public string Title { get; set; } = "";
    public string VersionIdentifier { get; set; } = "";
    public string RegistrationTypeCode { get; set; } = "";
    public DateTime EffectiveAtUtc { get; set; }
    public string PublicationStatus { get; set; } = "";
    public string StorageReference { get; set; } = "";
    public byte[] ContentHash { get; set; } = [];
    public string MimeType { get; set; } = "";
    public long FileSizeBytes { get; set; }
}

public sealed record LegalTermsMetadata(
    Guid DocumentVersionId,
    string Title,
    string RegistrationType,
    string Version,
    DateTime EffectiveAtUtc,
    string DocumentUrl,
    string ContentHash,
    string PublicationStatus);

public sealed class OnboardingApplication
{
    public long ApplicationId { get; set; }
    public string RegistrationType { get; set; } = "";
    public string OnboardingStatus { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
    public DateTime? CompletedAtUtc { get; set; }
    public long? TenantId { get; set; }
    public byte[] RowVersion { get; set; } = [];
}

public sealed record OnboardingApplicationResponse(
    long ApplicationId,
    string RegistrationType,
    string OnboardingStatus,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc,
    DateTime? CompletedAtUtc,
    long? TenantId,
    string RowVersion);

public sealed record PersonalOnboardingDraftRequest(
    string RowVersion,
    string? PhoneNumber,
    string? CountryCode,
    string? Region,
    string? City,
    string? PostalCode,
    string? AddressLine);

public sealed record OrganizationOnboardingDraftRequest(
    string RowVersion,
    long? OrganizationTypeId,
    string? CountryCode,
    string? RegisteredName,
    string? ContactEmail,
    string? ContactPhone,
    string? Region,
    string? City,
    string? PostalCode,
    string? AddressLine);

public sealed record OnboardingSubmitRequest(string RowVersion);

public sealed class OrganizationIdentityRequirement
{
    public long RequirementGroupId { get; set; }
    public string RequirementGroupCode { get; set; } = "";
    public string SelectionMode { get; set; } = "";
    public int MinimumRequired { get; set; }
    public long IdentityDocumentTypeId { get; set; }
    public string IdentityDocumentTypeCode { get; set; } = "";
    public bool RequiresNumber { get; set; }
    public bool AllowsFileUpload { get; set; }
    public string RequirementLevel { get; set; } = "";
    public DateTime GroupEffectiveFromUtc { get; set; }
    public DateTime? GroupEffectiveToUtc { get; set; }
    public DateTime RequirementEffectiveFromUtc { get; set; }
    public DateTime? RequirementEffectiveToUtc { get; set; }
}

public sealed record OrganizationRequirementResponse(
    long RequirementGroupId,
    string RequirementGroupCode,
    string SelectionMode,
    int MinimumRequired,
    long IdentityDocumentTypeId,
    string IdentityDocumentTypeCode,
    bool RequiresNumber,
    bool AllowsFileUpload,
    string RequirementLevel,
    DateTime GroupEffectiveFromUtc,
    DateTime? GroupEffectiveToUtc,
    DateTime RequirementEffectiveFromUtc,
    DateTime? RequirementEffectiveToUtc);

public static class RowVersionCodec
{
    public static bool TryDecode(string? value, out byte[] rowVersion)
    {
        rowVersion = [];
        if (string.IsNullOrWhiteSpace(value))
            return false;

        try
        {
            rowVersion = Convert.FromBase64String(value);
            return rowVersion.Length == 8;
        }
        catch (FormatException)
        {
            return false;
        }
    }
}

public interface IRegistrationRepository
{
    Task<LegalTermsDocument?> GetCurrentTerms(string registrationType, CancellationToken cancellationToken);
    Task<LegalTermsDocument?> GetPublicTermsFile(Guid documentVersionId, CancellationToken cancellationToken);
    Task<OnboardingApplication?> GetMyOnboarding(long userId, CancellationToken cancellationToken);
    Task<OnboardingApplication?> GetOnboarding(long userId, long applicationId, CancellationToken cancellationToken);
    Task<OnboardingApplication?> SavePersonalDraft(long userId, PersonalOnboardingDraftRequest request,
        RequestMetadata metadata, CancellationToken cancellationToken);
    Task<OnboardingApplication?> SaveOrganizationDraft(long userId, OrganizationOnboardingDraftRequest request,
        RequestMetadata metadata, CancellationToken cancellationToken);
    Task<IReadOnlyList<OrganizationIdentityRequirement>> GetOrganizationRequirements(long userId,
        CancellationToken cancellationToken);
    Task<OnboardingApplication?> SubmitOnboarding(long userId, OnboardingSubmitRequest request,
        RequestMetadata metadata, CancellationToken cancellationToken);
}

public interface ILegalDocumentStorage
{
    Task<Stream> OpenPdf(string storageReference, long expectedSizeBytes, long maximumSizeBytes,
        byte[] expectedSha256, CancellationToken cancellationToken);
    Task<StoredLegalDocument> SavePdf(Stream source, long expectedSizeBytes, long maximumSizeBytes,
        CancellationToken cancellationToken);
    Task DeletePdf(string storageReference, CancellationToken cancellationToken);
}

public sealed class LegalDocumentStorageUnavailableException(string reason) : Exception(reason);
public sealed class OrganizationRequirementsUnavailableException() : Exception("Organization requirements are unavailable.");
