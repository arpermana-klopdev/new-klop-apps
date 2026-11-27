# Logging and observability

## Application logs

Serilog uses structured console output and configuration-based minimum levels. ASP.NET request logging records method/path/status/duration, endpoint, correlation ID, and trace ID. Request and response bodies are not captured.

Database failures log only the SQL error number; unexpected failures log the exception type. Verification email failures log the failure type and that the database operation already committed. No password, token, hash, email body, SQL parameter, or raw exception message is logged.

Container/platform log storage is expected to provide access controls, retention, and rotation. The app does not write local log files by default.

## Distributed telemetry

OpenTelemetry instruments ASP.NET Core, HttpClient, and SqlClient. When `OTEL_EXPORTER_OTLP_ENDPOINT` is configured, traces and metrics are exported through OTLP; without it, instrumentation remains available to the hosting environment but no remote exporter is configured.

HTTP request correlation is returned in `X-Correlation-Id` and response metadata. Incoming IDs are parsed as GUIDs; otherwise the application generates one. Activity trace IDs remain separate. SqlClient instrumentation does not record application request bodies or credential values.

## Database audit and security events

The SQL procedures write authoritative audit/security events in the protected mutation transaction. Do not duplicate those events in Serilog or treat logs as a replacement for database audit records.

## Operations

Configure minimum log levels using the environment-specific Serilog section. Restrict console log access and apply retention at the container/runtime sink. Never enable body logging to troubleshoot authentication; use correlation and trace IDs instead.
