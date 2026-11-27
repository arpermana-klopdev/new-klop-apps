# Global Compact Logging Implementation Report

**Standard:** KLOP-COMPACT-LOGGING-1.0  
**Project:** KLOP Platform  
**Status:** IMPLEMENTED  
**Build:** PASS  
**Unit tests:** PASS  
**File output:** VERIFIED (isolated local HTTP host and temporary directory)  
**SQL database:** UNCHANGED  
**Production readiness:** NOT YET VERIFIED

## 1. Executive Summary

Implemented global HTTP request-completion logging using the existing Serilog setup. The prior ASP.NET Serilog request logger was replaced by one completion middleware; a whitelist formatter writes concise entries to a UTF-8 rolling file at the configured `logs/log.txt` path. Correlation IDs, route templates, safe result codes, status-based severity, successful health-check exclusion, and non-fatal file-sink fallback are covered by unit tests. SQL audit/security/business logging and database artifacts were not modified.

## 2. Existing Logging Architecture

The API already used Serilog, console output, `UseSerilogRequestLogging`, OpenTelemetry instrumentation, correlation context, centralized API exception mapping, and SQL-backed audit/security/business events. The request logger was console-oriented and did not provide the required compact route-template file format or safe result-code contract. It also ran outside exception mapping such that the observed status could differ from the final mapped response. The correlation header accepted GUIDs without the new exact format and empty-value constraints.

## 3. Identified Gaps

- No configured rolling compact file sink at `logs/log.txt`.
- Existing request logging did not meet the deterministic seven-field format or whitelist-only file output requirements.
- Request completion status/result mapping and exception-finalization behavior needed centralization.
- No explicit trusted endpoint-metadata policy for excluding successful health checks.
- Correlation header validation needed to reject malformed, repeated, oversized, and empty GUID values.
- Runtime log file patterns were not ignored in nested API project log directories.

## 4. Implementation Decisions

- Replaced, rather than duplicated, `UseSerilogRequestLogging` with `CompactRequestCompletionLoggingMiddleware`.
- Middleware order is correlation context, completion logger, centralized exception handler, and downstream routing/endpoint middleware. The completion logger observes the final mapped response and emits at most one completion event per request.
- Added a small Serilog text formatter that writes only marked completion/process events and only explicitly selected properties. Other Serilog structured events remain available to existing sinks; arbitrary message text and properties are not serialized into the compact file.
- Kept bootstrap logging independent of SQL-loaded runtime settings. Invalid/unwritable file logging reports a safe fallback diagnostic and does not prevent request processing.
- Successful health probes are excluded only when trusted endpoint metadata marks them as routine health endpoints; failed probes remain logged.

## 5. Changed Source Files

- `.gitignore` - ignore runtime `.txt`, `.log`, and `.json` files in any `logs` directory.
- `src/KLOP.Platform.Api/KLOP.Platform.Api.csproj` - add `Serilog.Sinks.File` 7.0.0.
- `src/KLOP.Platform.Api/Bootstrap/ObservabilityRegistration.cs` - configure Serilog file sink, formatter, and safe fallback.
- `src/KLOP.Platform.Api/Bootstrap/RequestPipeline.cs` - register correlation, completion, and exception middleware once in the intended order.
- `src/KLOP.Platform.Api/Bootstrap/ServiceRegistration.cs` - expose the correlation response header through the existing CORS policy.
- `src/KLOP.Platform.Api/Extensions/ApiHelpers.cs` - attach safe request result codes without changing response payload contracts.
- `src/KLOP.Platform.Api/Logging/CompactLogFormatter.cs` - field policy, sanitization, configuration validation, and file sink setup.
- `src/KLOP.Platform.Api/Logging/RequestLoggingMiddleware.cs` - correlation, request completion, exception mapping, and important failure diagnostics.
- `src/KLOP.Platform.Api/Endpoints/System/SystemEndpoints.cs` - mark health endpoints using trusted metadata.
- `src/KLOP.Platform.Api/Health/SqlServerReadinessCheck.cs` - emit a safe readiness failure event.
- `src/KLOP.Platform.Api/appsettings.Development.json` and `appsettings.Production.json` - non-secret file sink defaults.
- `src/KLOP.Platform.Application/Features/Authentication/AuthenticationService.cs` - log verification email delivery failures as correlated process events.
- `tests/KLOP.Platform.UnitTests/Logging/CompactLoggingTests.cs` - formatter, middleware, correlation, health, exception, file output, concurrency, rotation, and failure-fallback tests.

