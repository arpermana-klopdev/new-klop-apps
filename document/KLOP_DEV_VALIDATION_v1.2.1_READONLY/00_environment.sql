-- KLOP DEVELOPMENT - READ-ONLY VALIDATION
-- Based on original v1.1, v1.2 and v1.2.1 artifacts.
-- READ-ONLY: no INSERT / UPDATE / DELETE / CREATE / ALTER / DROP on user objects, no stored procedure invocation.
-- Run via SSMS or sqlcmd, against the intended DEVELOPMENT database, with metadata/read privileges.
-- IMPORTANT: output is evidence only when executed and saved from the actual SQL Server.
SET NOCOUNT ON;
GO
SELECT
  DB_NAME() AS DatabaseName, @@SERVERNAME AS ServerName,
  SYSDATETIMEOFFSET() AS CapturedAt,
  CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(120)) AS ProductVersion,
  CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(120)) AS ProductLevel,
  d.compatibility_level AS CompatibilityLevel,
  d.is_read_committed_snapshot_on AS ReadCommittedSnapshotOn,
  d.recovery_model_desc AS RecoveryModel,
  d.state_desc AS DatabaseState
FROM sys.databases AS d WHERE d.database_id=DB_ID();
-- Confirm server/database environment independently before using these findings.
GO
