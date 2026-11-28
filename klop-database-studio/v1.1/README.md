# KLOP Database Studio v1.1 — offline working projection

**WORKING / SQL HOLD / NOT LIVE / NOT FROZEN.** Source checkpoint `36f563fdcdb70036ad5fd7d16e45c54b520c60a5` (Notification Management PR #12 merged). This snapshot lives in `klop-database-studio/v1.1/`; the original v1.0 files in its parent are unchanged. The SQL Server scripts remain canonical. Do not deploy SQLite or connect the application runtime to it.

## Scope and decisions
- Existing 44 domain tables + 3 RBAC tables + 13 Notification tables = 60 domain tables; 3 internal Studio tables remain. `mst__RolePermissions` has contextual tenant FK, separate partial unique indexes for NULL/non-NULL context, and scope triggers.
- 37 permission definitions (16 historical, 8 legal, 1 registration, 2 matrix, 10 notification); 37 metadata rows; 6 readiness statuses; 16 informational account policies. The ten notification permissions are HOLD, unassigned, not editable/effective. `ACTIVE` and `SYSTEM RESTRICTED` readiness codes from source are catalog states, not authorization grants.
- **No effective grants are stored:** the copied junction table is rebuilt empty, not a simulation of current production grants. The 28 historical mappings remain in v1.0; the 68 source-derived hypothetical contextual/seed mappings are in `seed_projection.json`, never assigned. This is an explicit offline safety decision, not an approved live matrix; some contextual rows may be ineligible under SQL Server effective-role policy. Do not apply the JSON to a database or infer effective permissions from it. The reconciliation CSV is historical evidence, not a substitute for the approved workbook or current DB inspection.
- EMAIL is the only catalog channel, `CONFIGURATION_REQUIRED`; both rollout/audit flags are explicitly `false`, approval-required. Existing 20 configuration placeholders remain disabled and null. No actual SMTP, Key Vault references, passwords, tokens, user/tenant or business records.
- The exact verification template recipe is in `seed_projection.json`. Template/version/approval/delivery tables remain empty because the SQL seed requires an actual approved actor. No guessed user IDs or approval. Validation creates an isolated memory-only actor/fixture and rolls it back.
- Original v1.0 projection is partial; this increment targets RBAC and Notification shapes and relevant reference definitions, not every prior SQL migration or all historical master seeds. No SQL Server or SMTP network actions, no deployment, no application changes.

## Usage
From `klop-database-studio/v1.1/` (Python 3, standard library):

```sh
python ../studio.py --db KlopPlatform.db inspect
python ../studio.py --db KlopPlatform.db validate
python validate.py
```

Rebuild into a **new** directory (the builder refuses overwrite and checks the original v1.0 DB Git blob). Copy the v1.1 `build.py`, `notification_schema.sql` and `validate.py` into that directory; then run `python build.py --base <path-to-klop-database-studio-v1.0-folder>` followed by `python validate.py --report validation.json`. The builder writes the new DB, `seed_projection.json`, and `schema_definition.json` alongside it. Timestamps and random SQLite rowversion placeholders mean independently rebuilt bytes can differ; compare logical schema and row counts, not byte identity. `SHA256SUMS.txt` identifies this exact committed snapshot.

Use version-specific paths for future approved design changes. Preserve prior snapshots. Do not commit SQLite WAL/SHM, local backups, live exports, credentials or personal records. Any subsequent mutation must be reviewed and versioned together with matching schema, seed and validation artifacts. SQL Server migration implementation stays with Copilot; execution stays manual by owner after HOLD lifted.

## Validation and limitations
`validate.py` reads the file read-only, copies it into memory, exercises 45 checks, rolls fixtures back and verifies unchanged snapshot bytes. Results are in `validation.json`. It checks schema relationships, scope uniqueness, default-off, actor and composite FKs, positive counters, single active version, active/archived immutability, outcome consistency, rollback, privacy boundaries. The fixture transitions are explicit SQL updates; they do **not** prove stored-procedure lifecycle enforcement, approval authorization, real rowversion concurrency or audit atomicity on SQL Server. SQLite uses text GUID/date and 8-byte BLOB rowversion placeholders; collation, text widths, identity semantics, server permission grants, transaction locking and T-SQL functions differ. The SQLite trigger uses NULL-safe comparison as a local integrity approximation. The v1.11 SQL role mappings/readiness activation, deployment, least-privilege identity and manual UAT remain HOLD.
