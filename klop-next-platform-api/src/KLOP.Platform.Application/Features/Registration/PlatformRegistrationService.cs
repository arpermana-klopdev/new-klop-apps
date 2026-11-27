namespace KLOP.Platform.Application;

public sealed class PlatformRegistrationPermissionService(IPlatformPermissionRepository permissionRepository)
{
    public async Task<PlatformRegistrationPermissionsResponse> Get(long userId, Guid sessionId,
        CancellationToken cancellationToken)
    {
        var permissions = await permissionRepository.GetPlatformPermissions(userId, sessionId, cancellationToken);
        return new PlatformRegistrationPermissionsResponse(
            permissions.Where(permission => permission == PlatformRegistrationPermissions.Read)
                .Distinct(StringComparer.Ordinal)
                .Order(StringComparer.Ordinal)
                .ToArray());
    }
}

public sealed class PlatformRegistrationService(IPlatformRegistrationRepository repository)
{
    public Task<PlatformRegistrationSummary?> GetSummary(string registrationType, long actorUserId,
        Guid sessionId, CancellationToken cancellationToken) =>
        repository.GetPlatformRegistrationSummary(
            RegistrationTypeCodes.Normalize(registrationType), actorUserId, sessionId, cancellationToken);

    public Task<PlatformRegistrationPage> List(PlatformRegistrationListQuery query, long actorUserId,
        Guid sessionId, CancellationToken cancellationToken)
    {
        query.RegistrationType = RegistrationTypeCodes.Normalize(query.RegistrationType);
        query.EmailVerificationStatus = string.IsNullOrWhiteSpace(query.EmailVerificationStatus)
            ? null
            : query.EmailVerificationStatus.Trim().ToUpperInvariant();
        query.ApplicationStatus = string.IsNullOrWhiteSpace(query.ApplicationStatus)
            ? null
            : query.ApplicationStatus.Trim().ToUpperInvariant();
        query.Search = string.IsNullOrWhiteSpace(query.Search) ? null : query.Search.Trim();
        return repository.ListPlatformRegistrations(query, actorUserId, sessionId, cancellationToken);
    }

    public async Task<PlatformRegistrationDetail?> Get(long registrationApplicationId, long actorUserId,
        Guid sessionId, CancellationToken cancellationToken)
    {
        var row = await repository.GetPlatformRegistration(registrationApplicationId, actorUserId,
            sessionId, cancellationToken);
        if (row is null)
            return null;

        var registrationType = row.RegistrationType;
        var profile = new PlatformRegistrationProfile(
            CompletionStatus: null,
            Personal: registrationType == RegistrationTypeCodes.Personal
                ? new PlatformPersonalRegistrationProfile(
                    row.PersonalPhoneNumber,
                    row.PersonalCountryCode,
                    row.PersonalRegion,
                    row.PersonalCity,
                    row.PersonalPostalCode,
                    row.PersonalAddressLine)
                : null,
            Organization: registrationType == RegistrationTypeCodes.Organization
                ? new PlatformOrganizationRegistrationProfile(
                    row.OrganizationType,
                    row.OrganizationCountryCode,
                    row.OrganizationRegisteredName,
                    row.OrganizationContactEmail,
                    row.OrganizationContactPhone,
                    row.OrganizationRegion,
                    row.OrganizationCity,
                    row.OrganizationPostalCode,
                    row.OrganizationAddressLine)
                : null);

        var tenant = row.TenantId is { } tenantId && row.TenantCode is not null &&
                     row.TenantType is not null && row.TenantDisplayName is not null &&
                     row.TenantStatus is not null
            ? new PlatformRegistrationTenant(tenantId, row.TenantCode, row.TenantType,
                row.TenantDisplayName, row.TenantStatus)
            : null;

        var challenge = row.LatestChallengeIssuedAtUtc is not null ||
                        row.LatestChallengeExpiresAtUtc is not null
            ? new PlatformRegistrationChallenge(
                row.LatestChallengeIssuedAtUtc is { } issued ? AsUtc(issued) : null,
                row.LatestChallengeExpiresAtUtc is { } expires ? AsUtc(expires) : null)
            : null;

        return new PlatformRegistrationDetail(
            row.RegistrationApplicationId,
            new PlatformRegistrationUser(
                row.DisplayName,
                row.Email,
                row.IsActive ? "ACTIVE" : "INACTIVE",
                AsUtc(row.UserRegisteredAtUtc),
                AsUtc(row.EmailVerifiedAtUtc)),
            new PlatformRegistrationApplication(
                registrationType,
                row.ApplicationStatus,
                AsUtc(row.ApplicationCreatedAtUtc),
                AsUtc(row.ApplicationUpdatedAtUtc),
                row.TenantId),
            profile,
            challenge,
            tenant);
    }

    public async Task<IReadOnlyList<PlatformRegistrationTimelineEvent>> GetTimeline(
        long registrationApplicationId, long actorUserId, Guid sessionId,
        CancellationToken cancellationToken)
    {
        var timeline = await repository.GetPlatformRegistrationTimeline(registrationApplicationId,
            actorUserId, sessionId, cancellationToken);
        return timeline.Select(item => new PlatformRegistrationTimelineEvent(
            AsUtc(item.OccurredAtUtc),
            item.EventCode,
            item.FromStatus,
            item.ToStatus,
            item.ActorDisplayName)).ToArray();
    }

    private static DateTime AsUtc(DateTime value) => DateTime.SpecifyKind(value, DateTimeKind.Utc);

    private static DateTime? AsUtc(DateTime? value) =>
        value is { } dateTime ? AsUtc(dateTime) : null;
}
