-- Read-only v1.9 registration procedure post-deployment validation.
SET NOCOUNT ON;

IF DB_NAME()<>N'KlopPlatformDB'
    THROW 52950, 'Registration procedure validation is restricted to KlopPlatformDB.', 1;

DECLARE @Expected TABLE(SchemaName SYSNAME NOT NULL,ProcedureName SYSNAME NOT NULL,PRIMARY KEY(SchemaName,ProcedureName));
INSERT @Expected(SchemaName,ProcedureName) VALUES
    (N'iam',N'usp_ValidatePlatformPermission'),
    (N'iam',N'usp_GetPlatformPermissions'),
    (N'reg',N'usp_GetPlatformRegistrationSummary'),
    (N'reg',N'usp_ListPlatformRegistrations'),
    (N'reg',N'usp_GetPlatformRegistration'),
    (N'reg',N'usp_GetPlatformRegistrationTimeline');

IF EXISTS
(
    SELECT 1 FROM @Expected expected
    WHERE OBJECT_ID(QUOTENAME(expected.SchemaName)+N'.'+QUOTENAME(expected.ProcedureName),N'P') IS NULL
)
    THROW 52951, 'One or more v1.9 registration read procedures is missing.', 1;

IF EXISTS
(
    SELECT 1
    FROM (VALUES(N'usp_ValidatePlatformPermission'),(N'usp_GetPlatformPermissions')) required(ProcedureName)
    JOIN sys.procedures procedureInfo
        ON procedureInfo.object_id=OBJECT_ID(N'iam.'+required.ProcedureName,N'P')
    JOIN sys.sql_modules moduleInfo ON moduleInfo.object_id=procedureInfo.object_id
    WHERE moduleInfo.definition NOT LIKE N'%platform.registrations.read%'
)
    THROW 52953, 'Platform registration permission is missing from an IAM permission procedure.', 1;

IF EXISTS
(
    SELECT 1
    FROM @Expected expected
    JOIN sys.schemas schemaInfo ON schemaInfo.name=expected.SchemaName
    JOIN sys.procedures procedureInfo
        ON procedureInfo.schema_id=schemaInfo.schema_id AND procedureInfo.name=expected.ProcedureName
    JOIN sys.sql_modules moduleInfo ON moduleInfo.object_id=procedureInfo.object_id
    WHERE moduleInfo.definition LIKE N'%PasswordHash%'
       OR moduleInfo.definition LIKE N'%TokenHash%'
       OR moduleInfo.definition LIKE N'%VerificationToken%'
)
    THROW 52952, 'A registration read procedure references credential or verification token material.', 1;

SELECT N'PASS' AS ValidationStatus,expected.SchemaName,expected.ProcedureName,
       (SELECT COUNT(*) FROM sys.parameters parameterInfo
        WHERE parameterInfo.object_id=procedureInfo.object_id
          AND parameterInfo.parameter_id>0) AS ParameterCount,
       CONVERT(BIT,CASE WHEN EXISTS
       (
           SELECT 1
           FROM sys.database_permissions permission
           WHERE permission.grantee_principal_id=DATABASE_PRINCIPAL_ID(N'klop_app_runtime')
             AND permission.class=1 AND permission.major_id=procedureInfo.object_id
             AND permission.permission_name=N'EXECUTE' AND permission.state IN('G','W')
       ) THEN 1 ELSE 0 END) AS RuntimeExecuteGranted
FROM @Expected expected
JOIN sys.schemas schemaInfo ON schemaInfo.name=expected.SchemaName
JOIN sys.procedures procedureInfo
    ON procedureInfo.schema_id=schemaInfo.schema_id AND procedureInfo.name=expected.ProcedureName
ORDER BY expected.SchemaName,expected.ProcedureName;
GO
