# SQL runtime permission matrix

## Development status

Read-only inspection of `DEV-PC\SQLEXPRESS` / `KlopPlatformDB` found:

- The API uses Integrated Security under an elevated Windows identity mapped to `dbo`, with `sysadmin`, `db_owner`, and `db_ddladmin` privileges. This is **BLOCKED** for least-privilege runtime validation.
- `klop_app_runtime` exists but has **zero members** and eight explicit object-level `EXECUTE` grants: `iam.usp_RegisterLocalUser`, `mst.usp_TenantType_GetAll`, and the six registration-onboarding procedures (`reg.usp_GetMyApplication`, `reg.usp_GetApplicationForOwner`, `reg.usp_SavePersonalDraft`, `reg.usp_SaveOrganizationDraft`, `reg.usp_GetOrganizationRequirements`, `reg.usp_SubmitOnboarding`).
- The required procedures are categorized below. The four registration-administration procedures and the two platform permission procedures are present; the v1.10 tenant permission resolver is not yet deployed. The v1.9 migration ledger is absent, so catalog presence cannot establish which artifact deployed existing procedures.
- The seven application schemas (`cfg`, `iam`, `mst`, `ten`, `aud`, `reg`, `leg`) are owned by `dbo`. Same-database ownership chaining is the intended procedure access model; do not grant table access to compensate for an ownership-chain issue.
- No migration, permission seed, role assignment, principal mapping, grant, or application data change was performed.

The approved workbook authorizes only the immediate `platform.registrations.read` priority for `SUPER_ADMIN` and `PLATFORM_SUPPORT`. It is not FROZEN. Proposed, conditional, and HOLD permission codes remain inactive.

## Exact procedure allowlist

The revised, still-un-deployed v1.10 runtime package permits only these **38 object-level EXECUTE grants** through `klop_app_runtime`. The two `leg` procedures are public read-only Terms lookups needed by registration; this does not enable any legal-document administration capability.

### Baseline application and authentication (20)

| Schema | Stored procedure | Use |
|---|---|---|
| `cfg` | `usp_Configuration_GetByKey` | Runtime settings and readiness |
| `mst` | `usp_TenantType_GetAll` | Tenant-type lookup |
| `mst` | `usp_OrganizationType_GetAll` | Public organization-type lookup |
| `iam` | `usp_RegisterLocalUser` | Registration |
| `iam` | `usp_ConfirmEmail` | Email verification |
| `ten` | `usp_CreateTenantWithOwner` | Tenant creation |
| `ten` | `usp_InviteExistingUser` | Membership invitation |
| `ten` | `usp_AcceptMembership` | Invitation acceptance |
| `ten` | `usp_RemoveTenantMember` | Membership removal |
| `iam` | `usp_AssignTenantRole` | Approved tenant-role assignment |
| `iam` | `usp_RevokeTenantRole` | Tenant-role revocation |
| `iam` | `usp_GetLocalLoginCandidate` | Login candidate lookup |
| `iam` | `usp_RecordLocalLoginFailure` | Failed-login/lockout event |
| `iam` | `usp_IssueEmailVerificationChallenge` | Verification resend |
| `iam` | `usp_CreateAuthSession` | Session creation |
| `iam` | `usp_ValidateSessionAccess` | Session and tenant authorization |
| `iam` | `usp_RotateRefreshToken` | Refresh rotation/replay handling |
| `iam` | `usp_RevokeAuthSession` | Logout/session revocation |
| `iam` | `usp_GetUserProfile` | Authenticated profile |
| `ten` | `usp_ListMyTenants` | Current-user tenant listing |

### Public Terms reads (2)

| Schema | Stored procedure | Use |
|---|---|---|
| `leg` | `usp_GetCurrentTerms` | Current public Terms metadata |
| `leg` | `usp_GetPublicTermsFile` | Public Terms document content |

### Registration onboarding and read-only administration (10)

| Schema | Stored procedure | Use |
|---|---|---|
| `reg` | `usp_GetMyApplication` | Current user's onboarding application |
| `reg` | `usp_GetApplicationForOwner` | Owner-scoped application read |
| `reg` | `usp_SavePersonalDraft` | Personal onboarding draft |
| `reg` | `usp_SaveOrganizationDraft` | Organization onboarding draft |
| `reg` | `usp_GetOrganizationRequirements` | Organization requirements |
| `reg` | `usp_SubmitOnboarding` | Onboarding submission |
| `reg` | `usp_GetPlatformRegistrationSummary` | Platform registration summary |
| `reg` | `usp_ListPlatformRegistrations` | Platform registration listing |
| `reg` | `usp_GetPlatformRegistration` | Platform registration detail |
| `reg` | `usp_GetPlatformRegistrationTimeline` | Persisted registration timeline |