No database schema, stored procedure, seed, grant, or SQL runtime principal files were changed.

## 6. Final Compact Log Format

HTTP completion lines contain exactly seven logical fields separated by ` | `:

`TimestampUtc | Level | Method RouteTemplate | HttpStatus | DurationMs | CorrelationId | ResultCode`

Timestamps use invariant UTC ISO 8601 with millisecond precision (`yyyy-MM-ddTHH:mm:ss.fffZ`). Duration is a non-negative integer followed by `ms`. Route templates come from endpoint metadata; requests without a matched route use `UNMATCHED_ROUTE`. Pipe characters, line breaks, and control characters are sanitized. The formatter appends one line terminator per emitted event.

Important process events use the separate six-field form:

`TimestampUtc | Level | EVENT | Component | CorrelationId | ResultCode`

## 7. Sample Sanitized `log.txt` Output

```text
2026-11-22T13:05:10.125Z | INFO | POST /api/v1/auth/register | 202 | 135ms | 54e3a8b7-1c2d-4a56-9f31-1f6247ac803e | REGISTER_ACCEPTED
2026-11-22T13:06:00.132Z | INFO | POST /api/v1/auth/login | 200 | 112ms | 2e49e7c6-1669-4cd7-8cb1-93cc6e731497 | LOGIN_SUCCESS
2026-11-22T13:07:10.148Z | WARN | POST /api/v1/auth/login | 401 | 65ms | 86877a7e-2330-4981-980f-d80ae21d1f6c | INVALID_CREDENTIALS
2026-11-22T13:08:20.113Z | ERROR | POST /api/v1/auth/register | 500 | 93ms | 24594fd0-8472-4c7b-8b2f-2ca50414dfd4 | INTERNAL_ERROR
2026-11-22T13:08:21.113Z | WARN | EVENT | EmailVerification | 24594fd0-8472-4c7b-8b2f-2ca50414dfd4 | SMTP_DELIVERY_FAILED
```

The values above are illustrative and contain no real account data or credentials.

## 8. Correlation ID Behavior

`X-Correlation-Id` is accepted only when present once, exactly 36 characters, parseable as GUID `D` format, and non-empty. Otherwise the API generates a new GUID. The same full GUID is placed in request context, `TraceIdentifier`, Serilog `LogContext`, completion/process diagnostics, and the response header. The existing CORS policy exposes that response header. Correlation IDs are diagnostic identifiers only and are not used for authorization.

## 9. HTTP Status and Log Level Mapping

- 2xx and 3xx: `INFO`.
- 4xx, including 400/401/403/404/409/422/429: `WARN`.
- 5xx, including 500/503: `ERROR`.
- Unhandled exceptions: `ERROR` with `INTERNAL_ERROR`, even if a response had already started.
- Safe result codes are derived from status and known endpoint metadata or retained from the existing safe `INVALID_CREDENTIALS` code. Unknown codes fall back to `REQUEST_FAILED` in the formatter.

This changes diagnostics only; HTTP response bodies and endpoint status contracts remain unchanged.

## 10. Security and Redaction Controls

- The file formatter is whitelist-based; it does not render message templates, exception text, arbitrary Serilog properties, request/response bodies, raw URL paths, or query strings.
- Request routes use server endpoint templates. Method, route, component, and result fields are bounded and sanitize `|`, CR/LF, and control characters.
- Correlation IDs are validated GUIDs. Result codes come from a fixed safe set.
- Passwords, password hashes, JWTs, refresh tokens, verification tokens, authorization headers, cookies, connection strings, email addresses, and identity/document data are not included in compact completion/process fields.
- Exception messages and stack traces are not serialized to the compact file or public API error response. Restricted structured diagnostics may include safe failure type or SQL error number, not raw request data.

