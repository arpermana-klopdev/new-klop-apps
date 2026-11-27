using System.Security.Claims;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Microsoft.Data.SqlClient;

namespace KLOP.Platform.Api;

public static class ApiHelpers
{
    public static IResult Success<T>(HttpContext ctx,T data,int status=200) =>
        Results.Json(new ApiEnvelope<T>(true,data,null,new ApiMeta(ctx.TraceIdentifier)),statusCode:status);
    public static IResult Error(HttpContext ctx,int status,string code,string message) =>
        Results.Json(new ApiEnvelope<object>(false,null,new ApiError(code,message),
            new ApiMeta(ctx.TraceIdentifier)),statusCode:status);
    public static (long UserId,Guid Sid)? Identity(HttpContext ctx)
    {
        if (long.TryParse(ctx.User.FindFirstValue("sub"),out var userId)
            && Guid.TryParse(ctx.User.FindFirstValue("sid"),out var sid)) return(userId,sid);
        return null;
    }
    public static Guid Correlation(HttpContext ctx) =>
        Guid.TryParse(ctx.Request.Headers["X-Correlation-Id"],out var id)?id:Guid.NewGuid();
    public static bool SameOrigin(HttpContext ctx,RuntimeSettings settings)
    {
        var expected=settings.AllowedOrigin;
        var origin=ctx.Request.Headers["Origin"].ToString();
        // Cookie-authenticated refresh must always be sent by the configured SPA origin.
        return !string.IsNullOrWhiteSpace(expected) && string.Equals(expected.TrimEnd('/'),origin.TrimEnd('/'),StringComparison.Ordinal);
    }
    public static async Task<bool> Can(HttpContext ctx,KlopRepository db,long tenantId,string permission,CancellationToken ct)
    {
        var identity=Identity(ctx); if(identity is null) return false;
        try {await db.ValidateSession(identity.Value.UserId,identity.Value.Sid,tenantId,permission,ct);return true;}
        catch(SqlException ex) when(ex.Number is 52330 or 52331 or 52332 or 52333) { return false; }
    }
    public static (int Status,string Code,string Message) MapSql(SqlException ex)
    {
        return ex.Number switch {
            52113 or 52136 or 52137 or 52347 => (409,"CONFLICT","Request conflicts with current state."),
            52123 or 52330 or 52342 or 52344 or 52346 => (401,"INVALID_CREDENTIALS","Credentials or session are invalid."),
            52331 or 52332 or 52333 or 52145 or 52146 or 52161 or 52162 =>
                (403,"FORBIDDEN","Operation is not permitted."),
            >= 52100 and <= 52199 or >=52300 and <= 52399 => (400,"RULE_REJECTED","Operation was rejected by business rules."),
            2601 or 2627 => (409,"CONFLICT","Request conflicts with current state."),
            _ => (500,"SERVER_ERROR","Operation failed.")
        };
    }
}
