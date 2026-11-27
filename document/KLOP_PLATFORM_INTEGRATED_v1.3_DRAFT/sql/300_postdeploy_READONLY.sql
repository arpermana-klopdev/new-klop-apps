-- Read-only report. 9 additional procedures should be present.
SELECT v.ProcName,CASE WHEN OBJECT_ID(v.ProcName,N'P') IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS Status
 FROM (VALUES ('iam.usp_GetLocalLoginCandidate'),('iam.usp_RecordLocalLoginFailure'),
 ('iam.usp_IssueEmailVerificationChallenge'),('iam.usp_CreateAuthSession'),
 ('iam.usp_ValidateSessionAccess'),('iam.usp_RotateRefreshToken'),
 ('iam.usp_RevokeAuthSession'),('iam.usp_GetUserProfile'),('ten.usp_ListMyTenants')) v(ProcName);
SELECT p.name, p.type_desc FROM sys.database_principals p WHERE p.name=N'klop_app_runtime';
