# Reconciliation sources

Source commit `36f563fdcdb70036ad5fd7d16e45c54b520c60a5`; v1.0 input DB Git blob `7dc47b14baa7636f1446aeac368b62407bd3f67d` verified by builder. Original root snapshot preserved.

| Source path (relative to repository) | Blob SHA | Projection |
|---|---|---|
| klop-next-platform-api/database/migrations/v1.7/001_platform_legal_documents.sql | 73549469b0defed2d684869738c8c7d7bc13fe6c | 8 legal permission definitions and proposed grant comparison |
| klop-next-platform-api/database/migrations/v1.10/002_platform_registration_permissions_APPROVAL_TEMPLATE.sql | 89ffee301a6fa88736496c812bd9a6ae26c435d8 | registration permission definition; prepared mappings only |
| klop-next-platform-api/database/migrations/v1.10/003_tenant_permission_policy_APPROVAL_TEMPLATE.sql | 492b6bd3b77c0c08d214ea2da537a5688f3ffba6 | 3 tables, scoped junction, metadata/readiness, account policy definitions, proposed contextual mappings |
| document/KLOP_UNIFIED_ROLE_PERMISSION_MATRIX_RECONCILIATION.csv | 9ad07d45b3a65d75d0d91bf6cc4469d41ab1dcd5 | historical role/permission inventory and caveats; not current DB evidence |
| klop-next-platform-api/database/migrations/v1.11/001_notification_schema_APPROVAL_TEMPLATE.sql | 0d70fce0c2d1a6b0cf50efc2cd011c7780c44580 | 13 tables, constraints, two indexes, immutable version triggers |
| klop-next-platform-api/database/migrations/v1.11/003_notification_seed_APPROVAL_TEMPLATE.sql | 238b4d7cf9738bd5c7bbfa9db1b327b6ee722303 | exact reference seed, two off gates, draft recipe deferred |
| klop-next-platform-api/database/migrations/v1.11/004_notification_permissions_APPROVAL_TEMPLATE.sql | 72e5d26c8637d0e9cb6414694aac2528b58f9b3f | 10 notification permission definitions |
| klop-next-platform-api/database/migrations/v1.11/006_notification_authorization_delta_APPROVAL_TEMPLATE.sql | 5b2e249946ccc6d44b3e9574695a090ca3b4ed18 | notification HOLD-only metadata; no mapping |
