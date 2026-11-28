# System Configuration Management v1.12 — proposal and reconciliation report

## Status and scope

This is an additive, owner-review proposal only. No SQL Server script was executed, no SQL Server test database was created, no live database/UAT was performed, no actual configuration presence was assumed, and no deployment/readiness activation/role mapping was performed. Nothing in this report claims production readiness or a frozen baseline. The v1.1 source tables, configuration loader, bootstrap settings, registration/notification behavior, v1.10/v1.11 migrations, and Database Studio are unchanged.

The application still reads persisted startup settings through `cfg.usp_Configuration_GetByKey` in `RuntimeSettings.Load`; v1.12 does not connect to that path at startup. The UI/API project types compile without requiring v1.12 at startup. Until the v1.12 permission procedures are separately installed, the existing authorization procedure rejects these new permission codes and the endpoints fail closed.

## ERD and projected data

```text
cfg.SystemConfigurations (existing; only persisted value store)
  ConfigurationKey [unique], ValueType, Category, StorageType,
  RequiresApproval, VersionNumber, IsActive, IsEditable, IsSensitive,
  RequiresRestart, actors/timestamps, RowVersion
             |
             | exact key match; no FK, so absent source rows remain reportable
             v
cfg.ConfigurationManagementPolicies (new explicit safe allowlist + management policy)
  ConfigurationKey [PK], safe category/type/storage, approval/restart flags,
  integer bounds, IsManageable (seed 0), ManagementStatus (seed HOLD), RowVersion
             |
             +----< cfg.ConfigurationChangeRequests (new versioned lifecycle)
             |        RequestId [PK], ConfigurationKey [FK], allowlisted integer proposal,
             |        expected target version/rowversion, expected policy rowversion,
             |        reason code, status, requester/approver/apply actor, timestamps, RowVersion
             |                    |
             |                    +---- 1:0..1 cfg.ConfigurationChangeDecisions
             |                    |       append-only APPROVE/REJECT actor and timestamp
             |                    |
             |                    +---- 1:0..1 cfg.ConfigurationAppliedHistory
             |                            append-only candidate integer, new version,
             |                            reason, applying actor and timestamp
             |
             +---- safe paginated read procedures

Every successful mutation -> existing aud.AuditEvents in the same SQL transaction.
```

`ConfigurationManagementPolicies.ConfigurationKey` intentionally has no FK to the existing settings table: missing/inactive settings must be reportable without creating configuration rows. Request keys do have an FK to the explicit policy catalog. All reads start from a SQL-embedded allowlist and return only allowlisted metadata; unclassified configuration keys are counted in aggregate only. `ConfigurationValue`, defaults, free-form descriptions, regex patterns, allowed-values JSON, secret references, and raw notes are not selected into DTOs. The only history/request value is the explicitly allowlisted bounded integer candidate.

### New table/field and seed map

| Table | Why it is new / field projection | Constraints and seed state |
|---|---|---|
| `cfg.ConfigurationManagementPolicies` | Reviewed key classification, safe category/type/storage, runtime-bounded integer range, approval/restart flags, management hold state, optimistic policy version | PK `ConfigurationKey`; HOLD/ACTIVE check; `IsManageable=1` requires ACTIVE; valid numeric range check. Twelve known non-sensitive `RuntimeSettings` keys only; `IsManageable=0`, `ManagementStatus='HOLD'` for all. No values/defaults. |
| `cfg.ConfigurationChangeRequests` | Draft snapshot, typed integer, expected target and policy concurrency, reason code, lifecycle state, requester/approver/apply actor and timestamps | PK `RequestId`; FK to policy; fixed status/reason checks; positive expected version; indexed by status/time. No delete; submitted content immutable; lifecycle trigger only permits forward transitions. |
| `cfg.ConfigurationChangeDecisions` | Separate decision actor/time and immutable approval/rejection evidence | PK identity; FK to request; decision constrained to APPROVE/REJECT; unique request ID; append-only trigger. |
| `cfg.ConfigurationAppliedHistory` | Exactly-once immutable applied version/value/reason/actor/time projection | PK identity; FK to request; unique request ID; positive version; deterministic time/id pagination; append-only trigger. |

No new configuration key, configuration default, target row, grant, role, user, or role assignment is seeded. The candidate retains the existing v1.4 source seed’s `IsEditable=0`.

## Safe source inventory and readiness

