:on error exit
:setvar KLOP_CLEANUP_APPROVED "NO"
:setvar KLOP_APPROVAL_TICKET "UNSET"

USE [master];
GO
SET NOCOUNT ON;
IF @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 52470,'Refused: cleanup is restricted to DEV-PC\SQLEXPRESS.',1;
IF DB_ID(N'KlopPlatformDB_TEST') IS NULL
BEGIN
    SELECT N'NO ACTION' AS Status,N'KlopPlatformDB_TEST does not exist.' AS Details;
    RETURN;
END;

DECLARE @CleanupApproved nvarchar(20)=N'$(KLOP_CLEANUP_APPROVED)';
DECLARE @ApprovalTicket nvarchar(200)=N'$(KLOP_APPROVAL_TICKET)';
IF @CleanupApproved<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
    SELECT N'NO CHANGES' AS Status,N'KlopPlatformDB_TEST exists and was not altered.' AS Details,
        N'Dropping the disposable test database permanently deletes all test fixtures.' AS RequiredApproval;
    RETURN;
END;
IF EXISTS
(
    SELECT 1 FROM sys.dm_exec_sessions
    WHERE database_id=DB_ID(N'KlopPlatformDB_TEST') AND session_id<>@@SPID
)
    THROW 52471,'Refused: stop API/test connections before cleanup; no sessions were terminated.',1;

EXEC(N'DROP DATABASE [KlopPlatformDB_TEST];');
SELECT N'DROPPED KlopPlatformDB_TEST' AS Status,
    N'The external Windows/Entra login, if any, was not dropped.' AS Details;
GO
