SET NOCOUNT ON;

GO

IF OBJECT_ID(N'aud.AuditEvents', N'U') IS NULL
BEGIN
    CREATE TABLE aud.AuditEvents (
    [AuditEventId] BIGINT IDENTITY(1,1) NOT NULL,
    [TenantId] BIGINT NULL,
    [ActorUserId] BIGINT NULL,
    [ActorService] NVARCHAR(150) NULL,
    [AuditActionTypeId] BIGINT NOT NULL,
    [AuditResultTypeId] BIGINT NOT NULL,
    [TargetType] VARCHAR(100) NOT NULL,
    [TargetId] NVARCHAR(150) NULL,
    [ChangeSummaryJson] NVARCHAR(MAX) NULL,
    [RequestId] VARCHAR(100) NULL,
    [CorrelationId] UNIQUEIDENTIFIER NULL,
    [OccurredAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_aud_AuditEvents] PRIMARY KEY CLUSTERED ([AuditEventId])
    );
END;

GO

IF OBJECT_ID(N'aud.SecurityEvents', N'U') IS NULL
BEGIN
    CREATE TABLE aud.SecurityEvents (
    [SecurityEventId] BIGINT IDENTITY(1,1) NOT NULL,
    [TenantId] BIGINT NULL,
    [ActorUserId] BIGINT NULL,
    [SubjectUserId] BIGINT NULL,
    [SecurityEventTypeId] BIGINT NOT NULL,
    [SeverityCode] VARCHAR(20) NOT NULL,
    [MetadataJson] NVARCHAR(MAX) NULL,
    [CorrelationId] UNIQUEIDENTIFIER NULL,
    [OccurredAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_aud_SecurityEvents] PRIMARY KEY CLUSTERED ([SecurityEventId])
    );
END;

GO

IF OBJECT_ID(N'aud.BusinessEvents', N'U') IS NULL
BEGIN
    CREATE TABLE aud.BusinessEvents (
    [BusinessEventId] BIGINT IDENTITY(1,1) NOT NULL,
    [TenantId] BIGINT NOT NULL,
    [ActorUserId] BIGINT NULL,
    [BusinessEventTypeId] BIGINT NOT NULL,
    [TargetType] VARCHAR(100) NOT NULL,
    [TargetId] NVARCHAR(150) NULL,
    [EventDataJson] NVARCHAR(MAX) NULL,
    [CorrelationId] UNIQUEIDENTIFIER NULL,
    [OccurredAtUtc] DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_aud_BusinessEvents] PRIMARY KEY CLUSTERED ([BusinessEventId])
    );
END;

GO
