# Platform Legal Documents SQL Change Manifest

## Status and target

- Target: Development `KlopPlatformDB`.
- Baseline: frozen v1.6. This is an additive v1.7 proposal; v1.6 files are not changed.
- Execution status: **NOT EXECUTED**. No SQL mutation, migration, grant, role assignment, document registration, or publication was performed.
- Review required: database owner, IAM/security owner, and legal-document policy owner.

## Migration delta

`klop-next-platform-api/database/migrations/v1.7/001_platform_legal_documents.sql`

The script:

1. Guards the database name and required verified v1.6 objects.
2. Adds nullable submitter identity/time fields and an FK to legal versions.
3. Adds append-only approval/rejection decision history with reviewer, note, UTC time, request ID, and correlation ID.
4. Extends legal version state checks to support `PENDING_APPROVAL`.
5. Seeds eight PLATFORM permission codes and seven audit action codes idempotently.
6. Links the existing PLATFORM `SUPER_ADMIN` role to all eight capabilities. Links existing `PLATFORM_SUPPORT` only to read, draft-create, draft-edit, and draft-preview. It creates no roles and does not change `iam.PlatformRoleAssignments`.
7. Adds session-aware effective PLATFORM permission validation and legal-document read/write workflow procedures.
8. Replaces the v1.6 version/scope guards with lifecycle-aware guards that prevent content mutation after submission, invalid transitions, version deletion, scope changes after draft, and approval-decision edits/deletes.
9. Audits upload, metadata edit, submission, approval/rejection, publication, and archival with actor and request/correlation metadata.

Permission codes:

- `platform.legal_documents.read`
- `platform.legal_documents.draft.create`
- `platform.legal_documents.draft.edit`
- `platform.legal_documents.draft.preview`
- `platform.legal_documents.submit`
- `platform.legal_documents.approve`
- `platform.legal_documents.publish`
- `platform.legal_documents.archive`

The proposed role links have security impact and must be explicitly approved before execution. If current policy does not approve full legal permissions for every holder of the existing SUPER_ADMIN role, revise the mapping before applying; do not make manual user assignments as a workaround.

## Runtime grant template

`klop-next-platform-api/database/security/v1.7_platform_legal_documents_runtime_grants_TEMPLATE.sql`

Review-only EXECUTE grants for the new IAM/legal procedures to the existing `klop_app_runtime` database role. It intentionally performs no table DML grants, database role/login creation, or role membership changes. It checks procedure availability and ownership-chain prerequisites. Apply only after the migration and DBA verification.

## Required non-SQL configuration

- Configure `LegalDocuments:StorageRoot` to a private, non-webroot path with appropriately restricted filesystem ACLs. The source does not hardcode the supplied Windows PDF path.
- Keep `PlatformLegalDocuments:AdministrationEnabled` false until schema, permissions, runtime grants, and storage are ready. Routes are omitted by default and mapped only when explicitly enabled.
- The existing upload cap is read from `legal.maximum_upload_bytes`; the API also caps at 50 MiB. The verified Development setting was 10 MiB.

## Pre-approval checks

1. Compare every referenced column, key, trigger, audit code/result type, permission scope, and configuration field with a fresh read-only Development catalog snapshot.
2. Review deployment execution in an approved SQL Server client with stop-on-error behavior, transaction handling, backup/rollback strategy, and target DB confirmation.
3. Review role-permission inheritance and existing Super Admin/Support holders. Confirm whether the proposed assignment is approved.
4. Confirm runtime schema ownership and the actual mapping of `klop_app_runtime` before applying the grant template.
5. Do not execute against Production; do not create a TEST database; do not rerun v1.6.
6. After approved deployment, enable the feature flag and perform the manual full-stack verification in `PLATFORM_LEGAL_DOCUMENTS_BACKEND_REPORT.md`.
