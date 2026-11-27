namespace KLOP.Platform.Api;

internal sealed record MessageResponse(string Message);
internal sealed record VerifiedResponse(bool Verified);
internal sealed record LoggedOutResponse(bool LoggedOut);
internal sealed record MembershipIdResponse(long MembershipId);
internal sealed record AcceptedResponse(bool Accepted);
internal sealed record RemovedResponse(bool Removed);
internal sealed record AssignedResponse(bool Assigned);
internal sealed record RevokedResponse(bool Revoked);
internal sealed record HealthResponse(string Status);
internal sealed record JwksResponse(IReadOnlyList<JwkResponse> Keys);
internal sealed record JwkResponse(string Kty, string Use, string Alg, string Kid, string N, string E);
