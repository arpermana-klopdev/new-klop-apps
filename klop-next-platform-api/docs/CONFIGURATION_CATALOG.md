# Configuration catalog and runtime source

`cfg.SystemConfigurations` remains the only persisted business/runtime configuration store. `cfg.usp_Configuration_GetByKey` and `RuntimeSettings.Load` remain authoritative. Runtime settings are loaded at process startup and held in memory; the management catalog is a protected metadata projection and never claims to read the live in-memory value.

The v1.12 proposal does not change the configuration loader, create a competing value store, edit bootstrap settings, or execute SQL. It does not disclose `ConfigurationValue`, `DefaultValue`, patterns, allowed-values JSON, secret names/references, or unclassified key names. `PLAIN` is not a disclosure grant. Only the explicit non-sensitive allowlist in the v1.12 catalog procedure can be returned. Unclassified database rows contribute only to an aggregate count.

## Bootstrap settings stay separate

Infrastructure bootstrap values remain in environment-specific `appsettings` and environment variables:

| Setting | Purpose |
|---|---|
| `Sql:Server`, `Sql:Database`, `Sql:Authentication` | Environment-specific SQL connection bootstrap |
| `Sql:TrustServerCertificate` | Development-only certificate override |
| `KeyVault:VaultUri` | Environment-specific Key Vault endpoint |
| `AllowedHosts` | Explicit host filtering |
| `ForwardedHeaders:KnownProxies` | Explicit trusted proxy IPs |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Optional telemetry endpoint |

Development and Production appsettings are not edited by this feature. No credentials, key material, connection strings, SMTP configuration, or business flags are moved into bootstrap configuration.

## RuntimeSettings source inventory

The safe management catalog contains metadata for only the following keys consumed by the current `RuntimeSettings.Load` implementation. It does not return their persisted values. Static ranges below are the typed runtime validator bounds; database metadata bounds are intersected when a proposal is validated.

| Configuration key | Type/storage | Runtime constraint | Management |
|---|---|---|---|
| `auth.access_token_minutes` | INTEGER / PLAIN | 5–60 | Metadata only; HOLD |
| `auth.refresh_token_days` | INTEGER / PLAIN | 1–30 | Metadata only; HOLD |
| `auth.email_verification_hours` | INTEGER / PLAIN | 1–24 | Metadata only; HOLD |
| `security.max_login_attempts` | INTEGER / PLAIN | 3–10 | Metadata only; HOLD |
| `security.password.min_length` | INTEGER / PLAIN | 12–128 | Metadata only; HOLD |
| `security.auth_requests_per_minute` | INTEGER / PLAIN | 1–120 | Metadata only; HOLD |
| `registration.personal.enabled` | BOOLEAN / PLAIN | Strict boolean | Metadata only; HOLD |
| `registration.organization.enabled` | BOOLEAN / PLAIN | Strict boolean | Metadata only; HOLD |
| `registration.legal_consent_enforcement` | BOOLEAN / PLAIN | Strict boolean; v1.8 enforcement source | Metadata only; HOLD |
| `notification.email_verification_templates.enabled` | BOOLEAN / PLAIN | Optional boolean; absent means disabled | Metadata only; HOLD |
| `notification.email_verification_delivery_audit.enabled` | BOOLEAN / PLAIN | Optional boolean; absent means disabled | Metadata only; HOLD |
| `database.command_timeout_seconds` | INTEGER / PLAIN | 1–120 | Metadata only; HOLD; existing v1.4 source seed has `IsEditable=0` |

Presence is evaluated from current persisted metadata as `PRESENT`, `MISSING`, `INACTIVE`, or `INVALID`; no live environment was queried for this change, so actual presence is not asserted here. Policy status is separately `HOLD` unless explicitly reviewed by the owner. The v1.12 seed leaves every policy held and non-manageable. No user/role mapping or active readiness is proposed.

`database.command_timeout_seconds` is the only proposed value-workflow candidate. It is an INTEGER in the 1–120 runtime range, but the existing v1.4 seed explicitly marks it non-editable. This proposal does not flip that flag or the management policy; actual draft creation/apply therefore fails closed. Candidate unlock, editable policy, and role assignment need separate owner approval.

## Validation and startup semantics

The safe metadata catalog is not a replacement for startup validation. `RuntimeSettings.Load` trims required SQL values and validates the expected type/storage, URI/origin requirements, booleans, and fixed numeric ranges. Optional notification rollout gates default to `false` when absent and reject invalid type/value/storage when present. Registration legal-consent enforcement remains read by the existing loader and v1.8 SQL enforcement path; the Development bypass remains a separate default-off bootstrap option. None of these settings is hot-reloaded by v1.12.

SMTP host/from/account/credentials, Key Vault references and secret names, connection/JWT/signing material, and other sensitive or unclassified configuration are excluded from the management allowlist, result DTOs, request bodies, history, and UI. SMTP remains manual. This catalog is not a secret readiness endpoint.

## State and restart interpretation

The catalog reports persisted-row presence, safe metadata, edit/approval/restart flags, version, timestamps, and safe numeric constraints. It does not expose a current value or a default. An applied request would update the persisted row only after separate authorization and would record a restart-required pending state; the process’s startup-loaded `RuntimeSettings` would remain unchanged until an independently authorized service restart. There is no restart endpoint or automatic restart behavior.

See [SYSTEM_CONFIGURATION_V1_12.md](SYSTEM_CONFIGURATION_V1_12.md) for the proposed schema, permission matrix, migration order, evidence, and owner/UAT checklist.
