-- Security contract: API creates cryptographically random verification secret and a password KDF hash;
-- only their derived hashes enter SQL. The API owns rate limiting, authentication and email delivery.
-- These SPs own their transactions; do not call inside an API-managed SQL transaction.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE iam.usp_RegisterLocalUser
    @Email NVARCHAR(320),
    @DisplayName NVARCHAR(150),
    @PasswordHash NVARCHAR(1024),
    @VerificationTokenHash BINARY(32),
    @VerificationExpiresAtUtc DATETIME2(3),
    @RequestId VARCHAR(100) = NULL,
    @CorrelationId UNIQUEIDENTIFIER = NULL,
    @UserId BIGINT OUTPUT,
    @ChallengeId BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 THROW 52110, 'Procedure must own the transaction.', 1;

    DECLARE @CleanEmail NVARCHAR(320) = LTRIM(RTRIM(@Email));
    DECLARE @NormalizedEmail NVARCHAR(320) = UPPER(@CleanEmail);
    DECLARE @CleanName NVARCHAR(150) = LTRIM(RTRIM(@DisplayName));
    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @PurposeId BIGINT, @ActionId BIGINT, @ResultId BIGINT, @Json NVARCHAR(MAX);
    SET @UserId = NULL;
    SET @ChallengeId = NULL;

    IF @CleanEmail IS NULL OR @CleanEmail = N'' OR @CleanEmail NOT LIKE N'%_@_%._%'
       OR @CleanName IS NULL OR @CleanName = N''
       OR @PasswordHash IS NULL OR LEN(@PasswordHash) < 50
       OR @VerificationTokenHash IS NULL OR @VerificationExpiresAtUtc IS NULL OR @VerificationExpiresAtUtc <= @Now
       THROW 52111, 'Invalid registration parameters.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @PurposeId = VerificationPurposeId FROM mst.VerificationPurposes WHERE Code = 'EMAIL_CONFIRMATION' AND IsActive = 1;
        SELECT @ActionId = AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1;
        SELECT @ResultId = AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        IF @PurposeId IS NULL OR @ActionId IS NULL OR @ResultId IS NULL
           THROW 52112, 'Required masters are unavailable.', 1;
        IF EXISTS (SELECT 1 FROM iam.Users WITH (UPDLOCK, HOLDLOCK) WHERE NormalizedEmail = @NormalizedEmail)
           THROW 52113, 'Email is already registered.', 1;

        INSERT INTO iam.Users (Email, NormalizedEmail, DisplayName, IsActive)
        VALUES (@CleanEmail, @NormalizedEmail, @CleanName, 1);
        SET @UserId = CONVERT(BIGINT, SCOPE_IDENTITY());
        INSERT INTO iam.UserCredentials (UserId, PasswordHash)
        VALUES (@UserId, @PasswordHash);
        INSERT INTO iam.VerificationChallenges (UserId, VerificationPurposeId, TokenHash, ExpiresAtUtc)
        VALUES (@UserId, @PurposeId, @VerificationTokenHash, @VerificationExpiresAtUtc);
        SET @ChallengeId = CONVERT(BIGINT, SCOPE_IDENTITY());

        SELECT @Json = (SELECT @UserId AS UserId, 'EMAIL_PENDING' AS VerificationState
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        INSERT INTO aud.AuditEvents
             (ActorService, AuditActionTypeId, AuditResultTypeId, TargetType, TargetId,
              ChangeSummaryJson, RequestId, CorrelationId)
        VALUES (N'KLOP.PLATFORM.REGISTRATION', @ActionId, @ResultId, 'USER',
                CONVERT(NVARCHAR(150),@UserId), @Json, @RequestId, @CorrelationId);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE iam.usp_ConfirmEmail
    @UserId BIGINT,
    @VerificationTokenHash BINARY(32),
    @RequestId VARCHAR(100) = NULL,
    @CorrelationId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 THROW 52120, 'Procedure must own the transaction.', 1;
    IF @UserId IS NULL OR @VerificationTokenHash IS NULL
       THROW 52121, 'Invalid verification parameters.', 1;

    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ChallengeId BIGINT, @PurposeId BIGINT, @ActionId BIGINT, @ResultId BIGINT;
    DECLARE @Json NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @PurposeId = VerificationPurposeId FROM mst.VerificationPurposes WHERE Code='EMAIL_CONFIRMATION' AND IsActive=1;
        SELECT @ActionId = AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='UPDATE' AND IsActive=1;
        SELECT @ResultId = AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
        IF @PurposeId IS NULL OR @ActionId IS NULL OR @ResultId IS NULL
           THROW 52122, 'Required masters are unavailable.', 1;

        SELECT @ChallengeId = c.ChallengeId
          FROM iam.VerificationChallenges c WITH (UPDLOCK, HOLDLOCK)
         WHERE c.UserId = @UserId AND c.TokenHash = @VerificationTokenHash
           AND c.VerificationPurposeId = @PurposeId AND c.ConsumedAtUtc IS NULL
           AND c.InvalidatedAtUtc IS NULL AND c.ExpiresAtUtc > @Now;
        IF @ChallengeId IS NULL THROW 52123, 'Verification challenge invalid or expired.', 1;

        UPDATE iam.Users SET EmailVerifiedAtUtc = @Now, UpdatedAtUtc = @Now,
                             UpdatedByUserId = @UserId
         WHERE UserId = @UserId AND IsActive = 1 AND EmailVerifiedAtUtc IS NULL;
        IF @@ROWCOUNT <> 1 THROW 52124, 'User is not eligible for verification.', 1;
        UPDATE iam.VerificationChallenges SET ConsumedAtUtc = @Now WHERE ChallengeId = @ChallengeId;
        UPDATE iam.VerificationChallenges SET InvalidatedAtUtc = @Now
         WHERE UserId = @UserId AND VerificationPurposeId = @PurposeId
           AND ChallengeId <> @ChallengeId AND ConsumedAtUtc IS NULL AND InvalidatedAtUtc IS NULL;

        SELECT @Json = (SELECT @UserId AS UserId, 'EMAIL_VERIFIED' AS VerificationState
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        INSERT INTO aud.AuditEvents
             (ActorUserId, AuditActionTypeId, AuditResultTypeId, TargetType, TargetId,
              ChangeSummaryJson, RequestId, CorrelationId)
        VALUES (@UserId, @ActionId, @ResultId, 'USER', CONVERT(NVARCHAR(150),@UserId),
                @Json, @RequestId, @CorrelationId);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
