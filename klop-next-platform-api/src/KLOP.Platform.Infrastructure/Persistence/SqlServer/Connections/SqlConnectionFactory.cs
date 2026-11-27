using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace KLOP.Platform.Infrastructure;

public sealed class SqlConnectionFactory(IConfiguration configuration, bool allowCertificateTrustBypass = false)
{
    public SqlConnection Open()
    {
        var server = configuration["Sql:Server"];
        var database = configuration["Sql:Database"];
        var auth = configuration["Sql:Authentication"];
        var trustServerCertificateValue = configuration["Sql:TrustServerCertificate"];
        var trustServerCertificate = false;
        if (!string.IsNullOrWhiteSpace(trustServerCertificateValue) &&
            !bool.TryParse(trustServerCertificateValue, out trustServerCertificate))
            throw new InvalidOperationException("Sql:TrustServerCertificate must be a boolean.");
        if (trustServerCertificate && !allowCertificateTrustBypass)
            throw new InvalidOperationException("Sql:TrustServerCertificate is only allowed in Development.");
        if (string.IsNullOrWhiteSpace(server) || string.IsNullOrWhiteSpace(database))
            throw new InvalidOperationException("Sql server/database bootstrap configuration is missing.");
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = server, InitialCatalog = database, Encrypt = SqlConnectionEncryptOption.Mandatory,
            TrustServerCertificate = trustServerCertificate, ConnectTimeout = 15, ApplicationName = "KLOP.Platform.API"
        };
        if (auth == "IntegratedSecurity") builder.IntegratedSecurity = true;
        else if (auth == "ActiveDirectoryDefault") builder.Authentication = SqlAuthenticationMethod.ActiveDirectoryDefault;
        else if (auth == "ActiveDirectoryManagedIdentity") builder.Authentication = SqlAuthenticationMethod.ActiveDirectoryManagedIdentity;
        else throw new InvalidOperationException("Unsupported Sql:Authentication. Use integrated/Entra identity.");
        return new SqlConnection(builder.ConnectionString);
    }
}
