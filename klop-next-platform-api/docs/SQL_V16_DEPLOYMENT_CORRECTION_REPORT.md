# KLOP Platform — SQL v1.6 Deployment Correction Report

**Environment:** Development only  
**SQL target:** `DEV-PC\SQLEXPRESS` / `KlopPlatformDB`  
**Baseline:** `KLOP-PLATFORM-DB-FOUNDATION-1.1 FROZEN`  
**Disposition:** Review package prepared. No database mutation, grant, role change, login/account creation, Production operation, or TEST database operation was performed.

## Executive status

A fresh read-only catalog check shows the two Legal read procedures that were missing in the earlier diagnosis are now present. Both procedures, the three v1.6 legal triggers, and their tables are in the catalog. The two procedure definitions match the reviewed v1.6 `003_legal_read_procedures.sql` contracts. Their catalog creation timestamps align with the trigger timestamps; the legal tables were created earlier. The enabled SQL Server default trace records `Object:Created` events for the two procedures and three triggers at `2026-11-23 11:43:35`, with application `Microsoft SQL Server Management Studio - Query`, host `DEV-PC`, and login `DEV-PC\rajaa`. Trace `TextData` is null, so it does not prove the exact submitted file/statement. The evidence supports that the legal-read procedure/trigger batch was not deployed at the earlier diagnosis and was then created through SSMS under the interactive developer login. This agent performed only read-only inspections and no-op template checks; it did not deploy these objects. No migration-history table was found.

The database-level procedure gap is now closed; the runtime security gap is not:

- **28/28 required API procedures exist.** Error 51633 should no longer occur for this inventory.
- `klop_app_runtime` still has **zero members**. `KLOP_PLATFORM_API_DEV` is still unmapped, and there is no approved runtime Windows SQL login configured in the template. Error 51632 remains valid until an approved identity is mapped.
- Only **8/28** required procedures have explicit `EXECUTE` grants to the role. The role’s existing schema-level `DENY` entries remain untouched.
- No Development API process or active `KLOP.Platform.API` SQL session was observed. The SQLCMD/SSMS identity is the interactive developer identity and is privileged; it is not API runtime evidence.
- No currently published, effective, scoped Terms document exists for either `PERSONAL` or `ORGANIZATION`. The metadata/file routes therefore are not data-ready even though their procedures and schemas exist.

## A. SQL v1.6 deployment inventory and reconciliation

### Current catalog inventory

| Object group | Current Development catalog state |
|---|---|
| `reg` schema | Present; owner `dbo` |
| Registration v1.6 procedures | All six present: `usp_GetMyApplication`, `usp_GetApplicationForOwner`, `usp_SavePersonalDraft`, `usp_SaveOrganizationDraft`, `usp_GetOrganizationRequirements`, `usp_SubmitOnboarding` |
| `leg` schema | Present; owner `dbo` |
| Legal tables | `leg.LegalDocuments`, `leg.LegalDocumentVersions`, `leg.LegalDocumentVersionScopes`, `leg.UserLegalConsents` present |
| Legal read procedures | `leg.usp_GetCurrentTerms` and `leg.usp_GetPublicTermsFile` present |
| Legal triggers | `trg_LegalDocumentVersions_Immutable`, `trg_LegalDocumentVersionScopes_Immutable`, and `trg_UserLegalConsents_AppendOnly` present |
| Authentication/tenant/configuration/master procedures | All 20 baseline objects present |

The legal tables have creation timestamps around `2026-11-23 09:01`; both legal procedures and all three legal triggers have creation timestamps around `2026-11-23 11:43:35`. The procedures’ current catalog definitions implement the source logic in `database/migrations/v1.6/003_legal_read_procedures.sql`. The default trace identifies the creating SSMS application, host, and interactive SQL login for those five objects; it does not retain `TextData`, and no migration-history table records a migration transaction. This establishes that the v1.6 legal procedure/trigger objects were absent at the earlier check and later created via SSMS, but not whether the entire file or selected statements were submitted. The original v1.6 migration was not modified or rerun by this agent.