## 11. File Sink Configuration

Development and Production defaults use `Logging:File:Path=logs/log.txt`, relative to the API content root, with UTF-8 without BOM and append behavior. Settings can be overridden through the existing configuration providers (for example `Logging__File__Path`, `Logging__File__MaximumFileSizeBytes`, and `Logging__File__RetainedArchiveCount`). Paths are resolved and size/retention settings validated before sink registration. Serilog `SelfLog` and a synchronized stderr fallback provide safe diagnostics if file logging cannot initialize or write; logging failure is not intended to fail business requests.

## 12. File Size and Rolling Policy

Default maximum size is 20 MiB. Serilog rolls by size; the sink can exceed the configured threshold by the size of the event that triggers rollover. This uses the standard file sink rather than custom rotation logic.

## 13. Retention Policy

The default is 10 retained archives plus the current file. The implementation configures Serilog's retained-file count as 11 because that count includes the active file. On size roll, Serilog uses numbered suffixes such as `log_001.txt`; `logs/log.txt` is the initial active filename and is not guaranteed to remain the filename currently receiving writes after rollover. Production storage and retention must be configured for the deployment's operational policy; local disk durability is not assumed.

## 14. Health Check Exclusion

Routine successful `/health/live` and `/health/ready` requests are excluded from `log.txt` via endpoint metadata. Failed health responses are logged under normal status severity policy. A failed SQL readiness dependency also produces a safe `DEPENDENCY_UNAVAILABLE` process event. Health HTTP behavior and response payloads are unchanged.

## 15. Important Process Event Policy

Only meaningful failures are marked for compact process-event output: mapped SQL operation failures/rejections, unhandled request failures, SQL readiness failures, and verification email delivery failures. These events include a safe component/result code and correlation ID, not user data or raw exception messages. Routine successful database/email operations and method-level tracing are not added. Existing SQL audit/security/business event behavior remains separate.

## 16. SQL Audit Compatibility

No changes were made to `aud.AuditEvents`, `aud.SecurityEvents`, `aud.BusinessEvents`, stored procedures, schema, transaction boundaries, or database configuration. The HTTP middleware does not insert SQL audit rows and does not replace database audit/security/business logging. Existing correlation metadata continues through application repository calls where supported.

## 17. Build Results

Command: `dotnet build KLOP.Platform.sln`

**Result:** PASS - all solution projects built, 0 warnings, 0 errors.

## 18. Unit Test Results

Command: `dotnet test tests\KLOP.Platform.UnitTests\KLOP.Platform.UnitTests.csproj --no-build --no-restore`

**Result:** PASS - 97 passed, 0 failed, 0 skipped. The suite includes an isolated loopback Kestrel request writing to a temporary `logs/log.txt`, format/privacy assertions, concurrent writes, rolling/retention, and file initialization failure coverage. Existing authentication/register unit tests ran as part of the same suite. SQL integration and mutating tests were not run.

## 19. No Database Mutation Evidence

The work used source edits, `dotnet build`, and the non-mutating unit test project only. The file-output test creates a temporary local directory and an isolated in-process HTTP host; it does not configure or call the KLOP SQL repository. No SQL connection, database creation, SQL mutation, user seeding, stored procedure execution, or production operation was performed. Therefore the database and frozen baseline were not modified by this task.

## 20. Remaining Risks and Limitations

- Full API startup and SQL integration were not exercised because startup loads runtime settings from the configured database; SQL integration remains unverified.
- Production file path availability, directory permissions, storage durability, external log shipping, and operational retention were not verified in a production-like deployment. Configure these explicitly before release.
- Size rolling uses Serilog's standard numbered archive naming; after rollover, consumers must not assume `log.txt` remains the active file.
- The in-process loopback file test verifies output mechanics, not deployment-level logging availability or production readiness.

## Final Status

- **IMPLEMENTED**
- **BUILD PASS**
- **UNIT TEST PASS** - 97/97
- **FILE OUTPUT VERIFIED** - isolated temporary filesystem test
- **SQL DATABASE UNCHANGED**
- **PRODUCTION READY: NOT YET VERIFIED**
