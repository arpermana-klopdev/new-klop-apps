-- REVIEW ONLY. DBA must verify effective permissions and ownership chaining before applying.
-- Required by the v1.4 backend's database-driven tenant-type registration lookup.
IF DATABASE_PRINCIPAL_ID(N'klop_app_runtime') IS NULL
    THROW 52400, 'Runtime database role is missing.', 1;

GRANT EXECUTE ON OBJECT::mst.usp_TenantType_GetAll TO klop_app_runtime;
GO
