using System.Data;
using Dapper;
using KLOP.Platform.Application;

namespace KLOP.Platform.Infrastructure;

public sealed partial class KlopRepository : IRolePermissionMatrixRepository
{
    public Task<IReadOnlyList<RolePermissionMatrixDbRow>> GetRolePermissionMatrix(
        long actorUserId, Guid sessionId, CancellationToken cancellationToken) =>
        Many<RolePermissionMatrixDbRow>("iam.usp_GetUnifiedRolePermissionMatrix",
            Params(("ActorUserId", actorUserId), ("PublicSessionId", sessionId)), cancellationToken);

    public Task<IReadOnlyList<RolePermissionMatrixValidationDbRow>> ValidateRolePermissionBatch(
        long actorUserId, Guid sessionId, string reason, string changesJson,
        CancellationToken cancellationToken) =>
        Many<RolePermissionMatrixValidationDbRow>("iam.usp_SaveRolePermissionBatch",
            BatchParams(actorUserId, sessionId, reason, changesJson, null, null, false), cancellationToken);

    public Task<RolePermissionMatrixSaveDbRow?> SaveRolePermissionBatch(
        long actorUserId, Guid sessionId, string reason, string changesJson,
        RequestMetadata metadata, CancellationToken cancellationToken) =>
        One<RolePermissionMatrixSaveDbRow>("iam.usp_SaveRolePermissionBatch",
            BatchParams(actorUserId, sessionId, reason, changesJson, metadata.RequestId,
                metadata.CorrelationId, true), cancellationToken);

    public Task<IReadOnlyList<RolePermissionMatrixHistoryDbRow>> GetRolePermissionHistory(
        long actorUserId, Guid sessionId, int pageNumber, int pageSize,
        CancellationToken cancellationToken) =>
        Many<RolePermissionMatrixHistoryDbRow>("iam.usp_GetRolePermissionChangeHistory",
            Params(("ActorUserId", actorUserId), ("PublicSessionId", sessionId),
                ("PageNumber", pageNumber), ("PageSize", pageSize)), cancellationToken);

    private static DynamicParameters BatchParams(
        long actorUserId, Guid sessionId, string reason, string changesJson,
        string? requestId, Guid? correlationId, bool applyChanges)
    {
        var parameters = Params(("ActorUserId", actorUserId), ("PublicSessionId", sessionId),
            ("ChangeReason", reason), ("ChangesJson", changesJson),
            ("RequestId", requestId), ("CorrelationId", correlationId),
            ("ApplyChanges", applyChanges));
        return parameters;
    }
}
