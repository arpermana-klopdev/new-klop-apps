SET NOCOUNT ON;
GO
IF OBJECT_ID(N'cfg.SystemConfigurations', N'U') IS NULL
BEGIN
    CREATE TABLE cfg.SystemConfigurations (
    [ConfigurationId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [ConfigurationKey] VARCHAR(150) NOT NULL,
    [ConfigurationValue] NVARCHAR(MAX) NULL,
    [ValueType] VARCHAR(20) NOT NULL,
    [Category] VARCHAR(80) NOT NULL,
    [StorageType] VARCHAR(30) NOT NULL DEFAULT ('PLAIN'),
    [Description] NVARCHAR(500) NULL,
    [DefaultValue] NVARCHAR(MAX) NULL,
    [MinNumericValue] DECIMAL(18,4) NULL,
    [MaxNumericValue] DECIMAL(18,4) NULL,
    [AllowedValuesJson] NVARCHAR(MAX) NULL,
    [ValidationPattern] NVARCHAR(300) NULL,
    [RequiresApproval] BIT NOT NULL DEFAULT (0),
    [VersionNumber] INT NOT NULL DEFAULT (1),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (0),
    [IsEditable] BIT NOT NULL DEFAULT (1),
    [IsSensitive] BIT NOT NULL DEFAULT (0),
    [RequiresRestart] BIT NOT NULL DEFAULT (0),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO
