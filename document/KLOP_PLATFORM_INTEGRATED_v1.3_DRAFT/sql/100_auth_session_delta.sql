-- KLOP PLATFORM v1.3 DRAFT. ADDITIVE DELTA to DB v1.1 + v1.2 + v1.2.1.
-- Do NOT run in Production without code review and Development tests.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE iam.usp_GetLocalLoginCandidate @NormalizedEmail NVARCHAR(320)
AS
BEGIN
 SET NOCOUNT ON;
 SELECT u.UserId, u.DisplayName, c.PasswordHash, u.IsActive, u.EmailVerifiedAtUtc,
        c.LockoutUntilUtc
 FROM iam.Users u JOIN iam.UserCredentials c ON c.UserId=u.UserId
 WHERE u.NormalizedEmail=UPPER(LTRIM(RTRIM(@NormalizedEmail)));
END;
GO
CREATE OR ALTER PROCEDURE iam.usp_RecordLocalLoginFailure
 @UserId BIGINT, @CorrelationId UNIQUEIDENTIFIER=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @@TRANCOUNT<>0 THROW 52301,'Procedure requires independent transaction',1;
 DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(), @Count INT, @TypeId BIGINT,
  @MaxAttempts INT, @LockoutMinutes INT, @CurrentlyLocked BIT;
 BEGIN TRY
  BEGIN TRAN;
  SELECT @Count=CASE WHEN LockoutUntilUtc IS NOT NULL AND LockoutUntilUtc<=@Now THEN 0 ELSE FailedLoginCount END,
          @CurrentlyLocked=CASE WHEN LockoutUntilUtc>@Now THEN 1 ELSE 0 END
   FROM iam.UserCredentials WITH(UPDLOCK,HOLDLOCK) WHERE UserId=@UserId;
  SELECT @MaxAttempts=TRY_CONVERT(INT,ConfigurationValue) FROM cfg.SystemConfigurations WHERE ConfigurationKey='security.max_login_attempts' AND IsActive=1;
  SELECT @LockoutMinutes=TRY_CONVERT(INT,ConfigurationValue) FROM cfg.SystemConfigurations WHERE ConfigurationKey='security.login_lockout_minutes' AND IsActive=1;
  IF @MaxAttempts NOT BETWEEN 3 AND 10 OR @LockoutMinutes NOT BETWEEN 5 AND 120
    THROW 52304,'Required security configuration unavailable',1;
  IF @Count IS NULL THROW 52302,'Account unavailable',1;
  SELECT @TypeId=SecurityEventTypeId FROM mst.SecurityEventTypes WHERE Code='LOGIN_FAILED' AND IsActive=1;
  IF @TypeId IS NULL THROW 52303,'Missing security event master',1;
  IF @CurrentlyLocked=0
    UPDATE iam.UserCredentials SET FailedLoginCount=@Count+1,
      LockoutUntilUtc=CASE WHEN @Count+1>=@MaxAttempts THEN DATEADD(MINUTE,@LockoutMinutes,@Now) ELSE NULL END,
      UpdatedAtUtc=@Now WHERE UserId=@UserId;
  INSERT aud.SecurityEvents (ActorUserId,SubjectUserId,SecurityEventTypeId,SeverityCode,CorrelationId)
   VALUES (@UserId,@UserId,@TypeId,'WARNING',@CorrelationId);
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE iam.usp_IssueEmailVerificationChallenge
 @Email NVARCHAR(320), @TokenHash BINARY(32), @ExpiresAtUtc DATETIME2(3),
 @RequestId VARCHAR(100)=NULL, @CorrelationId UNIQUEIDENTIFIER=NULL,
 @UserId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @@TRANCOUNT<>0 THROW 52310,'Procedure requires independent transaction',1;
 DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(), @Purpose BIGINT, @Action BIGINT, @Success BIGINT;
 SET @UserId=NULL;
 IF @TokenHash IS NULL OR @ExpiresAtUtc<=@Now OR @ExpiresAtUtc>DATEADD(HOUR,24,@Now)
  THROW 52311,'Invalid challenge',1;
 BEGIN TRY
  BEGIN TRAN;
  SELECT @UserId=UserId FROM iam.Users WITH(UPDLOCK,HOLDLOCK)
   WHERE NormalizedEmail=UPPER(LTRIM(RTRIM(@Email))) AND IsActive=1 AND EmailVerifiedAtUtc IS NULL;
  IF @UserId IS NOT NULL
  BEGIN
   SELECT @Purpose=VerificationPurposeId FROM mst.VerificationPurposes WHERE Code='EMAIL_CONFIRMATION' AND IsActive=1;
   SELECT @Action=AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1;
   SELECT @Success=AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
   IF @Purpose IS NULL OR @Action IS NULL OR @Success IS NULL THROW 52312,'Missing master',1;
   UPDATE iam.VerificationChallenges SET InvalidatedAtUtc=@Now
    WHERE UserId=@UserId AND VerificationPurposeId=@Purpose AND ConsumedAtUtc IS NULL AND InvalidatedAtUtc IS NULL;
   INSERT iam.VerificationChallenges(UserId,VerificationPurposeId,TokenHash,ExpiresAtUtc)
    VALUES(@UserId,@Purpose,@TokenHash,@ExpiresAtUtc);
   INSERT aud.AuditEvents(ActorService,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,RequestId,CorrelationId)
    VALUES(N'KLOP.PLATFORM.EMAIL',@Action,@Success,'USER',CONVERT(NVARCHAR(150),@UserId),@RequestId,@CorrelationId);
  END
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE iam.usp_CreateAuthSession
 @UserId BIGINT, @SessionExpiresAtUtc DATETIME2(3), @RefreshTokenHash BINARY(32),
 @RefreshExpiresAtUtc DATETIME2(3), @RequestId VARCHAR(100)=NULL,
 @CorrelationId UNIQUEIDENTIFIER=NULL,
 @PublicSessionId UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @@TRANCOUNT<>0 THROW 52320,'Procedure requires independent transaction',1;
 DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(), @SessionId BIGINT, @SecurityType BIGINT, @AuditAction BIGINT, @AuditSuccess BIGINT;
 SET @PublicSessionId=NULL;
 IF @SessionExpiresAtUtc<=@Now OR @SessionExpiresAtUtc>DATEADD(DAY,30,@Now)
    OR @RefreshExpiresAtUtc<=@Now OR @RefreshExpiresAtUtc>@SessionExpiresAtUtc OR @RefreshTokenHash IS NULL
  THROW 52321,'Invalid session expiry',1;
 BEGIN TRY
  BEGIN TRAN;
  IF NOT EXISTS(SELECT 1 FROM iam.Users WITH(UPDLOCK,HOLDLOCK) WHERE UserId=@UserId AND IsActive=1 AND EmailVerifiedAtUtc IS NOT NULL)
   THROW 52322,'User inactive or unverified',1;
  IF NOT EXISTS(SELECT 1 FROM iam.UserCredentials WITH(UPDLOCK,HOLDLOCK) WHERE UserId=@UserId AND (LockoutUntilUtc IS NULL OR LockoutUntilUtc<=@Now))
   THROW 52323,'User account locked',1;
  SELECT @SecurityType=SecurityEventTypeId FROM mst.SecurityEventTypes WHERE Code='LOGIN_SUCCESS' AND IsActive=1;
  SELECT @AuditAction=AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='CREATE' AND IsActive=1;
  SELECT @AuditSuccess=AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
  IF @SecurityType IS NULL OR @AuditAction IS NULL OR @AuditSuccess IS NULL THROW 52324,'Missing master',1;
  INSERT iam.AuthSessions(UserId,TenantId,ExpiresAtUtc) VALUES(@UserId,NULL,@SessionExpiresAtUtc);
  SET @SessionId=CONVERT(BIGINT,SCOPE_IDENTITY());
  SELECT @PublicSessionId=PublicSessionId FROM iam.AuthSessions WHERE AuthSessionId=@SessionId;
  INSERT iam.RefreshTokens(AuthSessionId,TokenHash,TokenFamilyId,ExpiresAtUtc)
   VALUES(@SessionId,@RefreshTokenHash,NEWID(),@RefreshExpiresAtUtc);
  UPDATE iam.UserCredentials SET FailedLoginCount=0,LockoutUntilUtc=NULL,UpdatedAtUtc=@Now WHERE UserId=@UserId;
  INSERT aud.SecurityEvents(ActorUserId,SubjectUserId,SecurityEventTypeId,SeverityCode,CorrelationId)
   VALUES(@UserId,@UserId,@SecurityType,'INFO',@CorrelationId);
  INSERT aud.AuditEvents(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,RequestId,CorrelationId)
   VALUES(@UserId,@AuditAction,@AuditSuccess,'SESSION',CONVERT(NVARCHAR(150),@SessionId),@RequestId,@CorrelationId);
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE iam.usp_ValidateSessionAccess
 @UserId BIGINT, @PublicSessionId UNIQUEIDENTIFIER,
 @TenantId BIGINT=NULL, @PermissionCode VARCHAR(120)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @Now DATETIME2(3)=SYSUTCDATETIME();
 IF NOT EXISTS (
  SELECT 1 FROM iam.AuthSessions s JOIN iam.Users u ON u.UserId=s.UserId
  WHERE s.PublicSessionId=@PublicSessionId AND s.UserId=@UserId AND s.RevokedAtUtc IS NULL
    AND s.ExpiresAtUtc>@Now AND u.IsActive=1 AND u.EmailVerifiedAtUtc IS NOT NULL)
  THROW 52330,'Session inactive',1;
 IF @TenantId IS NOT NULL
 BEGIN
  IF NOT EXISTS (
   SELECT 1 FROM ten.TenantMemberships m
   JOIN mst.MembershipStatuses ms ON ms.MembershipStatusId=m.MembershipStatusId AND ms.Code='ACTIVE'
   JOIN ten.Tenants t ON t.TenantId=m.TenantId
   JOIN mst.TenantStatuses ts ON ts.TenantStatusId=t.TenantStatusId AND ts.Code IN('ACTIVE','PENDING')
   WHERE m.UserId=@UserId AND m.TenantId=@TenantId)
    THROW 52331,'Tenant membership inactive',1;
  IF @PermissionCode IS NOT NULL AND NOT EXISTS (
   SELECT 1 FROM ten.TenantMemberships m
   JOIN iam.TenantRoleAssignments a ON a.MembershipId=m.MembershipId
   JOIN mst.Roles r ON r.RoleId=a.RoleId AND r.IsActive=1
   JOIN mst.RoleScopes rs ON rs.RoleScopeId=r.RoleScopeId AND rs.Code='TENANT'
   JOIN mst.RolePermissions rp ON rp.RoleId=r.RoleId
   JOIN mst.Permissions p ON p.PermissionId=rp.PermissionId AND p.IsActive=1 AND p.Code=@PermissionCode
   JOIN mst.MembershipStatuses ms ON ms.MembershipStatusId=m.MembershipStatusId AND ms.Code='ACTIVE'
   WHERE m.UserId=@UserId AND m.TenantId=@TenantId)
    THROW 52332,'Permission denied',1;
 END
 ELSE IF @PermissionCode IS NOT NULL THROW 52333,'Tenant required for permission',1;
 SELECT CAST(1 AS BIT) AS IsAuthorized;