See [CONFIGURATION_CATALOG.md](CONFIGURATION_CATALOG.md) for all twelve safe inventory keys and the exact fixed runtime ranges. Runtime state was not queried, so the inventory does not imply any key is present, active, valid, or deployed. At request time, readiness is one of `PRESENT`, `MISSING`, `INACTIVE`, or `INVALID`; management status is separate. The new policy seed is entirely `HOLD`; the existing `database.command_timeout_seconds` row’s editability is not changed.

Out-of-allowlist settings (including security/identity material, connection/JWT/signing values, SMTP details/references, and any unclassified value) are not catalog rows. The procedure returns only a count of rows outside its compiled allowlist. It does not expose arbitrary key names, descriptions, defaults, patterns, JSON, or stored values. `PLAIN` alone never permits projection.

An applied persisted integer would not be a runtime hot reload. The audit/history marker is `RESTART_REQUIRED; RUNTIME_VALUE_UNCHANGED`; no automatic or API-triggered restart is provided.

## Proposed PLATFORM permission matrix

All definitions are for the existing PLATFORM scope, seeded as `HOLD`, matrix-unassigned, and ineffective. No role grants, user IDs, role assignments, or readiness activations are included. Both authorization stored procedures receive the same additive code allowlist while preserving prior session/scope/readiness logic and all existing v1.10/v1.11 codes.

| Permission | Intended operation | Default matrix state |
|---|---|---|
| `platform.configurations.read` | Safe catalog and request metadata | HOLD / unassigned |
| `platform.configurations.request.create` | Create typed draft for a separately eligible policy | HOLD / unassigned |
| `platform.configurations.request.edit` | Edit own draft only | HOLD / unassigned |
| `platform.configurations.request.submit` | Submit immutable request for review | HOLD / unassigned |
| `platform.configurations.request.cancel` | Cancel own draft/submitted request | HOLD / unassigned |
| `platform.configurations.approve` | Approve/reject submitted request; requester cannot approve own request | HOLD / unassigned |
| `platform.configurations.apply` | Independently authorized exactly-once apply | HOLD / unassigned |
| `platform.configurations.history` | Read deterministic safe applied history | HOLD / unassigned |

Conservative default separates requester, approver, and applier: SQL rejects requester self-approval, and apply requires an actor different from both requester and approver. Owner review may alter that policy only in a separate authorization decision.

## Workflow and safety invariants

```text
DRAFT -> SUBMITTED -> APPROVED -> APPLIED
                  \-> REJECTED
DRAFT or SUBMITTED -> CANCELED
```

- Only a named candidate, typed INTEGER, and canonical integer input are supported. The service and stored procedures independently constrain the key to `database.command_timeout_seconds`, runtime 1–120, current target numeric metadata, `PLAIN`, active, editable, nonsensitive, requires-approval and requires-restart.
- Effective proposal bounds are the intersection of the fixed `RuntimeSettings` range and current source metadata bounds. Unknown types/keys and changed policy fail closed; no arbitrary regex or generic untyped handler exists.
- Create/update/submit/decision/apply use the verified session actor and exact PLATFORM permission in both application/service and stored-procedure layers. SQL locks policy, request, and target rows and checks expected request rowversion, target rowversion/version, and policy rowversion.
- Submit freezes request content; approval and apply are separate; apply must be separately authorized and is unique per request. It increments the existing `VersionNumber`, updates actor/time, writes applied history and audit in one transaction. Duplicate, stale, unauthorized, policy-changed, and rollback paths fail closed.
- No delete or blind restore operation exists. Recovery from an applied mistake requires a new separately submitted and approved request.
- Mutation error bodies are mapped to safe fixed messages. Reasons are constrained codes, not user notes. Audit/history contains only approved key metadata, bounded candidate integer, reason code, action/state, version, actor, and timestamps.

## API/UI projection

The API uses the existing layered Application/Infrastructure/API architecture and Dapper stored-procedure boundary. Routes are under `/api/v1/platform/configurations` for permission discovery, allowlisted catalog, change requests, approvals, history, and protected lifecycle mutations. OpenAPI is the TypeScript source of truth. The UI uses accessible separate Catalog, Change Requests, Approvals, and History tabs, local-only search over returned approved rows, safe category filtering, deterministic paging, readiness/detail metadata, and permission-gated controls. A key on HOLD exposes no edit control. No raw current value is queried or displayed.

## SQL file map and proposed execution order

No script in this package has been run.

