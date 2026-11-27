# KLOP isolated SQL integration test enablement

## Current gate

This package is **prepared but not applied**. Read-only inspection found no `KlopPlatformDB_TEST` database. The live Development API identity maps to `dbo` and is a SQL Server `sysadmin`; it must not be used by the API or integration tests. No SQL login/user, database, schema, grant, or fixture was created by this work.

The v1.1 frozen SQL source and the v1.2/v1.2.1 draft source packages are available under the sibling `document` directory. The schema bundle below references those sources without copying or modifying them. v1.5 auth/session definitions and v1.4 settings use the active backend's versioned SQL artifacts.

## DBA-reviewed execution order — approval required

1. Establish an approved change/test ticket and a dedicated non-sysadmin Windows/Entra service identity outside SQL. Do not use SQL authentication with an embedded password.
2. Review and, only after explicit approval, execute `001_create_test_database_TEMPLATE.sql`. It creates an empty database only, defaults to no-op, refuses to overwrite an existing database, and is restricted to `DEV-PC\SQLEXPRESS`.
3. Review and approve `002_deploy_test_schema_TEMPLATE.sql`. It deploys the frozen v1.1 source followed by v1.2 and v1.2.1 draft sources, the existing reviewed Development configuration seed, v1.4 settings, then v1.5 auth/session procedures. It requires a blank test database and explicit SQLCMD approval. Do not run any included source against Development or Production.
4. `002_deploy_test_schema_TEMPLATE.sql` includes the referenced reference/configuration seeds. `003_seed_test_runtime_configuration_TEMPLATE.sql` is a separately guarded, idempotent way to apply the v1.3/v1.4 configuration seeds if needed. These scripts do not overwrite existing configuration rows. A local SMTP sink on `127.0.0.1:1025` is required for API registration/email-verification tests; the scripts do not install or start one.
5. Review and approve `database/security/001_runtime_principal_TEMPLATE.sql`, connect directly to `KlopPlatformDB_TEST`, and map a pre-created non-admin login to `KLOP_PLATFORM_TEST_RUNTIME`. It adds that user to `klop_app_runtime` and grants EXECUTE on only the 20 mapped procedures. It does not create server logins, set passwords, revoke grants, or grant table DML.
6. Connect as the actual test identity and run `database/security/002_runtime_identity_validation_READONLY.sql`, then run `006_validate_test_database_READONLY.sql` as a DBA for object/configuration/signature evidence. The runtime validator must pass as the actual identity; a DBA's `EXECUTE AS` simulation is not a substitute.
7. After separate security and test approval, run `004_run_integration_tests_TEMPLATE.ps1` with an approved ticket and `-ApprovePersistentTestData`. The .NET fixtures create unique users, tenants, and sessions through Stored Procedures; they commit data and do not clean it per test.
8. After stopping all API/test connections and capturing test evidence, review `005_cleanup_test_database_TEMPLATE.sql`. It defaults to no-op and drops only the exact disposable `KlopPlatformDB_TEST` database; it will not kill active sessions or delete the external Windows/Entra login.

Run SQLCMD from `klop-next-platform-api` for `:r` include paths. The template SQLCMD variables default to `NO`/`UNSET`. Setting a variable is not a substitute for approved change control. Never run these scripts against Production. Do not rerun v1.5 migrations against Development; its procedures already exist there.

## Test identity contract

The integration test fixture now requires:

- Server `DEV-PC\SQLEXPRESS` and database exactly `KlopPlatformDB_TEST`.
- A non-empty approval ticket and explicit persistent-data opt-in.
- SQL database user `KLOP_PLATFORM_TEST_RUNTIME`, member of `klop_app_runtime`.
- No `sysadmin`, `db_owner`, `db_ddladmin`, `db_datareader`, or `db_datawriter` membership.
- Procedure-based fixture setup only; tests do not query application tables directly.

Each test run creates persistent records. The cleanup boundary is dropping this disposable database after evidence is saved, not issuing broad row deletes against application tables.

## Known blockers

- Database provisioning and permission changes remain **NOT EXECUTED** pending explicit approval.
- The live Development identity is `dbo`/`sysadmin` and the existing runtime role has no members and only one explicit procedure grant; no change was made to that identity or role.
- A test SMTP sink and dedicated test login/service identity have not been provisioned.
- The real-browser auth workflow and SQL-backed integration tests remain **NOT RUN**.
