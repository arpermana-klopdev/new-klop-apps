# KLOP Platform Backend — 1.4 DRAFT

- Reference package: `KLOP-PLATFORM-INTEGRATED-1.3-DRAFT` (checksums verified before port).
- Database source: checkpoint `KLOP-PLATFORM-DB-DEV-CHECKPOINT-1.2.1-FROZEN-20261118`; frozen SQL artifacts remain unchanged.
- Target framework: `net10.0`.
- Build status: Release build succeeded with 0 warnings and 0 errors; restore passed.
- Unit tests: 17 passed.
- Development API smoke: readiness, Swagger/OpenAPI, JWKS and SQL-backed organization-type read passed; 15 API operations discovered.
- SQL catalog: all 20 mapped procedures are present by catalog check; the nine v1.5 auth/session procedure signatures pass read-only verification.
- SQL integration tests: 3 skipped / BLOCKED because no disposable `_TEST` database was opted in.
- SQL migrations: User reports running the v1.5 standalone migration; catalog evidence confirms all nine objects/signatures. This validation session ran no DDL.
- v1.5 runtime readiness: BLOCKED. Read-only post-deployment verification found 0/9 explicit EXECUTE grants for `klop_app_runtime`, and the role has no members. No successful authentication integration test has been executed; do not enable auth/session traffic.
- Production approval: NOT APPROVED.

The frozen checkpoint and original v1.3 source directory were not modified. See [docs/BASELINE_POINTER.md](docs/BASELINE_POINTER.md), [docs/DATABASE_DEPENDENCIES.md](docs/DATABASE_DEPENDENCIES.md), and [VERSION_MANIFEST.json](VERSION_MANIFEST.json) for lineage and evidence.
