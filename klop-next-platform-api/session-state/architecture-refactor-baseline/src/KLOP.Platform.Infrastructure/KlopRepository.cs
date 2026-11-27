using System.Data;
using Dapper;
using KLOP.Platform.Application;
using KLOP.Platform.Domain;
using Microsoft.Data.SqlClient;

namespace KLOP.Platform.Infrastructure;

// No SQL statements, table DML, or master numeric IDs in API code. Only versioned SP contracts.
public sealed class KlopRepository(SqlConnectionFactory factory, RuntimeSettings settings) : IPlatformRepository
{
    private async Task Execute(string name, DynamicParameters p, CancellationToken ct)
    {
        using var c = factory.Open();
        await c.ExecuteAsync(new CommandDefinition(name, p, commandType:CommandType.StoredProcedure,
            commandTimeout: settings.CommandTimeoutSeconds, cancellationToken:ct));
    }
    private async Task<T?> One<T>(string name, DynamicParameters p, CancellationToken ct)
    {
        using var c = factory.Open();
        return await c.QuerySingleOrDefaultAsync<T>(new CommandDefinition(name,p,
            commandType:CommandType.StoredProcedure, commandTimeout:settings.CommandTimeoutSeconds,cancellationToken:ct));
    }
    private async Task<IReadOnlyList<T>> Many<T>(string name, DynamicParameters p, CancellationToken ct)
    {
        using var c = factory.Open();
        var items = await c.QueryAsync<T>(new CommandDefinition(name,p,
            commandType:CommandType.StoredProcedure,commandTimeout:settings.CommandTimeoutSeconds,cancellationToken:ct));
        return items.AsList();
    }
    public async Task<(long UserId,long ChallengeId)> Register(string email,string displayName,string passwordHash,byte[] tokenHash,
        string req,Guid correlation,CancellationToken ct)
    {
        var p = new DynamicParameters();
        p.Add("Email",email,DbType.String,size:320); p.Add("DisplayName",displayName,DbType.String,size:150);
        p.Add("PasswordHash",passwordHash,DbType.String,size:1024);
        p.Add("VerificationTokenHash",tokenHash,DbType.Binary,size:32);
        p.Add("VerificationExpiresAtUtc",DateTime.UtcNow.AddHours(settings.EmailVerificationHours),DbType.DateTime2);
        p.Add("RequestId",req,DbType.AnsiString,size:100);p.Add("CorrelationId",correlation,DbType.Guid);
        p.Add("UserId",dbType:DbType.Int64,direction:ParameterDirection.Output);
        p.Add("ChallengeId",dbType:DbType.Int64,direction:ParameterDirection.Output);
        try
        {
            await Execute("iam.usp_RegisterLocalUser",p,ct);
        }
        catch (SqlException exception) when (exception.Number == 52113)
        {
            throw new DuplicateRegistrationException();
        }
        return(p.Get<long>("UserId"),p.Get<long>("ChallengeId"));
    }
    public Task ConfirmEmail(long userId,byte[] tokenHash,string req,Guid correlation,CancellationToken ct)
    {
        var p = Params(("UserId",userId),("VerificationTokenHash",tokenHash),("RequestId",req),("CorrelationId",correlation));
        return Execute("iam.usp_ConfirmEmail",p,ct);
    }
    public async Task<long?> Resend(string email,byte[] hash,string req,Guid correlation,CancellationToken ct)
    {
        var p=Params(("Email",email),("TokenHash",hash),("ExpiresAtUtc",DateTime.UtcNow.AddHours(settings.EmailVerificationHours)),
            ("RequestId",req),("CorrelationId",correlation));
        p.Add("UserId",dbType:DbType.Int64,direction:ParameterDirection.Output);
        await Execute("iam.usp_IssueEmailVerificationChallenge",p,ct);
        return p.Get<long?>("UserId");
    }
    public Task<LoginCandidate?> GetLoginCandidate(string email,CancellationToken ct) =>
        One<LoginCandidate>("iam.usp_GetLocalLoginCandidate",Params(("NormalizedEmail",email)),ct);
    public Task RecordLoginFailure(long userId,Guid correlation,CancellationToken ct) =>
        Execute("iam.usp_RecordLocalLoginFailure",Params(("UserId",userId),("CorrelationId",correlation)),ct);
    public async Task<Guid> CreateSession(long userId,byte[] refreshHash,Guid correlation,string req,CancellationToken ct)
    {
        var lifetimeEnd = DateTime.UtcNow.AddDays(settings.RefreshDays);
        var p=Params(("UserId",userId),("SessionExpiresAtUtc",lifetimeEnd),
            ("RefreshTokenHash",refreshHash),("RefreshExpiresAtUtc",lifetimeEnd),
            ("RequestId",req),("CorrelationId",correlation));
        p.Add("PublicSessionId",dbType:DbType.Guid,direction:ParameterDirection.Output);
        await Execute("iam.usp_CreateAuthSession",p,ct);
        return p.Get<Guid>("PublicSessionId");
    }
    public Task ValidateSession(long userId,Guid sid,long? tenantId,string? permission,CancellationToken ct) =>
        Execute("iam.usp_ValidateSessionAccess",Params(("UserId",userId),("PublicSessionId",sid),
            ("TenantId",tenantId),("PermissionCode",permission)),ct);
    public async Task<long> RotateRefresh(Guid sid,byte[] oldHash,byte[] newHash,Guid correlation,CancellationToken ct)
    {
        var p=Params(("PublicSessionId",sid),("OldTokenHash",oldHash),("NewTokenHash",newHash),
            ("NewExpiresAtUtc",DateTime.UtcNow.AddDays(settings.RefreshDays)),("CorrelationId",correlation));
        p.Add("UserId",dbType:DbType.Int64,direction:ParameterDirection.Output);
        await Execute("iam.usp_RotateRefreshToken",p,ct);
        return p.Get<long>("UserId");
    }
    public Task RevokeSession(long userId,Guid sid,Guid correlation,CancellationToken ct) =>
        Execute("iam.usp_RevokeAuthSession",Params(("UserId",userId),("PublicSessionId",sid),
            ("CorrelationId",correlation)),ct);
    public Task<Profile?> GetProfile(long userId,CancellationToken ct) =>
        One<Profile>("iam.usp_GetUserProfile",Params(("UserId",userId)),ct);
    public Task<IReadOnlyList<TenantSummary>> MyTenants(long userId,CancellationToken ct) =>
        Many<TenantSummary>("ten.usp_ListMyTenants",Params(("UserId",userId)),ct);
    public Task<IReadOnlyList<OrganizationType>> OrganizationTypes(CancellationToken ct) =>
        Many<OrganizationType>("mst.usp_OrganizationType_GetAll",Params(("ActiveOnly",true)),ct);
    public Task<IReadOnlyList<TenantType>> TenantTypes(CancellationToken ct) =>
        Many<TenantType>("mst.usp_TenantType_GetAll",Params(("ActiveOnly",true)),ct);
    public Task<ConfigurationEntry?> GetConfiguration(string key,CancellationToken ct)
    {
        var p=new DynamicParameters();
        p.Add("ConfigurationKey",key,DbType.AnsiString,size:150);
        return One<ConfigurationEntry>("cfg.usp_Configuration_GetByKey",p,ct);
    }
    public async Task<(long TenantId,long MembershipId)> CreateTenant(long userId,string code,string type,string name,
        long? orgType,string? registered,string req,Guid correlation,CancellationToken ct)
    {
        var p=Params(("OwnerUserId",userId),("TenantCode",code),("TenantTypeCode",type),
            ("DisplayName",name),("OrganizationTypeId",orgType),("RegisteredName",registered),
            ("RequestId",req),("CorrelationId",correlation));
        p.Add("TenantId",dbType:DbType.Int64,direction:ParameterDirection.Output);
        p.Add("MembershipId",dbType:DbType.Int64,direction:ParameterDirection.Output);
        await Execute("ten.usp_CreateTenantWithOwner",p,ct);
        return(p.Get<long>("TenantId"),p.Get<long>("MembershipId"));
    }
    public async Task<long> Invite(long tenant,long actor,long invitee,string req,Guid correlation,CancellationToken ct)
    {
        var p=Params(("TenantId",tenant),("ActorUserId",actor),("InviteeUserId",invitee),
            ("RequestId",req),("CorrelationId",correlation));
        p.Add("MembershipId",dbType:DbType.Int64,direction:ParameterDirection.Output);
        await Execute("ten.usp_InviteExistingUser",p,ct);
        return p.Get<long>("MembershipId");
    }
    public Task Accept(long membership,long actor,string req,Guid correlation,CancellationToken ct) =>
        Execute("ten.usp_AcceptMembership",Params(("MembershipId",membership),("ActorUserId",actor),
            ("RequestId",req),("CorrelationId",correlation)),ct);
    public Task Remove(long membership,long actor,string req,Guid correlation,CancellationToken ct) =>
        Execute("ten.usp_RemoveTenantMember",Params(("MembershipId",membership),("ActorUserId",actor),
            ("RequestId",req),("CorrelationId",correlation)),ct);
    public Task AssignRole(long membership,long actor,string role,string req,Guid correlation,CancellationToken ct) =>
        Execute("iam.usp_AssignTenantRole",Params(("MembershipId",membership),("ActorUserId",actor),
            ("RoleCode",role),("RequestId",req),("CorrelationId",correlation)),ct);
    public Task RevokeRole(long membership,long actor,string role,string req,Guid correlation,CancellationToken ct) =>
        Execute("iam.usp_RevokeTenantRole",Params(("MembershipId",membership),("ActorUserId",actor),
            ("RoleCode",role),("RequestId",req),("CorrelationId",correlation)),ct);
    public async Task CheckDatabase(CancellationToken ct)
    {
        var p=new DynamicParameters();
        p.Add("ConfigurationKey","auth.access_token_minutes",DbType.AnsiString,size:150);
        var setting = await One<ConfigurationEntry>("cfg.usp_Configuration_GetByKey",p,ct);
        if (setting is null || setting.StorageType != "PLAIN" || setting.ValueType != "INTEGER")
            throw new InvalidOperationException("SQL readiness configuration is unavailable.");
    }
    private static DynamicParameters Params(params (string Name,object? Value)[] items)
    {
        var p=new DynamicParameters();
        foreach(var (n,v) in items)
        {
            var type = n switch
            {
                "RequestId" or "RoleCode" or "TenantCode" or "TenantTypeCode" or "PermissionCode" =>
                    DbType.AnsiString,
                "TenantId" or "OrganizationTypeId" => DbType.Int64,
                "RegisteredName" => DbType.String,
                _ => v switch
                {
                    byte[] => DbType.Binary,
                    Guid => DbType.Guid,
                    long => DbType.Int64,
                    bool => DbType.Boolean,
                    DateTime => DbType.DateTime2,
                    string => DbType.String,
                    _ => (DbType?)null
                }
            };
            p.Add(n,v,type);
        }
        return p;
    }
}
