# KLOP Development Changelog

## v1.3 DRAFT — 2026-11-19

One integrated delivery requested, no staged freeze.

- Prepared nine new Stored Procedures for local login, failure lockout, email challenge resend, session creation/validation, refresh rotation/replay revocation, logout, user profile and own-tenant listing.
- Added Development-only SQL config-key seed proposals; runtime settings read from `cfg.SystemConfigurations` using existing `cfg.usp_Configuration_GetByKey`. No application secrets in appsettings.
- Prepared Clean Architecture-style four-project ASP.NET Core solution with Dapper/SqlClient, key reference to Azure Key Vault, asymmetric JWT, local SMTP verification, tenant APIs and protected role/membership changes.
- Added xUnit unit tests, disposable SQL clone integration/concurrency harness, SQL read-only invariant checks, 32-case test matrix, and security/risk register.
- Preserved frozen checkpoint and all previous version scripts unchanged.

**Execution status**: Source prepared and limited static checks only. SQL v1.3 DRAFT has NOT been deployed to Development/Production. .NET build/test and SQL functional/security testing have NOT run. Production release prohibited until test evidence and security approvals are obtained.
