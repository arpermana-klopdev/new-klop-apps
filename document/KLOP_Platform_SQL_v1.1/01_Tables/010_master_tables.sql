SET NOCOUNT ON;
GO
IF OBJECT_ID(N'mst.TenantTypes', N'U') IS NULL
BEGIN
    CREATE TABLE mst.TenantTypes (
    [TenantTypeId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [Code] VARCHAR(50) NOT NULL,
    [AllowMultipleMembers] BIT NOT NULL DEFAULT (0),
    [Name] NVARCHAR(150) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [SortOrder] INT NOT NULL DEFAULT (0),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.TenantStatuses', N'U') IS NULL
BEGIN
    CREATE TABLE mst.TenantStatuses (
    [TenantStatusId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
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
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.OrganizationTypes', N'U') IS NULL
BEGIN
    CREATE TABLE mst.OrganizationTypes (
    [OrganizationTypeId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [CountryCode] CHAR(2) NOT NULL,
    [Code] VARCHAR(50) NOT NULL,
    [RequiresManualReview] BIT NOT NULL DEFAULT (0),
    [Name] NVARCHAR(150) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [SortOrder] INT NOT NULL DEFAULT (0),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.IdentityDocumentTypes', N'U') IS NULL
BEGIN
    CREATE TABLE mst.IdentityDocumentTypes (
    [IdentityDocumentTypeId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [CountryCode] CHAR(2) NOT NULL,
    [Code] VARCHAR(50) NOT NULL,
    [RequiresNumber] BIT NOT NULL DEFAULT (0),
    [AllowsFileUpload] BIT NOT NULL DEFAULT (1),
    [ValidationPattern] NVARCHAR(300) NULL,
    [Name] NVARCHAR(150) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [SortOrder] INT NOT NULL DEFAULT (0),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.OrganizationIdentityRequirementGroups', N'U') IS NULL
BEGIN
    CREATE TABLE mst.OrganizationIdentityRequirementGroups (
    [RequirementGroupId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [OrganizationTypeId] BIGINT NOT NULL,
    [Code] VARCHAR(50) NOT NULL,
    [SelectionMode] VARCHAR(20) NOT NULL,
    [MinimumRequired] INT NOT NULL DEFAULT (1),
    [EffectiveFromUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [EffectiveToUtc] DATETIME2(3) NULL,
    [Name] NVARCHAR(150) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [SortOrder] INT NOT NULL DEFAULT (0),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.OrganizationIdentityRequirements', N'U') IS NULL
BEGIN
    CREATE TABLE mst.OrganizationIdentityRequirements (
    [RequirementId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [RequirementGroupId] BIGINT NOT NULL,
    [IdentityDocumentTypeId] BIGINT NOT NULL,
    [RequirementLevel] VARCHAR(20) NOT NULL DEFAULT ('REQUIRED'),
    [EffectiveFromUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [EffectiveToUtc] DATETIME2(3) NULL,
    [IsActive] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.MembershipStatuses', N'U') IS NULL
BEGIN
    CREATE TABLE mst.MembershipStatuses (
    [MembershipStatusId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
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
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.RoleScopes', N'U') IS NULL
BEGIN
    CREATE TABLE mst.RoleScopes (
    [RoleScopeId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
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
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.Roles', N'U') IS NULL
BEGIN
    CREATE TABLE mst.Roles (
    [RoleId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [RoleScopeId] BIGINT NOT NULL,
    [Code] VARCHAR(50) NOT NULL,
    [IsAssignable] BIT NOT NULL DEFAULT (1),
    [Name] NVARCHAR(150) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [SortOrder] INT NOT NULL DEFAULT (0),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.Permissions', N'U') IS NULL
BEGIN
    CREATE TABLE mst.Permissions (
    [PermissionId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [RoleScopeId] BIGINT NOT NULL,
    [Code] VARCHAR(150) NOT NULL,
    [Name] NVARCHAR(150) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [SortOrder] INT NOT NULL DEFAULT (0),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.RolePermissions', N'U') IS NULL
BEGIN
    CREATE TABLE mst.RolePermissions (
    [RoleId] BIGINT NOT NULL,
    [PermissionId] BIGINT NOT NULL,
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.VerificationStatuses', N'U') IS NULL
BEGIN
    CREATE TABLE mst.VerificationStatuses (
    [VerificationStatusId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
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
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.AuditActionTypes', N'U') IS NULL
BEGIN
    CREATE TABLE mst.AuditActionTypes (
    [AuditActionTypeId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
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
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.SecurityEventTypes', N'U') IS NULL
BEGIN
    CREATE TABLE mst.SecurityEventTypes (
    [SecurityEventTypeId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [Code] VARCHAR(50) NOT NULL,
    [DefaultSeverity] VARCHAR(20) NOT NULL DEFAULT ('INFO'),
    [Name] NVARCHAR(150) NOT NULL,
    [Description] NVARCHAR(500) NULL,
    [SortOrder] INT NOT NULL DEFAULT (0),
    [IsActive] BIT NOT NULL DEFAULT (1),
    [IsSystem] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO

IF OBJECT_ID(N'mst.AuditResultTypes', N'U') IS NULL
BEGIN
    CREATE TABLE mst.AuditResultTypes (
    [AuditResultTypeId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
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
    [RowVersion] ROWVERSION NOT NULL
    );
END;
GO
