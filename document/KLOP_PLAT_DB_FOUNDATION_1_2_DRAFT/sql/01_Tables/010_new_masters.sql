SET NOCOUNT ON;

GO

IF OBJECT_ID(N'mst.IdentityProviders', N'U') IS NULL
BEGIN
    CREATE TABLE mst.IdentityProviders (
    [IdentityProviderId] BIGINT IDENTITY(1,1) NOT NULL,
    [Code] VARCHAR(50) NOT NULL,
    [Name] NVARCHAR(150) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [SortOrder] INT NOT NULL DEFAULT (0),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_mst_IdentityProviders] PRIMARY KEY CLUSTERED ([IdentityProviderId])
    );
END;

GO

IF OBJECT_ID(N'mst.VerificationPurposes', N'U') IS NULL
BEGIN
    CREATE TABLE mst.VerificationPurposes (
    [VerificationPurposeId] BIGINT IDENTITY(1,1) NOT NULL,
    [Code] VARCHAR(50) NOT NULL,
    [Name] NVARCHAR(150) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [SortOrder] INT NOT NULL DEFAULT (0),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_mst_VerificationPurposes] PRIMARY KEY CLUSTERED ([VerificationPurposeId])
    );
END;

GO

IF OBJECT_ID(N'mst.BusinessEventTypes', N'U') IS NULL
BEGIN
    CREATE TABLE mst.BusinessEventTypes (
    [BusinessEventTypeId] BIGINT IDENTITY(1,1) NOT NULL,
    [Code] VARCHAR(50) NOT NULL,
    [Name] NVARCHAR(150) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [SortOrder] INT NOT NULL DEFAULT (0),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_mst_BusinessEventTypes] PRIMARY KEY CLUSTERED ([BusinessEventTypeId])
    );
END;

GO
