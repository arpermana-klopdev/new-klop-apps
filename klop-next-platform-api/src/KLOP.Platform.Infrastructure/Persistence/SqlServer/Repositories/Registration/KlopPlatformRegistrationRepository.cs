using System.Data;
using System.Text.Json;
using Dapper;
using KLOP.Platform.Application;

namespace KLOP.Platform.Infrastructure;

public sealed partial class KlopRepository
{
    public Task<PlatformRegistrationSummary?> GetPlatformRegistrationSummary(
        string registrationType, long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
        One<PlatformRegistrationSummary>("reg.usp_GetPlatformRegistrationSummary",
            PlatformRegistrationActorParameters(actorUserId, sessionId,
                ("RegistrationTypeCode", registrationType, DbType.AnsiString, 50)),
            cancellationToken);

    public async Task<PlatformRegistrationPage> ListPlatformRegistrations(
        PlatformRegistrationListQuery query, long actorUserId, Guid sessionId,
        CancellationToken cancellationToken)
    {
        var parameters = PlatformRegistrationActorParameters(actorUserId, sessionId,
            ("RegistrationTypeCode", query.RegistrationType, DbType.AnsiString, 50),
            ("Search", query.Search, DbType.String, 200),
            ("EmailVerificationStatus", query.EmailVerificationStatus, DbType.AnsiString, 20),
            ("ApplicationStatus", query.ApplicationStatus, DbType.AnsiString, 30),
            ("PageNumber", query.PageNumber, DbType.Int32, null),
            ("PageSize", query.PageSize, DbType.Int32, null));

        using var connection = factory.Open();
        var rows = (await connection.QueryAsync<PlatformRegistrationListRow>(new CommandDefinition(
            "reg.usp_ListPlatformRegistrations",
            parameters,
            commandType: CommandType.StoredProcedure,
            commandTimeout: settings.CommandTimeoutSeconds,
            cancellationToken: cancellationToken))).AsList();
        var page = rows.FirstOrDefault()
            ?? throw new InvalidOperationException("The registration listing procedure returned no page metadata.");
        var items = rows
            .Where(row => row.RegistrationApplicationId is not null)
            .Select(row => new PlatformRegistrationListItem(
                row.RegistrationApplicationId!.Value,
                row.DisplayName ?? throw new InvalidOperationException("A registration list row has no display name."),
                row.Email ?? throw new InvalidOperationException("A registration list row has no email address."),
                AsUtc(row.EmailVerifiedAtUtc),
                row.ApplicationStatus ?? throw new InvalidOperationException("A registration list row has no application status."),
                row.RegistrationType ?? throw new InvalidOperationException("A registration list row has no registration type."),
                AsUtc(row.RegisteredAtUtc
                    ?? throw new InvalidOperationException("A registration list row has no registration timestamp."))))
            .ToArray();

        using var statusDocument = JsonDocument.Parse(page.ApplicationStatusesJson);
        var applicationStatuses = statusDocument.RootElement.EnumerateArray()
            .Select(status => status.GetProperty("Code").GetString()
                ?? throw new InvalidOperationException("The registration status catalog contains a null code."))
            .ToArray();
        return new PlatformRegistrationPage(items, page.PageNumber, page.PageSize, page.TotalCount,
            page.TotalPages, applicationStatuses);
    }

    public Task<PlatformRegistrationDetailRow?> GetPlatformRegistration(
        long registrationApplicationId, long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        return One<PlatformRegistrationDetailRow>("reg.usp_GetPlatformRegistration",
            PlatformRegistrationActorParameters(actorUserId, sessionId,
                ("RegistrationApplicationId", registrationApplicationId, DbType.Int64, null)),
            cancellationToken);
    }

    public async Task<IReadOnlyList<PlatformRegistrationTimelineEvent>> GetPlatformRegistrationTimeline(
        long registrationApplicationId, long actorUserId, Guid sessionId, CancellationToken cancellationToken)
    {
        var rows = await Many<PlatformRegistrationTimelineRow>("reg.usp_GetPlatformRegistrationTimeline",
            PlatformRegistrationActorParameters(actorUserId, sessionId,
                ("RegistrationApplicationId", registrationApplicationId, DbType.Int64, null)),
            cancellationToken);
        return rows.Select(row => new PlatformRegistrationTimelineEvent(
            AsUtc(row.OccurredAtUtc), row.EventCode, row.FromStatus, row.ToStatus, row.ActorDisplayName))
            .ToArray();
    }

    private static DynamicParameters PlatformRegistrationActorParameters(
        long actorUserId,
        Guid sessionId,
        params (string Name, object? Value, DbType Type, int? Size)[] values)
    {
        var parameters = new DynamicParameters();
        parameters.Add("ActorUserId", actorUserId, DbType.Int64);
        parameters.Add("PublicSessionId", sessionId, DbType.Guid);
        foreach (var (name, value, type, size) in values)
            parameters.Add(name, value, type, size: size);
        return parameters;
    }

    private static DateTime AsUtc(DateTime value) => DateTime.SpecifyKind(value, DateTimeKind.Utc);

    private static DateTime? AsUtc(DateTime? value) =>
        value is { } dateTime ? AsUtc(dateTime) : null;
}
