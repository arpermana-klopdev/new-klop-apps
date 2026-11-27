# KLOP DB v1.2.1 — Integration Test Matrix (PENDING)

Execution scope: isolated SQL Server **Development** database only, after clean v1.1 + v1.2 installs.
Use dedicated least-privilege runtime SQL principal and a separate fixture-setup principal.
All secrets must be disposable test-only values; never expose raw tokens or KDF parameters in diagnostics.

| ID | Scenario | Expected outcome |
|---|---|---|
| T01 | Register new user with valid password KDF hash and token hash | One user, one credential, one challenge, one `aud.AuditEvents` entry commit together |
| T02 | Register duplicate normalized email (including case variants) | Atomic failure; no extra user/credential/challenge/audit rows |
| T03 | Confirm email valid once; retry same hash | First call verifies and consumes, replay fails without additional success audit |
| T04 | Confirm expired or invalidated challenge | Rejected; EmailVerifiedAtUtc remains NULL |
| T05 | Create PERSONAL tenant for verified active user | ACTIVE tenant, one ACTIVE membership, exactly one OWNER, tenant audit + business event |
| T06 | Create ORGANIZATION tenant with valid OrganizationTypeId | PENDING tenant, organization UNVERIFIED, active owner, audit + business event |
| T07 | Create tenant for unverified user or duplicate TenantCode | Atomic failure; no orphan tenant or role assignment |
| T08 | Invite existing user from an authorized organization owner | INVITED membership, audit + business event; no role until accepted |
| T09 | Accept invite as the invitee | ACTIVE membership and MEMBER role, audit + business event; repeat fails |
| T10 | Invite or role-change from foreign tenant actor | Rejected; no changes in target tenant |
| T11 | Assign cross-scope role (PLATFORM role) to a tenant member | Rejected; no TenantRoleAssignments insert |
| T12 | Assign OWNER from a user without active OWNER | Rejected even if general role permission is granted |
| T13 | Revoke last OWNER in PERSONAL tenant | Rejected; exactly one active OWNER remains |
| T14 | Remove last OWNER in ORGANIZATION tenant | Rejected; roles and membership unchanged |
| T15 | Simultaneously revoke/remove two owners from same organization | At least one request fails; never zero active owners (concurrent sessions required) |
| T16 | Remove a non-owner | Membership REMOVED, all attached roles deleted, audit + business event in same commit |
| T17 | Intentionally make audit insert fail (isolated test principal/fixture) | Full state mutation rolls back, not just audit insert |
| T18 | Execute direct DML on iam/ten/aud as runtime principal | Permission denied; individual procedures callable |
| T19 | SQL app login attempts a self-attested ActorUserId without valid API auth | API denies before DB call; DB BIGINT parameter is *not* an authentication claim |
| T20 | Unknown master code, inactive role, invalid organization type | Rejected; master IDs resolved from DB, no static numeric IDs |
| T21 | Attempt invite/accept on CLOSED/SUSPENDED tenant | Invite and accept procedures reject these states (confirm by integration test) |
| T22 | Runtime API session/token lifecycle and refresh rotation | Not in v1.2.1 scope; separate audited security SPs required |

**Interpretation:** SQL text and structural checks are not proof of any of the above outcomes. Test results remain PENDING until executed against real SQL Server in Development. Release requires traceable evidence, including two-session concurrency runs and permission inspection.
