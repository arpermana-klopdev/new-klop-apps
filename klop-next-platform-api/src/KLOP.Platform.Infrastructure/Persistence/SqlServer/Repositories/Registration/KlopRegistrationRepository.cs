using System.Data;
using Dapper;
using KLOP.Platform.Application;

namespace KLOP.Platform.Infrastructure;

public sealed partial class KlopRepository
{
    public Task<LegalTermsDocument?> GetCurrentTerms(string registrationType, CancellationToken cancellationToken) =>
        One<LegalTermsDocument>("leg.usp_GetCurrentTerms", Params(("RegistrationTypeCode", registrationType)),
            cancellationToken);

    public Task<LegalTermsDocument?> GetPublicTermsFile(Guid documentVersionId,
        CancellationToken cancellationToken) =>
        One<LegalTermsDocument>("leg.usp_GetPublicTermsFile", Params(("DocumentVersionId", documentVersionId)),
            cancellationToken);

    public Task<OnboardingApplication?> GetMyOnboarding(long userId, CancellationToken cancellationToken) =>
        One<OnboardingApplication>("reg.usp_GetMyApplication", Params(("UserId", userId)), cancellationToken);

    public Task<OnboardingApplication?> GetOnboarding(long userId, long applicationId,
        CancellationToken cancellationToken) =>
        One<OnboardingApplication>("reg.usp_GetApplicationForOwner",
            Params(("UserId", userId), ("ApplicationId", applicationId)), cancellationToken);

    public Task<OnboardingApplication?> SavePersonalDraft(long userId, PersonalOnboardingDraftRequest request,
        RequestMetadata metadata, CancellationToken cancellationToken)
    {
        RowVersionCodec.TryDecode(request.RowVersion, out var rowVersion);
        var parameters = Params(("UserId", userId), ("ExpectedRowVersion", rowVersion),
            ("PhoneNumber", request.PhoneNumber), ("CountryCode", NormalizeCountryCode(request.CountryCode)),
            ("Region", request.Region), ("City", request.City), ("PostalCode", request.PostalCode),
            ("AddressLine", request.AddressLine), ("RequestId", metadata.RequestId),
            ("CorrelationId", metadata.CorrelationId));
        return One<OnboardingApplication>("reg.usp_SavePersonalDraft", parameters, cancellationToken);
    }

    public Task<OnboardingApplication?> SaveOrganizationDraft(long userId,
        OrganizationOnboardingDraftRequest request, RequestMetadata metadata, CancellationToken cancellationToken)
    {
        RowVersionCodec.TryDecode(request.RowVersion, out var rowVersion);
        var parameters = Params(("UserId", userId), ("ExpectedRowVersion", rowVersion),
            ("OrganizationTypeId", request.OrganizationTypeId), ("CountryCode", NormalizeCountryCode(request.CountryCode)),
            ("RegisteredName", request.RegisteredName), ("ContactEmail", request.ContactEmail),
            ("ContactPhone", request.ContactPhone), ("Region", request.Region), ("City", request.City),
            ("PostalCode", request.PostalCode), ("AddressLine", request.AddressLine),
            ("RequestId", metadata.RequestId), ("CorrelationId", metadata.CorrelationId));
        return One<OnboardingApplication>("reg.usp_SaveOrganizationDraft", parameters, cancellationToken);
    }

    public Task<IReadOnlyList<OrganizationIdentityRequirement>> GetOrganizationRequirements(long userId,
        CancellationToken cancellationToken) =>
        Many<OrganizationIdentityRequirement>("reg.usp_GetOrganizationRequirements",
            Params(("UserId", userId)), cancellationToken);

    public Task<OnboardingApplication?> SubmitOnboarding(long userId, OnboardingSubmitRequest request,
        RequestMetadata metadata, CancellationToken cancellationToken)
    {
        RowVersionCodec.TryDecode(request.RowVersion, out var rowVersion);
        return One<OnboardingApplication>("reg.usp_SubmitOnboarding",
            Params(("UserId", userId), ("ExpectedRowVersion", rowVersion), ("RequestId", metadata.RequestId),
                ("CorrelationId", metadata.CorrelationId)), cancellationToken);
    }

    private static string? NormalizeCountryCode(string? countryCode) =>
        string.IsNullOrWhiteSpace(countryCode) ? null : countryCode.Trim().ToUpperInvariant();
}