END;
GO
CREATE OR ALTER PROCEDURE iam.usp_RotateRefreshToken
 @PublicSessionId UNIQUEIDENTIFIER, @OldTokenHash BINARY(32), @NewTokenHash BINARY(32),
 @NewExpiresAtUtc DATETIME2(3), @CorrelationId UNIQUEIDENTIFIER=NULL,
 @UserId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @@TRANCOUNT<>0 THROW 52340,'Procedure requires independent transaction',1;
 DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(), @Sid BIGINT, @TokenId BIGINT,
         @Used DATETIME2(3), @Revoked DATETIME2(3), @Expiry DATETIME2(3), @Family UNIQUEIDENTIFIER,
         @PreviousExpiry DATETIME2(3), @SessionExpiry DATETIME2(3), @Replay BIT=0,
         @SecurityType BIGINT;
 SET @UserId=NULL;
 IF @OldTokenHash IS NULL OR @NewTokenHash IS NULL OR @OldTokenHash=@NewTokenHash THROW 52341,'Invalid refresh',1;
 BEGIN TRY
  BEGIN TRAN;
  SELECT @Sid=AuthSessionId,@UserId=UserId,@SessionExpiry=ExpiresAtUtc
   FROM iam.AuthSessions WITH(UPDLOCK,HOLDLOCK) WHERE PublicSessionId=@PublicSessionId AND RevokedAtUtc IS NULL AND ExpiresAtUtc>@Now;
  IF @Sid IS NULL THROW 52342,'Session unavailable',1;
  IF NOT EXISTS(SELECT 1 FROM iam.Users WHERE UserId=@UserId AND IsActive=1 AND EmailVerifiedAtUtc IS NOT NULL)
   THROW 52343,'User unavailable',1;
  SELECT @TokenId=RefreshTokenId,@Used=UsedAtUtc,@Revoked=RevokedAtUtc,@Expiry=ExpiresAtUtc,@Family=TokenFamilyId
   FROM iam.RefreshTokens WITH(UPDLOCK,HOLDLOCK)
   WHERE AuthSessionId=@Sid AND TokenHash=@OldTokenHash;
  IF @TokenId IS NULL THROW 52344,'Invalid refresh',1;
  IF @Used IS NOT NULL OR @Revoked IS NOT NULL
  BEGIN
   SET @Replay=1;
   SELECT @SecurityType=SecurityEventTypeId FROM mst.SecurityEventTypes WHERE Code='TOKEN_REVOKED' AND IsActive=1;
   IF @SecurityType IS NULL THROW 52345,'Missing security master',1;
   UPDATE iam.AuthSessions SET RevokedAtUtc=@Now,RevocationReason=N'REFRESH_REPLAY' WHERE AuthSessionId=@Sid;
   UPDATE iam.RefreshTokens SET RevokedAtUtc=@Now WHERE AuthSessionId=@Sid AND RevokedAtUtc IS NULL;
   INSERT aud.SecurityEvents(ActorUserId,SubjectUserId,SecurityEventTypeId,SeverityCode,CorrelationId)
    VALUES(@UserId,@UserId,@SecurityType,'CRITICAL',@CorrelationId);
  END
  ELSE
  BEGIN
   IF @NewExpiresAtUtc>@SessionExpiry SET @NewExpiresAtUtc=@SessionExpiry;
   IF @Expiry<=@Now OR @NewExpiresAtUtc<=@Now
      THROW 52346,'Refresh expired',1;
   UPDATE iam.RefreshTokens SET UsedAtUtc=@Now WHERE RefreshTokenId=@TokenId;
   INSERT iam.RefreshTokens(AuthSessionId,TokenHash,TokenFamilyId,PreviousTokenId,ExpiresAtUtc)
    VALUES(@Sid,@NewTokenHash,@Family,@TokenId,@NewExpiresAtUtc);
  END
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
 IF @Replay=1 THROW 52347,'Refresh replay detected; session revoked',1;
