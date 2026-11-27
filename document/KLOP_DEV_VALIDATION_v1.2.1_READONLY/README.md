# KLOP — Development Validation (v1.2.1 READ-ONLY)

**Execution report:** Project owner confirmed on 18 Nov 2026 that all scripts v1.1, v1.2, and v1.2.1 were executed in **Development without errors**. This is a *user-reported deployment outcome*, **not evidence of passed structural, security, concurrency, or integration tests**.

**Version governance:** `v1.1 FROZEN` unchanged. `v1.2` and `v1.2.1` remain DRAFT. This pack is an **independent validation/evidence bundle**, not a new database migration or a new FROZEN baseline.

## Run order (SSMS / sqlcmd)
1. Confirm target instance and DEVELOPMENT database manually. Run `00_environment.sql` and capture the result.
2. Run `01_object_inventory.sql`; check 33 expected tables and 24 expected procedures. Stop and investigate if any item missing.
3. Run `02_constraints_indexes.sql`; review 46 FKs, 30 additional indexes, and 10 additional CHECK constraints.
4. Run `03_reference_seed.sql`; verify 16 critical stable codes without extracting sensitive values.
5. Using a read-only *audit* principal, run `04_data_integrity_aggregate.sql` after confirming objects exist. It returns aggregate violation counts only.
6. DBA reviews `05_security_metadata.sql`. The role `klop_app_runtime` might not exist if optional v1.2.1 permission template was deliberately not applied. This is a **review**, not automatic failure.
7. Enter actual test evidence and execution timestamps into `KLOP_DEV_VALIDATION_TRACKER_v1.2.1.xlsx`.
8. Execute functional test matrix T01-T22 from v1.2.1 independently in isolated Development fixtures; this read-only pack does **not** run mutating integration tests.

## Important limitations
- SQL files use only SELECT/CTEs and session SET statements. They perform no persistent DDL/DML and call no mutating Stored Procedures.
- Some checks use data SELECT access; **do not grant runtime application extra SELECT permissions**. Use a DBA/read-only audit account.
- Missing catalog metadata may reflect insufficient permissions, not actual absence.
- Query results are not collected automatically. No SQL Server network access or actual execution has been performed by ChatGPT.
- Real security proof requires testing under actual login/API identity and concurrent sessions; checks of catalog metadata do not demonstrate tenant isolation, last-OWNER race safety, audit atomicity, or absence of privilege escalation.
- Do not provide screenshots/logs containing user emails, hashes, tokens or system secrets.
- Legacy architecture ARCH-04 single-tenant versus v1.1 B03 many-to-many remains a pending architecture decision.
- Production deployment requires explicit approval after test evidence and approved rollback plan.

## Reference packages
- v1.1 frozen original SQL and Excel (unchanged)
- v1.2 additive DB package (unchanged)
- v1.2.1 audited transactional SP package (unchanged)

## Contents
- `00_environment.sql` — capture instance and DB settings
- `01_object_inventory.sql` — expected tables & SP presence
- `02_constraints_indexes.sql` — FK trust, index presence/uniqueness, CHECK trust
- `03_reference_seed.sql` — reference code presence only
- `04_data_integrity_aggregate.sql` — aggregate data integrity, no PII
- `05_security_metadata.sql` — runtime principal permissions review
- `KLOP_DEV_VALIDATION_TRACKER_v1.2.1.xlsx` — editable evidence tracking
- `CHECKSUMS.sha256` — hashes of delivered files
