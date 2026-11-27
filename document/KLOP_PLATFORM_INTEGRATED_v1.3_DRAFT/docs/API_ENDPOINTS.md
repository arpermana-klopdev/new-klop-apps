# KLOP Platform v1.3 DRAFT API contract

`/api/v1` routes. JSON returns `success`, `data`, `error`, and `meta.requestId`. User IDs and membership IDs are SQL BIGINT; tenant types, role codes and permission codes come from database masters. Passwords/refresh tokens must never be logged.

| HTTP | Route | Auth / Purpose | Backing SP |
|---|---|---|---|
| POST | `/auth/register` | Anonymous registration; email verification sent via SMTP | `iam.usp_RegisterLocalUser` |
| POST | `/auth/resend-verification` | Anonymous anti-enumeration resend | `iam.usp_IssueEmailVerificationChallenge` |
| POST | `/auth/verify-email` | Anonymous verification code + user ID | `iam.usp_ConfirmEmail` |
| POST | `/auth/login` | Local auth with PBKDF2 password verify; short-lived signed JWT | `iam.usp_GetLocalLoginCandidate`, `iam.usp_CreateAuthSession`, failure SP |
| POST | `/auth/refresh` | Exact SPA Origin; HttpOnly Secure SameSite Strict refresh cookie | `iam.usp_RotateRefreshToken` |
| POST | `/auth/logout` | JWT required; revoke entire session/refresh tokens | `iam.usp_RevokeAuthSession` |
| GET | `/auth/me` | JWT + session validation | `iam.usp_GetUserProfile` |
| GET | `/master/organization-types` | DB-driven reference | `mst.usp_OrganizationType_GetAll` |
| GET | `/tenants/mine` | JWT + session validation | `ten.usp_ListMyTenants` |
| POST | `/tenants/` | JWT; owner derived server-side from verified session | `ten.usp_CreateTenantWithOwner` |
| POST | `/tenants/{tenantId}/invitations` | DB-checked `tenant.members.invite` | `ten.usp_InviteExistingUser` |
| POST | `/tenants/memberships/{membershipId}/accept` | JWT; invitee validated in SP | `ten.usp_AcceptMembership` |
| DELETE | `/tenants/{tenantId}/memberships/{membershipId}` | DB-checked `tenant.members.remove` | `ten.usp_RemoveTenantMember` |
| POST | `/tenants/{tenantId}/memberships/{membershipId}/roles` | DB-checked `tenant.roles.assign` | `iam.usp_AssignTenantRole` |
| DELETE | `/tenants/{tenantId}/memberships/{membershipId}/roles/{roleCode}` | DB-checked `tenant.roles.assign` | `iam.usp_RevokeTenantRole` |

All JWT-protected routes re-check active session state through `iam.usp_ValidateSessionAccess` on every request. Tenant operations additionally verify current tenant membership and requested permission; SPs enforce independent database rules. `OwnerUserId` and `ActorUserId` are never read from client payloads.

## Example requests

Registration:
```json
{"email":"dev@example.com","displayName":"Developer","password":"UseADisposableStrongPassphrase!"}
```
Verify-email:
```json
{"userId":123,"token":"paste-code-from-email"}
```
Login:
```json
{"email":"dev@example.com","password":"UseADisposableStrongPassphrase!"}
```
Create tenant:
```json
{"tenantCode":"DEV-001","tenantTypeCode":"PERSONAL","displayName":"Development Workspace","organizationTypeId":null,"registeredName":null}
```
Invite (existing verified user):
```json
{"inviteeUserId":124}
```
Role assignment:
```json
{"roleCode":"MEMBER"}
```

`POST /auth/refresh` accepts no JSON body; it requires the secure refresh cookie and an `Origin` header matching `Web:AllowedOrigin`. The bearer token is returned in the `data.accessToken` field for use as `Authorization: Bearer ...`; refresh secrets remain HttpOnly cookies.