### Procedure contracts, dependencies, and security behavior

Both procedures depend on the same four objects, confirmed through `sys.sql_expression_dependencies`:

- `leg.LegalDocuments`
- `leg.LegalDocumentVersions`
- `leg.LegalDocumentVersionScopes`
- `mst.TenantTypes`

`usp_GetCurrentTerms(@RegistrationTypeCode VARCHAR(50))` resolves only an active `mst.TenantTypes` code, filters to its matching version scope, `TERMS_AND_CONDITIONS`, `PUBLISHED`, and `EffectiveAtUtc <= SYSUTCDATETIME()`, and chooses the latest effective/published version. An unknown or inactive registration type raises the existing 52114 error.

`usp_GetPublicTermsFile(@DocumentVersionId UNIQUEIDENTIFIER)` returns metadata for that immutable version ID only if it is `TERMS_AND_CONDITIONS`, published, effective, and scoped to a registration type. It does not expose draft, approved-but-unpublished, future-effective, or unscoped versions. The existing public API route is intentionally anonymous and takes the version GUID; this procedure does not accept a registration-type parameter, and returns a registration type from the existing scope.

The SQL Server result-set metadata for **both** procedures is the same 11-column contract, all non-nullable:

| Column | SQL type | API model property |
|---|---|---|
| `DocumentVersionId` | `uniqueidentifier` | `Guid` |
| `DocumentTypeCode` | `varchar(50)` | `string` |
| `Title` | `nvarchar(300)` | `string` |
| `VersionIdentifier` | `nvarchar(50)` | `string` |
| `RegistrationTypeCode` | `varchar(50)` | `string` |
| `EffectiveAtUtc` | `datetime2(3)` | `DateTime` |
| `PublicationStatus` | `varchar(20)` | `string` |
| `StorageReference` | `nvarchar(100)` | `string` |
| `ContentHash` | `binary(32)` | `byte[]` |
| `MimeType` | `varchar(100)` | `string` |
| `FileSizeBytes` | `bigint` | `long` |

This matches `LegalTermsDocument` and both `KlopRegistrationRepository` mappings, which call `One<LegalTermsDocument>` with the expected procedure parameter names. The current schema constrains legal document type, publication state/dates, PDF MIME type/size, and the 32-character GUID storage reference. The three existing triggers preserve immutable published/archived version content and scope and append-only consent history.

`LegalTermsService` validates publication/type/effective metadata and the SHA-256 length. The API response maps the database `StorageReference` to a public version URL rather than returning that storage key. `FileSystemLegalDocumentStorage` separately requires a GUID `N` storage ID, keeps the configured storage root outside `wwwroot`, checks path containment/reparse points, size, PDF signature, and file hash. These existing public-document protections were not changed.

### Targeted corrective SQL package

Prepared path:

`database/migrations/v1.6.1/001_missing_legal_read_procedures_APPROVAL_TEMPLATE.sql`

This is deliberately not a replacement for, or rerun of, the historical v1.6 migration. It is Development/database restricted, approval gated, verifies the existing dependency tables/columns and schema owners, and uses `CREATE PROCEDURE` only for a procedure that is still absent. It does not alter an existing procedure and does not create schemas, tables, triggers, configuration, users, logins, role memberships, or grants. With both procedures present, the template reports `NO CHANGES - BOTH PROCEDURES ALREADY EXIST` even if an approval value were supplied.

The template was run with its default no-approval settings as a non-mutating check; SQLCMD returned `NO CHANGES - BOTH PROCEDURES ALREADY EXIST`. The live definitions’ successful SQL Server compilation, dependency metadata, and described result sets were also checked. No corrective DDL was executed.

## B. Windows runtime identity

### Observed launch/authentication behavior

