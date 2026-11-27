/*
DEV ONLY - ROLLBACK TEMPLATE, do not run automatically.
Confirm no active app nodes depend on v1.2.1 procedures. Take/verify a DB snapshot first.
This does NOT reverse business data already committed by these SPs. Investigate or reconcile
committed state separately. No v1.1/v1.2 tables/masters are touched.
*/
IF OBJECT_ID(N'iam.usp_RevokeTenantRole', N'P') IS NOT NULL DROP PROCEDURE iam.usp_RevokeTenantRole;
IF OBJECT_ID(N'iam.usp_AssignTenantRole', N'P') IS NOT NULL DROP PROCEDURE iam.usp_AssignTenantRole;
IF OBJECT_ID(N'ten.usp_RemoveTenantMember', N'P') IS NOT NULL DROP PROCEDURE ten.usp_RemoveTenantMember;
IF OBJECT_ID(N'ten.usp_AcceptMembership', N'P') IS NOT NULL DROP PROCEDURE ten.usp_AcceptMembership;
IF OBJECT_ID(N'ten.usp_InviteExistingUser', N'P') IS NOT NULL DROP PROCEDURE ten.usp_InviteExistingUser;
IF OBJECT_ID(N'ten.usp_CreateTenantWithOwner', N'P') IS NOT NULL DROP PROCEDURE ten.usp_CreateTenantWithOwner;
IF OBJECT_ID(N'iam.usp_ConfirmEmail', N'P') IS NOT NULL DROP PROCEDURE iam.usp_ConfirmEmail;
IF OBJECT_ID(N'iam.usp_RegisterLocalUser', N'P') IS NOT NULL DROP PROCEDURE iam.usp_RegisterLocalUser;
GO
-- Runtime role grants attached to dropped objects are removed; only remove role membership
-- following separate DBA review. Do not DROP ROLE if shared by other modules.