1. `database/migrations/v1.12/000_configuration_preflight_READONLY.sql` — inspect target/schema prerequisites and collisions only; does not inspect values or key names.
2. `001_configuration_schema_APPROVAL_TEMPLATE.sql` — additive policy/lifecycle schema and HOLD-only safe policy seed; guarded Development target and explicit ticket.
3. `002_configuration_procedures_APPROVAL_TEMPLATE.sql` — safe stored-procedure boundary and lifecycle.
4. `003_configuration_permissions_APPROVAL_TEMPLATE.sql` — PLATFORM permission definitions and HOLD/unassigned matrix metadata; no mappings.
5. `004_configuration_authorization_delta_APPROVAL_TEMPLATE.sql` — guarded addendum to both existing authorization procedures.
6. `005_configuration_postdeploy_READONLY.sql` — metadata/status/count checks; no raw values.
7. `database/security/v1.12_configuration_runtime_grants_APPROVAL_TEMPLATE.sql` — exact EXECUTE-only grant list for the seven v1.12 procedures, only after the owner confirms the existing runtime database principal. Never grants direct table access, creates principals, or changes memberships.

The templates default to refusal and require a separately approved Development target, explicit ticket, and apply flag. Scripts check prerequisites and object collisions; a collision or partial state requires owner/DBA reconciliation, not an overwrite. Procedure definitions are versioned and re-applicable after reviewed correction; do not restore configuration blindly. SQL Server rollback/UAT/recovery is an owner/DBA operation and remains unperformed. No SQL Server test database is created.

## Verification evidence

| Check | Evidence | Limitation |
|---|---|---|
| API build | `dotnet build src/KLOP.Platform.Api/KLOP.Platform.Api.csproj --configuration Release` — succeeded, 0 warnings, 0 errors | Compile only; no SQL/API startup |
| Backend isolated tests | `dotnet test tests/KLOP.Platform.UnitTests/KLOP.Platform.UnitTests.csproj --configuration Release` — 170 passed, 0 failed | Fake repository/contract tests; no SQL Server |
| Frontend | `npm run api:types`, `npm run typecheck`, `npm test -- --run`, `npm run build` — succeeded; 15 test files / 100 tests passed | Local contract/type/unit/build only; build reports existing third-party Rollup comment warnings |
| SQL scripts | Static SQL contract tests included in backend suite passed; scripts manually reviewed | No SQL parse/compile/execution evidence |
| CI / deployment | KLOP CI run `46125362817` on commit `29e3d2d` completed with `action_required`; it had 0 jobs and the failed-job log query reported no failed jobs | GitHub did not execute CI jobs; approval is required before CI evidence exists. No live deployment/UAT claim |

The repository's separate `scripts/validate_static.py` check remains a known unrelated failure: it references the removed legacy `src/KLOP.Platform.Infrastructure/KlopRepository.cs` path. It was not changed as part of this issue. No model identity has been confirmed from task evidence: **UNVERIFIED**.

## Owner decisions still required

- Whether the proposed requester/approver/applier separation is acceptable.
- Whether `database.command_timeout_seconds` may ever become editable; it remains HOLD and existing `IsEditable=0`.
- Any deliberate change to policy bounds, the safe inventory, or missing/inactive readiness interpretation.
- Which already-existing database principal receives the seven EXECUTE grants.
- Role mapping/readiness authorization and any owner-specific manual SQL review.
- Development SQL Server execution, postdeploy metadata checks, live UAT, service restart planning, deployment, and acceptance.
- SMTP settings/values and any secret/configuration resolution remain explicitly manual and out of scope.

## Owner/DBA checklist (all HOLD)

- [ ] Review exact source/base and verify the actual Development target without creating a test DB.
- [ ] Approve the ERD, safe key allowlist, bounds, lifecycle, immutability, audit projection, and separate actor rules.
- [ ] Approve policy management separately from the v1.12 schema seed; do not automatically unlock the candidate.
- [ ] Approve permissions and role mapping separately; no guessed user IDs or role readiness activation.
- [ ] Review each SQL template, expected object/column/constraint seed map, preflight and rollback/recovery plan.
- [ ] Confirm an existing runtime principal and approve only the listed EXECUTE grants.
- [ ] Perform separately authorized Development deployment, metadata-only postdeploy validation, and UAT.
- [ ] Confirm restart/pending-runtime semantics and retain existing registration, notification, bootstrap, and frozen-baseline behavior.
- [ ] Review current-head CI and security results before any owner-authorized merge; the agent does not merge.
