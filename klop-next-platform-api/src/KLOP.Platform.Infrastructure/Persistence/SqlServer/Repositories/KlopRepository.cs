using System.Data;
using Dapper;
using KLOP.Platform.Application;

namespace KLOP.Platform.Infrastructure;

// Repository methods invoke versioned stored procedures; application tables and audit remain database-owned.
public sealed partial class KlopRepository(SqlConnectionFactory factory, RuntimeSettings settings) :
    IPlatformRepository, IRegistrationRepository, IPlatformRegistrationRepository,
    IPlatformPermissionRepository, ILegalDocumentsRepository, IRolePermissionMatrixRepository,
    INotificationManagementRepository
{
    private async Task Execute(string name, DynamicParameters parameters, CancellationToken cancellationToken)
    {
        using var connection = factory.Open();
        await connection.ExecuteAsync(new CommandDefinition(name, parameters,
            commandType: CommandType.StoredProcedure,
            commandTimeout: settings.CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
    }

    private async Task<T?> One<T>(string name, DynamicParameters parameters, CancellationToken cancellationToken)
    {
        using var connection = factory.Open();
        return await connection.QuerySingleOrDefaultAsync<T>(new CommandDefinition(name, parameters,
            commandType: CommandType.StoredProcedure,
            commandTimeout: settings.CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
    }

    private async Task<IReadOnlyList<T>> Many<T>(string name, DynamicParameters parameters,
        CancellationToken cancellationToken)
    {
        using var connection = factory.Open();
        var items = await connection.QueryAsync<T>(new CommandDefinition(name, parameters,
            commandType: CommandType.StoredProcedure,
            commandTimeout: settings.CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        return items.AsList();
    }

    private static DynamicParameters Params(params (string Name, object? Value)[] items)
    {
        var parameters = new DynamicParameters();
        foreach (var (name, value) in items)
        {
            var type = name switch
            {
                "RequestId" or "RoleCode" or "TenantCode" or "TenantTypeCode" or "PermissionCode" =>
                    DbType.AnsiString,
                "TenantId" or "OrganizationTypeId" => DbType.Int64,
                "RegisteredName" => DbType.String,
                _ => value switch
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
            parameters.Add(name, value, type);
        }
        return parameters;
    }
}