### Permission discovery and validation (6)

| Schema | Stored procedure | Use |
|---|---|---|
| `iam` | `usp_ValidatePlatformPermission` | Platform permission authorization |
| `iam` | `usp_GetPlatformPermissions` | Authenticated platform capability discovery |
| `iam` | `usp_GetTenantPermissions` | Authenticated selected-tenant capability discovery (v1.10) |
| `iam` | `usp_GetUnifiedRolePermissionMatrix` | SUPER_ADMIN-only unified matrix read model |
| `iam` | `usp_SaveRolePermissionBatch` | Validate-only and atomic, audited matrix batch save |
| `iam` | `usp_GetRolePermissionChangeHistory` | SUPER_ADMIN-only matrix audit history |

The matrix uses `mst.RolePermissions` as its sole grant mapping, extended with nullable `TenantTypeId` and a rowversion concurrency token. Tenant grants are evaluated separately for PERSONAL and ORGANIZATION; eligible role columns are derived from the six existing roles and tenant-type policy. Account self-service is stored in `mst.AccountSelfServicePolicies` as read-only policy data, not in `mst.RoleScopes`, `mst.Permissions`, or `mst.RolePermissions`.

No direct `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `ALTER`, `CONTROL`, impersonation, or table ownership permissions are required. No database/schema-wide `EXECUTE`, `db_owner`, `db_ddladmin`, `db_datareader`, `db_datawriter`, server role, nested runtime role, grant option, or application-table permission is acceptable.

The allowlist excludes legal-document administration, approval/rejection, exports, SMTP/configuration administration, role-permission management, cross-tenant business data, and every proposed/HOLD permission. It does not activate or seed any permission code.

## Approval-gated deployment

All deployment remains manual and requires explicit Development DBA approval and a change ticket:

1. Run [the read-only v1.10 preflight](../database/migrations/v1.10/001_rbac_preflight_READONLY.sql).
2. Review and, only after approval, run [the registration permission seed template](../database/migrations/v1.10/002_platform_registration_permissions_APPROVAL_TEMPLATE.sql). It seeds only `platform.registrations.read` and maps only existing role IDs 1 (`SUPER_ADMIN`) and 2 (`PLATFORM_SUPPORT`). Permission and mapping writes produce audit events.
3. Review the revised template and, only after renewed DBA/policy approval, run [the tenant permission policy and unified matrix template](../database/migrations/v1.10/003_tenant_permission_policy_APPROVAL_TEMPLATE.sql). It preserves the six role records, extends the single role-permission mapping for tenant-type context, provisions read-only account policy catalog data outside the role-scope hierarchy, adds only the matrix's protected read/update permissions, and defines the tenant resolver and matrix procedures.
4. Provision the dedicated Windows/Entra individual login outside this package. Review and, only after approval, run [the v1.10 runtime identity and grants template](../database/security/v1.10_runtime_identity_and_grants_APPROVAL_TEMPLATE.sql). It maps one pre-created identity to `klop_app_runtime` and grants only the exact 38 procedures, preserving existing grants within the allowlist. It refuses to overwrite an unrelated member, remove existing privileges, or proceed when a required procedure/schema/prerequisite is missing.
5. Run [the read-only post-deployment checks](../database/migrations/v1.10/004_rbac_postdeploy_validation_READONLY.sql), deploy/restart the API and frontend, then run [runtime validation](../database/security/v1.10_runtime_identity_validation_READONLY.sql) from the actual least-privilege service connection.

The older runtime template has a 20-procedure allowlist and is not the v1.10 deployment path for this Development state. Do not execute it alongside the v1.10 package.

## Validation gate

The runtime is **NOT READY** until a non-admin identity is mapped, all 38 object grants pass from that identity, and there is no direct table access or elevated role membership. The API route and UI checks must then be run with valid `SUPER_ADMIN`, `PLATFORM_SUPPORT`, OWNER, and (where approved/mapped) ADMIN sessions. Until then, authenticated live behavior is blocked; the effective-permission UI remains a visibility aid, not an authorization boundary.
