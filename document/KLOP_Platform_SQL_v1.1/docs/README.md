# KLOP Platform — Database Foundation v1.1

Scope: 15 master tables (`mst`) and 1 configuration table (`cfg`), following the decisions in this conversation. Development and Production only. No database is created or modified by these scripts until deliberately executed.

Execution order:
1. `00_Foundation/001_schemas.sql`
2. `01_Tables/010_master_tables.sql`
3. `01_Tables/020_configuration.sql`
4. `02_Constraints/030_foreign_keys_indexes.sql`
5. `03_Seed/040_reference_seed.sql`
6. `03_Seed/050_configuration_seed.sql`
7. `04_StoredProcedures/060_read_procedures.sql`
8. `05_Security/070_permissions_template.sql` (review and replace database-role/service-principal placeholders before deployment)

**Deliberate exclusions / outstanding implementation gates**
- IAM, tenant operational entities, audit and security-event transaction tables, transactional outbox, and the complete write-side Stored Procedures are planned for subsequent modules.
- Master/config changes MUST NOT be exposed through an administrative write API until audited write Stored Procedures and authorization controls are implemented. No direct INSERT/UPDATE/DELETE permissions are granted to runtime principals.
- `CreatedByUserId` and `UpdatedByUserId` are nullable placeholders. Add FKs when `iam.Users` exists.
- Documents and required legal-identity rules are **NOT** seeded as legal claims. `OrganizationIdentityRequirementGroups` and `OrganizationIdentityRequirements` are intentionally empty initially; review requirements with legal/compliance experts before enabling organization verification.
- Metadata tables are database-driven, while security invariants and permission-contract changes still require reviewed migrations and application policy updates.
- The sample configuration values are proposals, not production-approved policy. Production secret values must stay in Azure Key Vault (or equivalent), NOT in SQL Server.
- These scripts have been generated and structurally checked, but not executed against a live SQL Server instance in this environment.

Design document: `KLOP_Platform_Baseline_v1.1.xlsx` distributed separately. Keep SQL migrations and workbook revisions synchronized via change log.