END;
GO
CREATE OR ALTER PROCEDURE iam.usp_RevokeAuthSession
 @UserId BIGINT, @PublicSessionId UNIQUEIDENTIFIER, @CorrelationId UNIQUEIDENTIFIER=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @@TRANCOUNT<>0 THROW 52350,'Procedure requires independent transaction',1;
 DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(),@Sid BIGINT,@Type BIGINT,@Action BIGINT,@Success BIGINT;
 BEGIN TRY
  BEGIN TRAN;
  SELECT @Sid=AuthSessionId FROM iam.AuthSessions WITH(UPDLOCK,HOLDLOCK)
   WHERE PublicSessionId=@PublicSessionId AND UserId=@UserId AND RevokedAtUtc IS NULL;
  IF @Sid IS NULL THROW 52351,'Session unavailable',1;
  SELECT @Type=SecurityEventTypeId FROM mst.SecurityEventTypes WHERE Code='TOKEN_REVOKED' AND IsActive=1;
  SELECT @Action=AuditActionTypeId FROM mst.AuditActionTypes WHERE Code='DEACTIVATE' AND IsActive=1;
  SELECT @Success=AuditResultTypeId FROM mst.AuditResultTypes WHERE Code='SUCCESS' AND IsActive=1;
  IF @Type IS NULL OR @Action IS NULL OR @Success IS NULL THROW 52352,'Missing master',1;
  UPDATE iam.AuthSessions SET RevokedAtUtc=@Now,RevocationReason=N'LOGOUT' WHERE AuthSessionId=@Sid;
  UPDATE iam.RefreshTokens SET RevokedAtUtc=@Now WHERE AuthSessionId=@Sid AND RevokedAtUtc IS NULL;
  INSERT aud.SecurityEvents(ActorUserId,SubjectUserId,SecurityEventTypeId,SeverityCode,CorrelationId)
   VALUES(@UserId,@UserId,@Type,'INFO',@CorrelationId);
  INSERT aud.AuditEvents(ActorUserId,AuditActionTypeId,AuditResultTypeId,TargetType,TargetId,CorrelationId)
   VALUES(@UserId,@Action,@Success,'SESSION',CONVERT(NVARCHAR(150),@Sid),@CorrelationId);
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
CREATE OR ALTER PROCEDURE iam.usp_GetUserProfile @UserId BIGINT
AS
BEGIN
 SET NOCOUNT ON;
 SELECT UserId,Email,DisplayName,EmailVerifiedAtUtc FROM iam.Users WHERE UserId=@UserId AND IsActive=1;
END;
GO
CREATE OR ALTER PROCEDURE ten.usp_ListMyTenants @UserId BIGINT
AS
BEGIN
 SET NOCOUNT ON;
 SELECT t.TenantId,t.TenantCode,t.DisplayName,ty.Code AS TenantTypeCode,ts.Code AS TenantStatusCode,
        m.MembershipId,ms.Code AS MembershipStatusCode
 FROM ten.TenantMemberships m JOIN ten.Tenants t ON t.TenantId=m.TenantId
 JOIN mst.TenantTypes ty ON ty.TenantTypeId=t.TenantTypeId
 JOIN mst.TenantStatuses ts ON ts.TenantStatusId=t.TenantStatusId
 JOIN mst.MembershipStatuses ms ON ms.MembershipStatusId=m.MembershipStatusId
 WHERE m.UserId=@UserId AND ms.Code='ACTIVE';
END;
GO