- Visual Studio’s `KLOP.Platform.Dev` launch profile uses `commandName=Project`, sets `ASPNETCORE_ENVIRONMENT=Development`, and does not specify another run-as identity.
- `Sql:Authentication` in Development is `IntegratedSecurity`. `SqlConnectionFactory` builds the connection with `IntegratedSecurity=true`; it supplies no SQL login or password. The API’s SQL principal is consequently determined by the Windows token of the API process.
- No API or `dotnet.exe` process was running during the checks, and the read-only DMV query found no `KLOP.Platform.API` SQL connection. Therefore, the actual API runtime identity is **not verified**.
- A separate SQLCMD inspection ran as `DEV-PC\rajaa`, mapped to database user `dbo`, with `sysadmin=1` and `db_owner=1`. Its `APP_NAME()` was `SQLCMD`; this is explicitly **not** API identity evidence and must not be used for the API.

### Proposed setup (manual approval required)

1. Have the Windows/identity administrator provision and approve a dedicated Development-only, non-administrator service identity (suggested name: `DEV-PC\svc_klop_platform_api_dev`; confirm naming/availability before use). Do not use a developer account, local Administrators member, or SQL-authenticated user. Do not create the account as part of this package.
2. After the Windows identity is approved, have the DBA create/enable its individual Windows SQL Server login under a separate approved change. For the suggested local account name, the manual DBA statement would be `CREATE LOGIN [DEV-PC\svc_klop_platform_api_dev] FROM WINDOWS;`—execute only if that exact Windows identity is approved and exists. This is not included in, or executed by, any template here. Do not create a SQL login/password. The login must have no SQL Server fixed-role membership, including via Windows-group nesting. The database mapping template intentionally requires this login to pre-exist.
3. Run the API under precisely that identity. The normal Visual Studio Project profile inherits the Visual Studio user and is not sufficient when Visual Studio is running as the developer. For a local Development run, an administrator can use standard `runas` (not `/netonly`) with the approved account and the Development profile; for example, after the account exists:

   ```powershell
   runas /user:DEV-PC\svc_klop_platform_api_dev "dotnet run --project D:\PROJECT\Smart\klop\klop-next-platform-api\src\KLOP.Platform.Api\KLOP.Platform.Api.csproj --launch-profile KLOP.Platform.Dev"
   ```

   `runas` will prompt interactively; do not put a password in the command, source, or report. The approved account must have only the OS rights needed to read the application and write configured logs. A Windows Service deployment may use the same dedicated identity if separately configured and approved.
4. Use the actual, approved Windows login name as the SQLCMD variable in the reviewed mapping template. That script maps it to `KLOP_PLATFORM_API_DEV`, adds that user to `klop_app_runtime`, and grants the reviewed object-level `EXECUTE` set in one approval-gated transaction. It creates no server login and grants no `sysadmin`, `db_owner`, table DML, or broad schema/database right.

## C. `klop_app_runtime` mapping and 28-procedure matrix

The existing template was reviewed at `database/security/v1.6_runtime_identity_mapping_and_grants_APPROVAL_TEMPLATE.sql`. It requires an enabled pre-existing individual Windows login, checks for server fixed-role membership, validates login/user SID mapping and existing role memberships, requires all 28 reviewed procedures and the expected schema ownership, and fails closed on unexpected direct grants. It creates only the database-user mapping when absent, adds the user to the existing role, and grants only object-level `EXECUTE` on the allowlist. It neither creates a login nor adds table DML. Existing schema-level `DENY` entries are not revoked or overwritten. No grant or membership change was applied.

The current role contains 8 existing object `EXECUTE` grants (including six Registration procedures); it also has existing schema-level `DENY` INSERT/UPDATE/DELETE entries across five schemas. There are no role members, so none of the role grants currently serve the intended API identity. The table shows current explicit role grants:

