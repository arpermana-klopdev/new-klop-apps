# KLOP 1.2.1 — API ↔ Stored Procedure contracts

**Data Access**: `SqlClient`/`Dapper`, `CommandType.StoredProcedure`; API/application must not embed direct table writes or hardcode master numeric IDs. Use named, typed SQL parameters and OUTPUT values. Never log `PasswordHash` or `VerificationTokenHash` parameters. Every procedure owns its SQL transaction (do not wrap in external SQL transaction).

| Stored Procedure | Required input | Optional input | Output |
|---|---|---|---|
| `iam.usp_RegisterLocalUser` | Email, DisplayName, PasswordHash, VerificationTokenHash (BINARY(32)), VerificationExpiresAtUtc | RequestId, CorrelationId | UserId, ChallengeId |
| `iam.usp_ConfirmEmail` | UserId, VerificationTokenHash | RequestId, CorrelationId | none |
| `ten.usp_CreateTenantWithOwner` | OwnerUserId, TenantCode, TenantTypeCode, DisplayName | OrganizationTypeId + RegisteredName for ORGANIZATION; RequestId, CorrelationId | TenantId, MembershipId |
| `ten.usp_InviteExistingUser` | TenantId, ActorUserId, InviteeUserId | RequestId, CorrelationId | MembershipId |
| `ten.usp_AcceptMembership` | MembershipId, ActorUserId | RequestId, CorrelationId | none |
| `ten.usp_RemoveTenantMember` | MembershipId, ActorUserId | RequestId, CorrelationId | none |
| `iam.usp_AssignTenantRole` | MembershipId, ActorUserId, RoleCode | RequestId, CorrelationId | none |
| `iam.usp_RevokeTenantRole` | MembershipId, ActorUserId, RoleCode | RequestId, CorrelationId | none |

## Caller security boundary
- Derive `ActorUserId` / `OwnerUserId` from authenticated server-side user context, **never** use a user-supplied payload field as the authority.
- Check session validity, tenant context, lifetime, and latest membership/tenant activation for protected endpoints. A removed user's old token/session must not retain effective access.
- Determine `OwnerUserId` from the authenticated user for self-service registration; a trusted admin onboarding path requires separate privileged SP design.
- Convert cryptographically random email verification token to its one-way hash in backend; send raw token only through approved email channel, with no access/request logs.
- Store a configured approved password KDF representation including salt and metadata; an encoded long string is **not** proof of a secure password hash.
- Rate limiting, anti-enumeration, email format normalization, challenge expiry upper bound and delivery status are application/security requirements.
- For front-end/API validation, map SQL errors 521xx to stable API errors without including SQL exception details in user responses.
- If a success response is lost after COMMIT, retry may report duplicate. Idempotency support remains future work.
- On a RCSI-enabled DB, `sp_getapplock` same tenant resource must be observed by all mutation paths touching memberships/roles.

## Response contract (concept only)
Follow the separate KLOP API baseline's unified response/HTTP semantics. This package does **not** include executable .NET endpoints nor claim API integration testing.
