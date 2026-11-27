# KLOP PLATFORM DB — 1.2.1 DRAFT implementation increment

## Lineage and immutability
- **v1.1 FROZEN:** immutable. Never overwrite the source Excel/SQL artifacts.
- **v1.2 DRAFT:** additive schema and starter seed only; remains a separate snapshot.
- **v1.2.1 DRAFT:** adds 8 transactional/audited Stored Procedures, a privilege review template, structural smoke checks and a pending test matrix. **No schema changes**, no changes to frozen/draft prior artifacts.
- Neither v1.2 nor v1.2.1 is approved for Production.

## SQL Server compatibility
- DRAFT targets SQL Server 2016 SP1 or newer (`CREATE OR ALTER`, `FOR JSON`, `sp_getapplock`); use supported, patched SQL Server versions for real deployment.
- Script files are meant for a GO-aware tool (e.g. sqlcmd / SSMS); GO is a client batch separator, not SQL.

## Sequence for Development only
1. Apply/test v1.1 then v1.2 migration **in Development** (the earlier source packages remain unchanged).
2. Execute `sql/00_Preflight/000_require_v1_2.sql`.
3. Execute in order `sql/01_StoredProcedures/100_registration.sql`, `110_tenant_create.sql`, `120_membership.sql`, `130_roles.sql`.
4. DBA reviews and **optionally** executes `sql/02_Security/200_runtime_role_TEMPLATE.sql` after confirming effective permissions and same-owner ownership chaining; this script is **not** an automatically applied migration.
5. Execute `sql/03_Validation/300_structure_checks.sql` and perform the real integration tests in `docs/INTEGRATION_TEST_MATRIX.md`.

## Stored Procedures
| Procedure | Behavior |
|---|---|
| `iam.usp_RegisterLocalUser` | Creates user, hashed password credential, email challenge and audit in one transaction |
| `iam.usp_ConfirmEmail` | Consumes valid single-use hash, verifies user, invalidates siblings, audits |
| `ten.usp_CreateTenantWithOwner` | Creates PERSONAL/ORGANIZATION tenant, OWNER membership/role, audit+business event |
| `ten.usp_InviteExistingUser` | Authorized tenant invite for existing verified user, membership INVITED, audit+business |
| `ten.usp_AcceptMembership` | Invitee activates their membership, receives MEMBER role, audit+business |
| `ten.usp_RemoveTenantMember` | Permission checked; blocks last owner removal; revokes all roles, audits |
| `iam.usp_AssignTenantRole` | Permission and scope checks; OWNER granting restricted to active OWNER |
| `iam.usp_RevokeTenantRole` | Permission and scope checks; blocks last owner revocation, audits |

## Security and design conditions
- API must validate JWT/session and bind the authenticated user to `@ActorUserId` / `@OwnerUserId`. SQL `BIGINT` parameters are NOT identity attestation. Direct SQL caller must be trusted backend principal.
- API generates secure random verification secrets, passes only 32-byte cryptographic hashes; raw tokens never stored or logged. API KDF creates an approved salted hash representation in PasswordHash. Email delivery and rate limiting are outside SQL procedures.
- `sp_getapplock` exclusive transaction-level lock keyed by tenant is used for all role/member edits. No direct runtime DML on operational tables. Any new membership/role SP must take the **same lock**.
- Stable master codes (PERSONAL, ORGANIZATION, OWNER, etc.) are looked up at runtime from SQL tables; **never hardcode master numeric IDs**.
- State transitions and AuditEvents commit atomically. `aud.BusinessEvents` is not a reliable outbox.
- Tenant activation after organization verification, organization identity document workflow, session/refresh-token SPs, secret rotation, denial logging, and app-side auth orchestration are **NOT YET IMPLEMENTED**.
- Email validation in SP is basic sanity-only; normalized address policy (Unicode/IDN/canonicalization) must be approved and matched in API. Also approve configured verification expiry upper limit / rate limiting policy.
- Runtime EXECUTE template is only a starting point; verify SQL principals, ownership chaining, effective privilege checks and schema ownership; distinguish runtime and migration identities.
- v1.0 ARCH-04 single-tenant vs v1.1 B03 many-to-many conflict remains OPEN; 1.2.1 intentionally follows v1.1 database modeling.

## Known gaps blocking release
1. No real SQL Server compilation/execution, no side-by-side run and no concurrency tests performed here.
2. SQL owner auth is dependent on trusted API proof; test with actual bearer/session auth and isolated principal.
3. User/tenant lifecycle rules incomplete for CLOSED/SUSPENDED and membership reinstatement.
4. Pending organization legal-identity verification workflows and config approval/change SPs.
5. No idempotency key/operations ledger; API retries may receive duplicate errors after a prior success.
6. API rate limiting, token TTL and secure mail workflow need implementation and policy approval.
7. Decide whether to use additional DB-native defense-in-depth on user identity attestation.

## Approval
**DRAFT — implementation candidate, not frozen, not Production-ready.** Baseline freeze and deployment require explicit owner approval and recorded test evidence.
