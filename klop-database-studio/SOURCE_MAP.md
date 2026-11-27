# Source reconciliation
Commit: `18a593fb7bcd5d4a6cca3c53b8918cd9b0acf28c`

| Inspected file | Use |
|---|---|
| document/KLOP_Platform_SQL_v1.1/01_Tables/010_master_tables.sql | 15 master definitions |
| document/KLOP_Platform_SQL_v1.1/01_Tables/020_configuration.sql | configuration structure |
| document/KLOP_Platform_SQL_v1.1/02_Constraints/030_foreign_keys_indexes.sql | uniqueness, relationships and checks |
| document/KLOP_Platform_SQL_v1.1/03_Seed/040_reference_seed.sql | historical catalog/role/permission seeds |
| document/KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT/sql/01_Tables/010_new_masters.sql | three additional master tables |
| document/KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT/sql/01_Tables/020_iam_tenant.sql | IAM and tenant tables |
| document/KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT/sql/01_Tables/030_audit_events.sql | three audit tables |
| document/KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT/sql/02_Constraints/040_foreign_keys_indexes_checks.sql | core relationships, indexes, checks |
| document/KLOP_PLAT_DB_FOUNDATION_1_2_DRAFT/sql/03_Seed/050_new_master_seed.sql | proposed master seed rows |
| klop-next-platform-api/database/migrations/v1.6/001_registration_onboarding_schema.sql | onboarding and legal tables and status seed |
| klop-next-platform-api/database/migrations/v1.7/001_platform_legal_documents.sql | approval decisions, submitted columns and publication state |
| klop-next-platform-api/database/migrations/v1.8/001_registration_terms_policy.sql | terms config key; not applied |
| klop-next-platform-api/database/migrations/v1.10/002_platform_registration_permissions_APPROVAL_TEMPLATE.sql | unexecuted permission proposal; not seeded |
| klop-next-platform-api/database/migrations/v1.10/003_tenant_permission_policy_APPROVAL_TEMPLATE.sql | staged 3 new tables + RolePermissions delta; no grants applied |
| klop-next-platform-api/docs/CONFIGURATION_CATALOG.md | key/type catalog only, values deliberately absent |

Partial source reconstruction: schema was manually projected from inspected definitions. Stored procedure bodies and actual SQL deployment state were not imported, all migration scripts have not been exhaustively reconciled, and baseline v1.2.1 validation evidence was not used as live data. Do not equate this file with a full SQL Server replica. Notification #11 not included. No actual user data, credentials, approvals, or SMTP settings copied. Version 1.0 is not FROZEN.