| # | Procedure | Present in DB | Explicit role `EXECUTE` |
|---:|---|---|---|
| 1 | `cfg.usp_Configuration_GetByKey` | Yes | No |
| 2 | `iam.usp_RegisterLocalUser` | Yes | Yes |
| 3 | `iam.usp_ConfirmEmail` | Yes | No |
| 4 | `iam.usp_IssueEmailVerificationChallenge` | Yes | No |
| 5 | `iam.usp_GetLocalLoginCandidate` | Yes | No |
| 6 | `iam.usp_RecordLocalLoginFailure` | Yes | No |
| 7 | `iam.usp_CreateAuthSession` | Yes | No |
| 8 | `iam.usp_ValidateSessionAccess` | Yes | No |
| 9 | `iam.usp_RotateRefreshToken` | Yes | No |
| 10 | `iam.usp_RevokeAuthSession` | Yes | No |
| 11 | `iam.usp_GetUserProfile` | Yes | No |
| 12 | `iam.usp_AssignTenantRole` | Yes | No |
| 13 | `iam.usp_RevokeTenantRole` | Yes | No |
| 14 | `ten.usp_ListMyTenants` | Yes | No |
| 15 | `ten.usp_CreateTenantWithOwner` | Yes | No |
| 16 | `ten.usp_InviteExistingUser` | Yes | No |
| 17 | `ten.usp_AcceptMembership` | Yes | No |
| 18 | `ten.usp_RemoveTenantMember` | Yes | No |
| 19 | `mst.usp_OrganizationType_GetAll` | Yes | No |
| 20 | `mst.usp_TenantType_GetAll` | Yes | Yes |
| 21 | `reg.usp_GetMyApplication` | Yes | Yes |
| 22 | `reg.usp_GetApplicationForOwner` | Yes | Yes |
| 23 | `reg.usp_SavePersonalDraft` | Yes | Yes |
| 24 | `reg.usp_SaveOrganizationDraft` | Yes | Yes |
| 25 | `reg.usp_GetOrganizationRequirements` | Yes | Yes |
| 26 | `reg.usp_SubmitOnboarding` | Yes | Yes |
| 27 | `leg.usp_GetCurrentTerms` | Yes | No |
| 28 | `leg.usp_GetPublicTermsFile` | Yes | No |

All 28 catalog objects are present now; the absence of any one must continue to block the grant template. The original v1.6 grant script’s 51632 guard is not to be disabled: it correctly stops until the role has an approved member. The earlier 51633 missing-procedure guard is also not to be bypassed; its required-object precondition is now satisfied by the current catalog. The approval-gated mapping template addresses 51632 by adding the approved user only after preflight and approval, not by suppressing the error. Never run an older grant-only script before mapping or without an approved change.

## D. Safe verification scripts and results

Prepared read-only scripts:

- `database/migrations/v1.6.1/002_legal_procedure_validation_READONLY.sql` — target guard, legal object inventory, both procedure result sets, dependencies, current published/effective counts, legal-size configuration status, and a consent-enforcement status. It explicitly labels its inspecting session as not API proof.
- `database/security/v1.6_runtime_identity_validation_READONLY.sql` — target/session identity, expected Windows login and fixed-role checks, database SID mapping, role membership, all 28 procedures and role grants, role/direct permission catalog, current-session table-access results, and active API SQL sessions. `HAS_PERMS_BY_NAME` values describe the current connection only; the script labels them as runtime evidence only if the session context matches. It does not use `EXECUTE AS`.
- `database/migrations/v1.6.1/001_missing_legal_read_procedures_APPROVAL_TEMPLATE.sql` — the guarded, default-no-op correction described above.

Read-only validation findings:

- The legal validator returned both procedures `PRESENT`, the expected 11 result columns for both procedures, and the four dependency objects for each.
- Published/effective/scoped Terms count is **0** for `PERSONAL` and **0** for `ORGANIZATION`. Legal size configuration status is `PASS`; `registration.legal_consent_enforcement` is `OFF`. No records or configuration were changed.
- The runtime validator returned the current SQLCMD session as `dbo`/`sysadmin`/`db_owner` with `ApplicationName=SQLCMD` and marked it **not API runtime proof**. The approved login placeholder is not provisioned, `KLOP_PLATFORM_API_DEV` is not mapped, the role has no member, and no active `KLOP.Platform.API` SQL session was found.
- `LegalDocuments:StorageRoot` is application configuration and is not present in the checked-in API JSON; because no API process was running, any environment-provided value was not verified. Do not expose that path in logs/reports. Legal PDF serving remains blocked until a private non-`wwwroot` storage root and actual published PDF assets are separately verified.

