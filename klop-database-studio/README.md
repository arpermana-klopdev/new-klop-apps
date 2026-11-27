# KLOP Database Studio v1.0

**WORKING / SOURCE PROJECTION — not FROZEN, not a live SQL Server export, not production-ready.**

Source: `arpermana-klopdev/new-klop-apps`, main checkpoint `18a593fb7bcd5d4a6cca3c53b8918cd9b0acf28c` (PR #10 merged). This is an offline SQLite design database derived from inspected SQL definitions. SQL Server remains the authoritative deployment target. No production/development SQL Server was accessed. The current source projection includes v1.1/v1.2 tables, v1.6 registration/legal and v1.7 legal workflow shape. Intermediate procedure-only/config proposals are not executable here. v1.10 RBAC shape is staged in JSON, not applied. Notification Management (#11/PR #12) is not included; reconcile once its approved SQL contracts are available.

## Files
- `KlopPlatform.db` — current editable working database, 44 KLOP domain tables and 3 Studio metadata tables.
- `schema_definition.json` — projected SQLite schema, original SQL Server object names, version per object, and separate v1.10 proposed object definitions.
- `build.py` — reproducible initial reconstruction/seed generator; refuses to overwrite an existing database. This reproduces the source-based initial state, not later edits.
- `studio.py` — local SQLite inspection, integrity validation, backups and transactional SQLite script application with a change log. Explicit confirmation required. No SQL Server connection.
- `validation.json` — inventory counts and actual SQLite test results.
- `SOURCE_MAP.md` — inspected source paths and gaps.
- `SHA256SUMS.txt` — hashes for this initial package.

## Usage (Python 3, standard library)
```sh
python studio.py inspect
python studio.py validate
python studio.py backup KlopPlatform_v1.0_backup.db
python studio.py apply approved_sqlite_change.sql --version 1.1 --summary "Approved design change" --confirm-working-db
```
Run from this folder. `apply` accepts SQLite statements ending in semicolons; it backs up the database, performs an atomic change and writes an audit entry after validation. Do not execute untrusted SQL files. Preserve versioned copies of the database, updated schema/seed definitions and migration history together after each approved change. The original `schema_definition.json` and builder are a v1.0 snapshot; updating the `.db` alone does not regenerate those definitions. The tool is a local utility, not a substitute for database access controls.

## Data boundaries
- Historical seed from SQL source: 2 tenant types, 7 organization types, 6 roles, 16 permissions, 28 legacy role-permission mappings. This is not an effective authorization matrix and is not live data.
- Configuration catalog: 20 known key placeholders; values and default values NULL, rows disabled, no credential, no Key Vault URI or secret. Category inferred for catalog navigation. It is not a deployable seed. Real configuration remains manually managed by owner.
- User, tenant, session, token, legal document, registration transaction and audit data intentionally empty. No identity data or documents copied.
- Some reference seed data, later permission proposals and configuration defaults may be absent. Reconcile against versioned SQL and owner-approved master data before declaring completeness.

## SQL Server translation limitations
`schema.Table` is represented as `schema__Table`. BIGINT/IDENTITY -> SQLite INTEGER PRIMARY KEY where applicable; BIT -> INTEGER with check; DATETIME2 -> TEXT UTC; UNIQUEIDENTIFIER -> TEXT; ROWVERSION -> 8-byte BLOB default (no SQL Server monotonic concurrency semantics); binary(32) -> BLOB with length check; DECIMAL -> NUMERIC. SQL Server text lengths, exact column type/precision, collations, GUID ordering, clustered/covering indexes, actual default functions, SQL security, stored procedures, transaction isolation and engine-specific constraints are not equivalent. Most source relationships and basic constraints were represented; column order/index names may differ. Do not use historical grants for authorization. v1.10 nullable uniqueness needs an explicit two-part SQLite partial index design if previewed. No SQL Server migration generator is provided: generate reviewed T-SQL deltas from the canonical source, not mechanically from SQLite. Validate on SQL Server before deployment, after HOLD is lifted.

## Workflow
1. Discuss and approve database design. ChatGPT manages the SQLite working copy, makes versioned backups, records proposed changes and validates SQLite.
2. GitHub Copilot implements approved backend/UI and versioned SQL Server scripts in feature branches; ChatGPT reviews PR, verifies CI, and merges only if all gates pass.
3. Owner enters SMTP values and performs SQL Server deployment/live testing manually when approved. No new SQL Server test database and no live deployment while HOLD remains.
4. Attach or retain the complete package as Project File for subsequent work. Runtime storage is not an always-on persistent database. Do not publish binary data or secrets in GitHub. The versioned SQL Server files remain canonical.
