:on error exit
:setvar KLOP_ENVIRONMENT "Development"
:setvar KLOP_EXPECTED_DATABASE "KlopPlatformDB"

-- Read-only Development catalog and readiness report. No rows or permissions are changed.
SET NOCOUNT ON;
DECLARE @Environment nvarchar(30)=N'$(KLOP_ENVIRONMENT)';
DECLARE @ExpectedDatabase sysname=N'$(KLOP_EXPECTED_DATABASE)';
IF @Environment<>N'Development' OR @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
	THROW 52720,'Validation is restricted to Development DEV-PC\SQLEXPRESS.',1;
IF @ExpectedDatabase<>N'KlopPlatformDB' OR DB_NAME()<>@ExpectedDatabase
	THROW 52721,'Validation is restricted to KlopPlatformDB.',1;

SELECT N'INSPECTING_SESSION_NOT_API_PROOF' AS Section,
	@@SERVERNAME AS ServerName,DB_NAME() AS DatabaseName,
	ORIGINAL_LOGIN() AS OriginalLogin,SUSER_SNAME() AS EffectiveLogin,
	USER_NAME() AS DatabaseUser,APP_NAME() AS ApplicationName,
	N'Use the separate runtime validator/DMV evidence to verify the API process identity.' AS Interpretation;

SELECT N'LEGAL_OBJECT_INVENTORY' AS Section,s.name AS SchemaName,o.name AS ObjectName,
	o.type_desc AS ObjectType,o.create_date,o.modify_date
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id=o.schema_id
WHERE s.name=N'leg'
  AND (o.name IN(N'LegalDocuments',N'LegalDocumentVersions',N'LegalDocumentVersionScopes',N'UserLegalConsents',
				 N'usp_GetCurrentTerms',N'usp_GetPublicTermsFile') OR o.name LIKE N'trg_%')
ORDER BY o.type_desc,o.name;

SELECT N'REQUIRED_READ_PROCEDURE' AS Section,r.ProcedureName,
	CASE WHEN OBJECT_ID(N'leg.'+QUOTENAME(r.ProcedureName),N'P') IS NULL THEN N'MISSING' ELSE N'PRESENT' END AS CatalogState
FROM (VALUES(N'usp_GetCurrentTerms'),(N'usp_GetPublicTermsFile')) r(ProcedureName)
ORDER BY r.ProcedureName;

IF OBJECT_ID(N'leg.usp_GetCurrentTerms',N'P') IS NOT NULL
BEGIN
	SELECT N'GET_CURRENT_TERMS_RESULT_COLUMNS' AS Section,column_ordinal,name,system_type_name,is_nullable
	FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'leg.usp_GetCurrentTerms'),0)
	WHERE is_hidden=0 ORDER BY column_ordinal;
END;
IF OBJECT_ID(N'leg.usp_GetPublicTermsFile',N'P') IS NOT NULL
BEGIN
	SELECT N'GET_PUBLIC_TERMS_FILE_RESULT_COLUMNS' AS Section,column_ordinal,name,system_type_name,is_nullable
	FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'leg.usp_GetPublicTermsFile'),0)
	WHERE is_hidden=0 ORDER BY column_ordinal;
END;

SELECT N'LEGAL_PROCEDURE_DEPENDENCIES' AS Section,
	OBJECT_SCHEMA_NAME(d.referencing_id) AS ReferencingSchema,
	OBJECT_NAME(d.referencing_id) AS ReferencingObject,
	d.referenced_schema_name,d.referenced_entity_name,d.is_ambiguous
FROM sys.sql_expression_dependencies d
WHERE d.referencing_id IN(OBJECT_ID(N'leg.usp_GetCurrentTerms'),OBJECT_ID(N'leg.usp_GetPublicTermsFile'))
ORDER BY ReferencingObject,d.referenced_schema_name,d.referenced_entity_name;

SELECT N'PUBLIC_TERMS_DATA_READINESS' AS Section,ty.Code AS RegistrationTypeCode,
	COUNT_BIG(d.LegalDocumentId) AS PublishedEffectiveScopedTermsCount
FROM mst.TenantTypes ty
LEFT JOIN leg.LegalDocumentVersionScopes scope ON scope.TenantTypeId=ty.TenantTypeId
LEFT JOIN leg.LegalDocumentVersions v ON v.DocumentVersionId=scope.DocumentVersionId
	AND v.PublicationStatus=N'PUBLISHED' AND v.EffectiveAtUtc<=SYSUTCDATETIME()
LEFT JOIN leg.LegalDocuments d ON d.LegalDocumentId=v.LegalDocumentId
	AND d.DocumentTypeCode=N'TERMS_AND_CONDITIONS'
WHERE ty.IsActive=1
GROUP BY ty.Code
ORDER BY ty.Code;

SELECT N'LEGAL_CONFIGURATION_READINESS' AS Section,
	CASE WHEN EXISTS
	(
		SELECT 1 FROM cfg.SystemConfigurations
		WHERE ConfigurationKey=N'legal.maximum_upload_bytes' AND IsActive=1
		  AND ValueType=N'INTEGER' AND StorageType=N'PLAIN'
		  AND TRY_CONVERT(bigint,ConfigurationValue) BETWEEN 1 AND 52428800
	) THEN N'PASS' ELSE N'BLOCKED' END AS MaximumPdfBytesSettingStatus,
	CASE WHEN EXISTS
	(
		SELECT 1 FROM cfg.SystemConfigurations
		WHERE ConfigurationKey=N'registration.legal_consent_enforcement'
		  AND IsActive=1 AND ValueType=N'BOOLEAN' AND StorageType=N'PLAIN'
		  AND TRY_CONVERT(bit,ConfigurationValue)=0
	) THEN N'OFF' ELSE N'REVIEW_REQUIRED' END AS ConsentEnforcementStatus,
	N'LegalDocuments:StorageRoot is application configuration and is not read from SQL; verify it separately without exposing its value.' AS StorageRootStatus;
GO
