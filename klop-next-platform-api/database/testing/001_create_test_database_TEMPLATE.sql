:on error exit
:setvar KLOP_CREATE_DATABASE "NO"
:setvar KLOP_APPROVAL_TICKET "UNSET"

USE [master];
GO
SET NOCOUNT ON;

IF @@SERVERNAME<>N'DEV-PC\SQLEXPRESS'
    THROW 52440,'Refused: this template is restricted to DEV-PC\SQLEXPRESS.',1;
IF DB_ID(N'KlopPlatformDB_TEST') IS NOT NULL
    THROW 52441,'Refused: KlopPlatformDB_TEST already exists; inspect it, do not overwrite it.',1;

DECLARE @CreateDatabase nvarchar(20)=N'$(KLOP_CREATE_DATABASE)';
DECLARE @ApprovalTicket nvarchar(200)=N'$(KLOP_APPROVAL_TICKET)';
IF @CreateDatabase<>N'APPROVED' OR @ApprovalTicket IN(N'',N'UNSET')
BEGIN
    SELECT N'NO CHANGES' AS Status,N'KlopPlatformDB_TEST does not exist.' AS ObservedState,
        N'Creation requires explicit DBA/security approval and an approved ticket.' AS RequiredAction;
    RETURN;
END;

EXEC(N'CREATE DATABASE [KlopPlatformDB_TEST];');
SELECT N'CREATED EMPTY DATABASE ONLY' AS Status,
    N'No schema, data, login, role, or permission was created.' AS Scope;
GO
