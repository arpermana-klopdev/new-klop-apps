SET NOCOUNT ON;

GO

IF OBJECT_ID(N'iam.Users', N'U') IS NULL
BEGIN
    CREATE TABLE iam.Users (
    [UserId] BIGINT IDENTITY(1,1) NOT NULL,
    [PublicUserId] UNIQUEIDENTIFIER NOT NULL DEFAULT (NEWSEQUENTIALID()),
    [Email] NVARCHAR(320) NOT NULL,
    [NormalizedEmail] NVARCHAR(320) NOT NULL,
    [DisplayName] NVARCHAR(150) NOT NULL,
    [EmailVerifiedAtUtc] DATETIME2(3) NULL,
    [IsActive] BIT NOT NULL DEFAULT (1),
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_iam_Users] PRIMARY KEY CLUSTERED ([UserId])
    );
END;

GO

IF OBJECT_ID(N'iam.UserCredentials', N'U') IS NULL
BEGIN
    CREATE TABLE iam.UserCredentials (
    [CredentialId] BIGINT IDENTITY(1,1) NOT NULL,
    [UserId] BIGINT NOT NULL,
    [PasswordHash] NVARCHAR(1024) NOT NULL,
    [PasswordChangedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [FailedLoginCount] INT NOT NULL DEFAULT (0),
    [LockoutUntilUtc] DATETIME2(3) NULL,
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_iam_UserCredentials] PRIMARY KEY CLUSTERED ([CredentialId])
    );
END;

GO

IF OBJECT_ID(N'iam.ExternalIdentities', N'U') IS NULL
BEGIN
    CREATE TABLE iam.ExternalIdentities (
    [ExternalIdentityId] BIGINT IDENTITY(1,1) NOT NULL,
    [UserId] BIGINT NOT NULL,
    [IdentityProviderId] BIGINT NOT NULL,
    [Issuer] NVARCHAR(250) NOT NULL,
    [Subject] NVARCHAR(250) NOT NULL,
    [LinkedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [LastLoginAtUtc] DATETIME2(3) NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_iam_ExternalIdentities] PRIMARY KEY CLUSTERED ([ExternalIdentityId])
    );
END;

GO

IF OBJECT_ID(N'iam.VerificationChallenges', N'U') IS NULL
BEGIN
    CREATE TABLE iam.VerificationChallenges (
    [ChallengeId] BIGINT IDENTITY(1,1) NOT NULL,
    [UserId] BIGINT NOT NULL,
    [VerificationPurposeId] BIGINT NOT NULL,
    [TokenHash] BINARY(32) NOT NULL,
    [ExpiresAtUtc] DATETIME2(3) NOT NULL,
    [ConsumedAtUtc] DATETIME2(3) NULL,
    [InvalidatedAtUtc] DATETIME2(3) NULL,
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_iam_VerificationChallenges] PRIMARY KEY CLUSTERED ([ChallengeId])
    );
END;

GO

IF OBJECT_ID(N'ten.Tenants', N'U') IS NULL
BEGIN
    CREATE TABLE ten.Tenants (
    [TenantId] BIGINT IDENTITY(1,1) NOT NULL,
    [PublicTenantId] UNIQUEIDENTIFIER NOT NULL DEFAULT (NEWSEQUENTIALID()),
    [TenantCode] VARCHAR(50) NOT NULL,
    [TenantTypeId] BIGINT NOT NULL,
    [TenantStatusId] BIGINT NOT NULL,
    [DisplayName] NVARCHAR(200) NOT NULL,
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_ten_Tenants] PRIMARY KEY CLUSTERED ([TenantId])
    );
END;

GO

IF OBJECT_ID(N'ten.Organizations', N'U') IS NULL
BEGIN
    CREATE TABLE ten.Organizations (
    [TenantId] BIGINT NOT NULL,
    [OrganizationTypeId] BIGINT NOT NULL,
    [RegisteredName] NVARCHAR(250) NOT NULL,
    [VerificationStatusId] BIGINT NOT NULL,
    [VerifiedAtUtc] DATETIME2(3) NULL,
    [VerifiedByUserId] BIGINT NULL,
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_ten_Organizations] PRIMARY KEY CLUSTERED ([TenantId])
    );