Authentication/Registration/Legal verification is intentionally distinguished:

- The backend build succeeded.
- All **105 `KLOP.Platform.UnitTests` passed**. This includes Authentication service contracts, registration request/terms validation, the legal-storage PDF/hash/path checks, and anonymous/public legal route metadata. These tests are isolated unit tests and do not prove SQL runtime permissions.
- SQL-backed integration tests, API end-to-end tests, and any Development data-writing tests were not run.
- Existing Authentication implementation and legal-consent enforcement were not modified. Legal consent enforcement remains OFF; onboarding/legal workflows were not activated to make tests pass.
- The current `0` published Terms count plus absent runtime mapping/grants means Legal API readiness and SQL-backed Authentication/Registration compatibility under the intended least-privilege identity are **not yet verified**.

## E. Required manual DBA/administrator actions and approval gates

1. **Identity approval:** Provision the dedicated Windows service identity through the normal Windows/identity process. Verify it is not an administrator and that the API process can access only its required files/logs.
2. **SQL login approval:** Have the DBA create or confirm the matching individual Windows SQL login under a separate approved Development change. Confirm no fixed server-role membership or unsafe Windows-group inheritance. No login is created by these files.
3. **SQL role approval:** Review the exact 28-object allowlist and current role DENY rules. Once the approved login exists, set the exact login, ticket, and `KLOP_APPLY_CHANGES=APPROVED` in `database/security/v1.6_runtime_identity_mapping_and_grants_APPROVAL_TEMPLATE.sql`. Review its preflight output before execution. If any guard fails—including 51632/51633-related conditions—stop for DBA reconciliation; do not disable the guard.
4. **Terms data/storage approval:** Use the approved legal-document publishing workflow to make versioned, scoped, published, effective PDF records available for the registration types, with immutable references and hash/size metadata. Separately configure/verify the private `LegalDocuments:StorageRoot`. Keep consent enforcement OFF unless a separate product/security approval explicitly changes it.
5. **Runtime verification:** Start the API under the same approved Windows identity used for the SQL mapping. Run the read-only runtime validator as a DBA for catalog/DMV evidence and confirm a live `program_name=KLOP.Platform.API` session has the approved login, expected database, and Windows auth scheme. Then verify mapping, role membership, all 28 `EXECUTE` grants, and least privilege using the actual runtime identity; do not treat a DBA/SSMS/SQLCMD session or `EXECUTE AS` as proof.
6. **Functional approval:** After permissions and legal data/storage are ready, separately authorize API-level Authentication and Registration/Legal checks. Avoid creating Development users or submissions without the appropriate data-test approval.

## Remaining blockers

- No approved dedicated Windows runtime identity or SQL login is selected/provisioned.
- No `KLOP_PLATFORM_API_DEV` mapping or `klop_app_runtime` member exists; role grants are incomplete at 8/28. This is the remaining 51632/runtime-permissions blocker.
- All 28 procedures now exist, so the former 51633 missing-object condition is resolved in the current snapshot; keep the missing-object guard enabled.
- No published/effective scoped Terms document exists for either supported registration type, and private storage-root runtime configuration was not verified.
- No live API process/SQL connection has been observed; actual Development API runtime identity and effective permissions remain unverified.
- No database-backed Authentication, Registration, or Legal API validation was run.

**Final safety confirmation:** No SQL DDL, `ALTER ROLE`, `GRANT`, login/account creation, database/user mapping, Production change, test database creation, baseline change, or Development data mutation was performed. Catalog checks were read-only, and both correction/mapping templates were exercised only through their default no-change gates.
