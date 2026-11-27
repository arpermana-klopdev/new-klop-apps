# Baseline lineage and protection

## Sources

- Integrated backend/SQL reference: `document/KLOP_PLATFORM_INTEGRATED_v1.3_DRAFT`.
- Immutable database checkpoint: `document/KLOP-PLATFORM-DB-DEV-CHECKPOINT-1.2.1-FROZEN-20261118`.
- v1.1 frozen foundation: `document/KLOP_Platform_SQL_v1.1`.
- v1.2 and v1.2.1 DRAFT schema/procedure sources: `document/KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT` and `document/KLOP_DB_FOUNDATION_1_2_1_DRAFT`.

The directory names above reflect the exact paths in this workspace. The v1.3 and checkpoint source packages are read-only references; no files in those directories were edited.

## Integrity and compatibility review

- Every entry in the v1.3 `SHA256SUMS.txt` matched before porting.
- All 12 checkpoint artifacts matched their `MANIFEST.json` SHA-256 and size entries.
- The original v1.3 checksum list is preserved as [`V1_3_SOURCE_SHA256SUMS.txt`](../V1_3_SOURCE_SHA256SUMS.txt). The target package checksum list is [`SHA256SUMS.txt`](../SHA256SUMS.txt); it excludes generated `bin`/`obj` outputs and the checksum list and version manifest themselves.
- v1.1 defines the master/config schemas, `cfg.usp_Configuration_GetByKey`, and `mst.usp_TenantType_GetAll` / `mst.usp_OrganizationType_GetAll`.
- v1.2 adds IAM, tenant, session, refresh-token and audit/security tables used by the v1.3 procedures.
- v1.2.1 defines the eight registration, verification, tenant, membership, and role procedures used by the existing contract.
- v1.3 defines nine additive auth/session/profile/list procedures and 15 API routes. Its SQL deployment and tests are explicitly `NOT EXECUTED` in the source manifest.
- v1.4 adds two SQL configuration rows and an EXECUTE grant template for the existing tenant-type read procedure. It adds no tables or stored procedures.

The checkpoint's Development deployment and read-only `PASS` status are owner-reported historical statements, not independent test evidence. Functional, concurrency, and runtime-security tests were unverified at checkpoint time.

## Source procedure map

The endpoint-to-procedure mapping is maintained in [API_ENDPOINTS.md](./API_ENDPOINTS.md) and database deployment status in [DATABASE_INTEGRATION.md](./DATABASE_INTEGRATION.md). No endpoint is backed by an invented procedure. The v1.4 additive grant is required because the port reads tenant type metadata from SQL rather than hardcoding it.

## Change record

The implementation is a new DRAFT version. It does not promote v1.2/v1.2.1 or claim a database deployment. See [../CHANGELOG.md](../CHANGELOG.md) and [../VERSION_MANIFEST.json](../VERSION_MANIFEST.json).