END;

GO

IF OBJECT_ID(N'ten.TenantMemberships', N'U') IS NULL
BEGIN
    CREATE TABLE ten.TenantMemberships (
    [MembershipId] BIGINT IDENTITY(1,1) NOT NULL,
    [TenantId] BIGINT NOT NULL,
    [UserId] BIGINT NOT NULL,
    [MembershipStatusId] BIGINT NOT NULL,
    [JoinedAtUtc] DATETIME2(3) NULL,
    [LeftAtUtc] DATETIME2(3) NULL,
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [CreatedByUserId] BIGINT NULL,
    [UpdatedAtUtc] DATETIME2(3) NULL,
    [UpdatedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_ten_TenantMemberships] PRIMARY KEY CLUSTERED ([MembershipId])
    );
END;

GO

IF OBJECT_ID(N'iam.PlatformRoleAssignments', N'U') IS NULL
BEGIN
    CREATE TABLE iam.PlatformRoleAssignments (
    [PlatformRoleAssignmentId] BIGINT IDENTITY(1,1) NOT NULL,
    [UserId] BIGINT NOT NULL,
    [RoleId] BIGINT NOT NULL,
    [AssignedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [AssignedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_iam_PlatformRoleAssignments] PRIMARY KEY CLUSTERED ([PlatformRoleAssignmentId])
    );
END;

GO

IF OBJECT_ID(N'iam.TenantRoleAssignments', N'U') IS NULL
BEGIN
    CREATE TABLE iam.TenantRoleAssignments (
    [TenantRoleAssignmentId] BIGINT IDENTITY(1,1) NOT NULL,
    [MembershipId] BIGINT NOT NULL,
    [RoleId] BIGINT NOT NULL,
    [AssignedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [AssignedByUserId] BIGINT NULL,
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_iam_TenantRoleAssignments] PRIMARY KEY CLUSTERED ([TenantRoleAssignmentId])
    );
END;

GO

IF OBJECT_ID(N'iam.AuthSessions', N'U') IS NULL
BEGIN
    CREATE TABLE iam.AuthSessions (
    [AuthSessionId] BIGINT IDENTITY(1,1) NOT NULL,
    [PublicSessionId] UNIQUEIDENTIFIER NOT NULL DEFAULT (NEWSEQUENTIALID()),
    [UserId] BIGINT NOT NULL,
    [TenantId] BIGINT NULL,
    [ExpiresAtUtc] DATETIME2(3) NOT NULL,
    [LastSeenAtUtc] DATETIME2(3) NULL,
    [RevokedAtUtc] DATETIME2(3) NULL,
    [RevocationReason] NVARCHAR(250) NULL,
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_iam_AuthSessions] PRIMARY KEY CLUSTERED ([AuthSessionId])
    );
END;

GO

IF OBJECT_ID(N'iam.RefreshTokens', N'U') IS NULL
BEGIN
    CREATE TABLE iam.RefreshTokens (
    [RefreshTokenId] BIGINT IDENTITY(1,1) NOT NULL,
    [AuthSessionId] BIGINT NOT NULL,
    [TokenHash] BINARY(32) NOT NULL,
    [TokenFamilyId] UNIQUEIDENTIFIER NOT NULL,
    [PreviousTokenId] BIGINT NULL,
    [ExpiresAtUtc] DATETIME2(3) NOT NULL,
    [UsedAtUtc] DATETIME2(3) NULL,
    [RevokedAtUtc] DATETIME2(3) NULL,
    [CreatedAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    [RowVersion] ROWVERSION NOT NULL,
    CONSTRAINT [PK_iam_RefreshTokens] PRIMARY KEY CLUSTERED ([RefreshTokenId])
    );
END;

GO
