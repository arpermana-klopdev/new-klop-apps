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
    private sealed class RuntimeIdentity
    {
        public string DatabaseName { get; set; } = "";
        public string DatabaseUser { get; set; } = "";
        public int IsSysadmin { get; set; }
        public int IsDbOwner { get; set; }
        public int IsDbDdlAdmin { get; set; }
        public int IsDbDatareader { get; set; }
        public int IsDbDatawriter { get; set; }
        public int IsRuntimeRoleMember { get; set; }
    }

    private static async Task<KlopRepository> Setup()
    {
        if(Environment.GetEnvironmentVariable("KLOP_TEST_ALLOW_MUTATION") != "I_UNDERSTAND_TEST_DATA_IS_PERSISTENT")
            throw new InvalidOperationException("Integration tests were NOT run. Explicit disposable-db opt-in is required.");
        var server=Environment.GetEnvironmentVariable("KLOP_TEST_SQL_SERVER");
        var db=Environment.GetEnvironmentVariable("KLOP_TEST_SQL_DATABASE");
        var approvalTicket=Environment.GetEnvironmentVariable("KLOP_TEST_APPROVAL_TICKET");
        var auth=Environment.GetEnvironmentVariable("KLOP_TEST_SQL_AUTH")??"IntegratedSecurity";
        if(!string.Equals(server,"DEV-PC\\SQLEXPRESS",StringComparison.OrdinalIgnoreCase)||
            !string.Equals(db,"KlopPlatformDB_TEST",StringComparison.OrdinalIgnoreCase)||
            string.IsNullOrWhiteSpace(approvalTicket))
            throw new InvalidOperationException("Integration tests require the approved DEV-PC\\SQLEXPRESS / KlopPlatformDB_TEST target and approval ticket.");
        var c=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?> {
            ["Sql:Server"]=server,["Sql:Database"]=db,["Sql:Authentication"]=auth }).Build();
        var factory=new SqlConnectionFactory(c);
        using(var connection=factory.Open())
        {
            var identity=await connection.QuerySingleAsync<RuntimeIdentity>(@"
                SELECT DB_NAME() AS DatabaseName, USER_NAME() AS DatabaseUser,
                    IS_SRVROLEMEMBER(N'sysadmin') AS IsSysadmin,
                    IS_ROLEMEMBER(N'db_owner') AS IsDbOwner,
                    IS_ROLEMEMBER(N'db_ddladmin') AS IsDbDdlAdmin,
                    IS_ROLEMEMBER(N'db_datareader') AS IsDbDatareader,
                    IS_ROLEMEMBER(N'db_datawriter') AS IsDbDatawriter,
                    IS_ROLEMEMBER(N'klop_app_runtime') AS IsRuntimeRoleMember");
            if(identity.DatabaseName!="KlopPlatformDB_TEST" ||
                identity.DatabaseUser!="KLOP_PLATFORM_TEST_RUNTIME" ||
                identity.IsSysadmin!=0 || identity.IsDbOwner!=0 ||
                identity.IsDbDdlAdmin!=0 || identity.IsDbDatareader!=0 ||
                identity.IsDbDatawriter!=0 || identity.IsRuntimeRoleMember!=1)
                throw new InvalidOperationException("Integration tests require the non-admin KLOP_PLATFORM_TEST_RUNTIME principal in klop_app_runtime.");
        }
        var settings=await RuntimeSettings.Load(factory);
        return new KlopRepository(factory,settings);
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
    [SqlServerFact]
    public async Task Registration_Tenant_OwnerSecurity_AndSessionRotation()
    {
        var repo=await Setup();
        var suffix=Guid.NewGuid().ToString("N")[..12];
        var user=await NewVerifiedUser(repo,suffix);
        Assert.NotNull(await repo.GetProfile(user,CancellationToken.None));
        var personal=await repo.CreateTenant(user,"T"+suffix,"PERSONAL","Integration Personal",
            null,null,"integration",Guid.NewGuid(),CancellationToken.None);
        var revokeLastOwner=await Assert.ThrowsAsync<SqlException>(()=>repo.RevokeRole(personal.MembershipId,user,"OWNER",
            "integration",Guid.NewGuid(),CancellationToken.None));
        Assert.Equal(52189,revokeLastOwner.Number);
        var removeLastOwner=await Assert.ThrowsAsync<SqlException>(()=>repo.Remove(personal.MembershipId,user,
            "integration",Guid.NewGuid(),CancellationToken.None));
        Assert.Equal(52167,removeLastOwner.Number);
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
        output.WriteLine("Created persistent SQL fixtures; cleanup requires dropping only the disposable test database.");
    }
    [SqlServerFact]
    public async Task CrossTenantAndConcurrentOwnerProtection()
    {
        var repo=await Setup();
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
        // Two concurrent requests using separate SQL connections through the repository.
        async Task<bool> Attempt(long memberId,long actorId)
        {
            try { await repo.RevokeRole(memberId,actorId,"OWNER","integration",Guid.NewGuid(),CancellationToken.None); return true; }
            catch(SqlException) {return false;}
        }
        var results=await Task.WhenAll(Attempt(member,a),Attempt(org.MembershipId,b));
        Assert.True(results.Count(x=>x)==1,"Exactly one owner revocation should succeed.");
        var (remainingMembershipId,remainingActorId)=results[0]?(org.MembershipId,a):(member,b);
        var lastOwnerError=await Assert.ThrowsAsync<SqlException>(()=>repo.RevokeRole(remainingMembershipId,
            remainingActorId,"OWNER","integration",Guid.NewGuid(),CancellationToken.None));
        Assert.Equal(52189,lastOwnerError.Number);
        output.WriteLine("Concurrent owner protection passed; fixture data remains in the disposable test database.");
    }
    [SqlServerFact]
    public async Task RejectedMasterCodeAndDuplicateEmail()
    {
        var repo=await Setup();
        var suffix=Guid.NewGuid().ToString("N")[..12];
        var user=await NewVerifiedUser(repo,suffix);
        await Assert.ThrowsAsync<SqlException>(()=>repo.CreateTenant(user,"T"+suffix,"NO_SUCH_TYPE",
            "Invalid",null,null,"integration",Guid.NewGuid(),CancellationToken.None));
        await Assert.ThrowsAsync<SqlException>(()=>repo.Register($"test-{suffix}@example.invalid","Duplicate",
            new PasswordCodec().Hash("TemporaryDevelopmentPass!456"),SecretTokens.Sha256(SecretTokens.NewToken()),
            "integration",Guid.NewGuid(),CancellationToken.None));
    }
}
