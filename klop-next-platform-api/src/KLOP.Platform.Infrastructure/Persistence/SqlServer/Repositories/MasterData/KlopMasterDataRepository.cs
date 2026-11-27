using System.Data;
using Dapper;
using KLOP.Platform.Domain;

namespace KLOP.Platform.Infrastructure;

public sealed partial class KlopRepository
{
    public Task<IReadOnlyList<OrganizationType>> OrganizationTypes(CancellationToken cancellationToken) =>
        Many<OrganizationType>("mst.usp_OrganizationType_GetAll", Params(("ActiveOnly", true)), cancellationToken);

    public Task<IReadOnlyList<TenantType>> TenantTypes(CancellationToken cancellationToken) =>
        Many<TenantType>("mst.usp_TenantType_GetAll", Params(("ActiveOnly", true)), cancellationToken);

    public Task<ConfigurationEntry?> GetConfiguration(string key, CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("ConfigurationKey", key, DbType.AnsiString, size: 150);
        return One<ConfigurationEntry>("cfg.usp_Configuration_GetByKey", parameters, cancellationToken);
    }

    public async Task CheckDatabase(CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("ConfigurationKey", "auth.access_token_minutes", DbType.AnsiString, size: 150);
        var setting = await One<ConfigurationEntry>("cfg.usp_Configuration_GetByKey", parameters, cancellationToken);
        if (setting is null || setting.StorageType != "PLAIN" || setting.ValueType != "INTEGER")
            throw new InvalidOperationException("SQL readiness configuration is unavailable.");
    }
}