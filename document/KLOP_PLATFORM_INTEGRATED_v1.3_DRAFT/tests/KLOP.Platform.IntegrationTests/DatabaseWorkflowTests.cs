using System.Data;
using Dapper;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Xunit;
using Xunit.Abstractions;

namespace KLOP.Platform.IntegrationTests;

// DESTRUCTIVE fixture: only a disposable SQL Server Development clone with test-only identity.
// Procedure calls commit independently; there is no transaction rollback wrapper.
public sealed class DatabaseWorkflowTests(ITestOutputHelper output)
{
    private static (KlopRepository Repo,SqlConnectionFactory Factory) Setup()
    {
        if(Environment.GetEnvironmentVariable("KLOP_TEST_ALLOW_MUTATION") != "I_UNDERSTAND_TEST_DATA_IS_PERSISTENT")
            throw new InvalidOperationException("Integration tests were NOT run. Explicit disposable-db opt-in is required.");
        var server=Environment.GetEnvironmentVariable("KLOP_TEST_SQL_SERVER");
        var db=Environment.GetEnvironmentVariable("KLOP_TEST_SQL_DATABASE");
        var auth=Environment.GetEnvironmentVariable("KLOP_TEST_SQL_AUTH")??"IntegratedSecurity";
        if(string.IsNullOrWhiteSpace(server)||string.IsNullOrWhiteSpace(db)||
            !db.EndsWith("_TEST",StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Integration database must be an isolated name ending _TEST.");
        var c=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?> {
            ["Sql:Server"]=server,["Sql:Database"]=db,["Sql:Authentication"]=auth }).Build();
        var factory=new SqlConnectionFactory(c);
        var settings=RuntimeSettings.Load(factory).GetAwaiter().GetResult();
        return (new KlopRepository(factory,settings),factory);
    }
    private static async Task<long> NewVerifiedUser(KlopRepository repo,string suffix)
    {
        var passHash=new PasswordCodec().Hash("TemporaryDevelopmentPass!456");
        var raw=SecretTokens.NewToken();
        var email=$"test-{suffix}@example.invalid";
        var created=await repo.Register(email,"Test User",passHash,SecretTokens.Sha256(raw),
            "klop-integration",Guid.NewGuid(),CancellationToken.None);
        await repo.ConfirmEmail(created.UserId,SecretTokens.Sha256(raw),"klop-integration",Guid.NewGuid(),CancellationToken.None);
        return created.UserId;
    }
    private static async Task<long> CountOwners(SqlConnectionFactory factory,long tenantId)
    {
        using var c=factory.Open();
        return await c.ExecuteScalarAsync<long>(@"
            SELECT COUNT_BIG(*) FROM ten.TenantMemberships m
            JOIN mst.MembershipStatuses ms ON ms.MembershipStatusId=m.MembershipStatusId AND ms.Code='ACTIVE'
            JOIN iam.TenantRoleAssignments a ON a.MembershipId=m.MembershipId
            JOIN mst.Roles r ON r.RoleId=a.RoleId AND r.Code='OWNER'
            JOIN mst.RoleScopes rs ON rs.RoleScopeId=r.RoleScopeId AND rs.Code='TENANT'
            WHERE m.TenantId=@tenantId",new{tenantId});
    }
    [Fact]
    public async Task Registration_Tenant_OwnerSecurity_AndSessionRotation()
    {
        var (repo,factory)=Setup();
        var suffix=Guid.NewGuid().ToString("N")[..12];
        var user=await NewVerifiedUser(repo,suffix);
        Assert.NotNull(await repo.GetProfile(user,CancellationToken.None));
        var personal=await repo.CreateTenant(user,"T"+suffix,"PERSONAL","Integration Personal",
            null,null,"integration",Guid.NewGuid(),CancellationToken.None);
        Assert.Equal(1,await CountOwners(factory,personal.TenantId));
        await Assert.ThrowsAsync<SqlException>(()=>repo.RevokeRole(personal.MembershipId,user,"OWNER",
            "integration",Guid.NewGuid(),CancellationToken.None));
        Assert.Equal(1,await CountOwners(factory,personal.TenantId));
        await Assert.ThrowsAsync<SqlException>(()=>repo.Remove(personal.MembershipId,user,
            "integration",Guid.NewGuid(),CancellationToken.None));
        Assert.Equal(1,await CountOwners(factory,personal.TenantId));
        var old=SecretTokens.NewToken();
        var sid=await repo.CreateSession(user,SecretTokens.Sha256(old),Guid.NewGuid(),"integration",CancellationToken.None);
        await repo.ValidateSession(user,sid,personal.TenantId,"tenant.read",CancellationToken.None);
        var newer=SecretTokens.NewToken();
        var fromRotate=await repo.RotateRefresh(sid,SecretTokens.Sha256(old),SecretTokens.Sha256(newer),
            Guid.NewGuid(),CancellationToken.None);
        Assert.Equal(user,fromRotate);
        await Assert.ThrowsAsync<SqlException>(()=>repo.RotateRefresh(sid,SecretTokens.Sha256(old),
            SecretTokens.Sha256(SecretTokens.NewToken()),Guid.NewGuid(),CancellationToken.None));
        await Assert.ThrowsAsync<SqlException>(()=>repo.ValidateSession(user,sid,null,null,CancellationToken.None));
        output.WriteLine($"CREATED PERSISTENT TEST FIXTURE: user={user}, tenant={personal.TenantId}, session={sid}");
    }
    [Fact]
    public async Task CrossTenantAndConcurrentOwnerProtection()
    {
        var (repo,factory)=Setup();
        var suffix=Guid.NewGuid().ToString("N")[..12];
        var a=await NewVerifiedUser(repo,suffix+"a");
        var b=await NewVerifiedUser(repo,suffix+"b");
        var types=await repo.OrganizationTypes(CancellationToken.None);
        var orgType=types.FirstOrDefault();
        Assert.NotNull(orgType);
        var org=await repo.CreateTenant(a,"O"+suffix,"ORGANIZATION","Integration Organization",
            orgType!.OrganizationTypeId,"Integration Org", "integration",Guid.NewGuid(),CancellationToken.None);
        var member=await repo.Invite(org.TenantId,a,b,"integration",Guid.NewGuid(),CancellationToken.None);
        await repo.Accept(member,b,"integration",Guid.NewGuid(),CancellationToken.None);
        await repo.AssignRole(member,a,"OWNER","integration",Guid.NewGuid(),CancellationToken.None);
        Assert.Equal(2,await CountOwners(factory,org.TenantId));
        // Two concurrent requests using separate SQL connections through the repository.
        async Task<bool> Attempt(long memberId,long actorId)
        {
            try { await repo.RevokeRole(memberId,actorId,"OWNER","integration",Guid.NewGuid(),CancellationToken.None); return true; }
            catch(SqlException) {return false;}
        }
        var results=await Task.WhenAll(Attempt(member,a),Attempt(org.MembershipId,b));
        Assert.True(results.Count(x=>x)==1,"Exactly one owner revocation should succeed.");
        Assert.Equal(1,await CountOwners(factory,org.TenantId));
        output.WriteLine($"PERSISTENT TEST FIXTURE: tenant={org.TenantId}, owners after race=1");
    }
    [Fact]
    public async Task RejectedMasterCodeAndDuplicateEmail()
    {
        var (repo,_)=Setup();
        var suffix=Guid.NewGuid().ToString("N")[..12];
        var user=await NewVerifiedUser(repo,suffix);
        await Assert.ThrowsAsync<SqlException>(()=>repo.CreateTenant(user,"T"+suffix,"NO_SUCH_TYPE",
            "Invalid",null,null,"integration",Guid.NewGuid(),CancellationToken.None));
        await Assert.ThrowsAsync<SqlException>(()=>repo.Register($"test-{suffix}@example.invalid","Duplicate",
            new PasswordCodec().Hash("TemporaryDevelopmentPass!456"),SecretTokens.Sha256(SecretTokens.NewToken()),
            "integration",Guid.NewGuid(),CancellationToken.None));
    }
}
