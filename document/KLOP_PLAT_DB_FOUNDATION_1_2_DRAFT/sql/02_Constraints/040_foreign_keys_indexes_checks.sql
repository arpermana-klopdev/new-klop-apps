SET NOCOUNT ON;
GO
-- FK definitions are additive. No v1.1 DDL is modified.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.UserCredentials') AND name=N'FK_iam_UserCredentials_UserId')
    ALTER TABLE iam.UserCredentials WITH CHECK ADD CONSTRAINT [FK_iam_UserCredentials_UserId] FOREIGN KEY ([UserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.ExternalIdentities') AND name=N'FK_iam_ExternalIdentities_UserId')
    ALTER TABLE iam.ExternalIdentities WITH CHECK ADD CONSTRAINT [FK_iam_ExternalIdentities_UserId] FOREIGN KEY ([UserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.ExternalIdentities') AND name=N'FK_iam_ExternalIdentities_IdentityProviderId')
    ALTER TABLE iam.ExternalIdentities WITH CHECK ADD CONSTRAINT [FK_iam_ExternalIdentities_IdentityProviderId] FOREIGN KEY ([IdentityProviderId]) REFERENCES mst.IdentityProviders ([IdentityProviderId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.VerificationChallenges') AND name=N'FK_iam_VerificationChallenges_UserId')
    ALTER TABLE iam.VerificationChallenges WITH CHECK ADD CONSTRAINT [FK_iam_VerificationChallenges_UserId] FOREIGN KEY ([UserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.VerificationChallenges') AND name=N'FK_iam_VerificationChallenges_VerificationPurposeId')
    ALTER TABLE iam.VerificationChallenges WITH CHECK ADD CONSTRAINT [FK_iam_VerificationChallenges_VerificationPurposeId] FOREIGN KEY ([VerificationPurposeId]) REFERENCES mst.VerificationPurposes ([VerificationPurposeId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.Tenants') AND name=N'FK_ten_Tenants_TenantTypeId')
    ALTER TABLE ten.Tenants WITH CHECK ADD CONSTRAINT [FK_ten_Tenants_TenantTypeId] FOREIGN KEY ([TenantTypeId]) REFERENCES mst.TenantTypes ([TenantTypeId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.Tenants') AND name=N'FK_ten_Tenants_TenantStatusId')
    ALTER TABLE ten.Tenants WITH CHECK ADD CONSTRAINT [FK_ten_Tenants_TenantStatusId] FOREIGN KEY ([TenantStatusId]) REFERENCES mst.TenantStatuses ([TenantStatusId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.Tenants') AND name=N'FK_ten_Tenants_CreatedByUserId')
    ALTER TABLE ten.Tenants WITH CHECK ADD CONSTRAINT [FK_ten_Tenants_CreatedByUserId] FOREIGN KEY ([CreatedByUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.Tenants') AND name=N'FK_ten_Tenants_UpdatedByUserId')
    ALTER TABLE ten.Tenants WITH CHECK ADD CONSTRAINT [FK_ten_Tenants_UpdatedByUserId] FOREIGN KEY ([UpdatedByUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.Organizations') AND name=N'FK_ten_Organizations_TenantId')
    ALTER TABLE ten.Organizations WITH CHECK ADD CONSTRAINT [FK_ten_Organizations_TenantId] FOREIGN KEY ([TenantId]) REFERENCES ten.Tenants ([TenantId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.Organizations') AND name=N'FK_ten_Organizations_OrganizationTypeId')
    ALTER TABLE ten.Organizations WITH CHECK ADD CONSTRAINT [FK_ten_Organizations_OrganizationTypeId] FOREIGN KEY ([OrganizationTypeId]) REFERENCES mst.OrganizationTypes ([OrganizationTypeId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.Organizations') AND name=N'FK_ten_Organizations_VerificationStatusId')
    ALTER TABLE ten.Organizations WITH CHECK ADD CONSTRAINT [FK_ten_Organizations_VerificationStatusId] FOREIGN KEY ([VerificationStatusId]) REFERENCES mst.VerificationStatuses ([VerificationStatusId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.Organizations') AND name=N'FK_ten_Organizations_VerifiedByUserId')
    ALTER TABLE ten.Organizations WITH CHECK ADD CONSTRAINT [FK_ten_Organizations_VerifiedByUserId] FOREIGN KEY ([VerifiedByUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.TenantMemberships') AND name=N'FK_ten_TenantMemberships_TenantId')
    ALTER TABLE ten.TenantMemberships WITH CHECK ADD CONSTRAINT [FK_ten_TenantMemberships_TenantId] FOREIGN KEY ([TenantId]) REFERENCES ten.Tenants ([TenantId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.TenantMemberships') AND name=N'FK_ten_TenantMemberships_UserId')
    ALTER TABLE ten.TenantMemberships WITH CHECK ADD CONSTRAINT [FK_ten_TenantMemberships_UserId] FOREIGN KEY ([UserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.TenantMemberships') AND name=N'FK_ten_TenantMemberships_MembershipStatusId')
    ALTER TABLE ten.TenantMemberships WITH CHECK ADD CONSTRAINT [FK_ten_TenantMemberships_MembershipStatusId] FOREIGN KEY ([MembershipStatusId]) REFERENCES mst.MembershipStatuses ([MembershipStatusId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.TenantMemberships') AND name=N'FK_ten_TenantMemberships_CreatedByUserId')
    ALTER TABLE ten.TenantMemberships WITH CHECK ADD CONSTRAINT [FK_ten_TenantMemberships_CreatedByUserId] FOREIGN KEY ([CreatedByUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'ten.TenantMemberships') AND name=N'FK_ten_TenantMemberships_UpdatedByUserId')
    ALTER TABLE ten.TenantMemberships WITH CHECK ADD CONSTRAINT [FK_ten_TenantMemberships_UpdatedByUserId] FOREIGN KEY ([UpdatedByUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.PlatformRoleAssignments') AND name=N'FK_iam_PlatformRoleAssignments_UserId')
    ALTER TABLE iam.PlatformRoleAssignments WITH CHECK ADD CONSTRAINT [FK_iam_PlatformRoleAssignments_UserId] FOREIGN KEY ([UserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.PlatformRoleAssignments') AND name=N'FK_iam_PlatformRoleAssignments_RoleId')
    ALTER TABLE iam.PlatformRoleAssignments WITH CHECK ADD CONSTRAINT [FK_iam_PlatformRoleAssignments_RoleId] FOREIGN KEY ([RoleId]) REFERENCES mst.Roles ([RoleId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.PlatformRoleAssignments') AND name=N'FK_iam_PlatformRoleAssignments_AssignedByUserId')
    ALTER TABLE iam.PlatformRoleAssignments WITH CHECK ADD CONSTRAINT [FK_iam_PlatformRoleAssignments_AssignedByUserId] FOREIGN KEY ([AssignedByUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.TenantRoleAssignments') AND name=N'FK_iam_TenantRoleAssignments_MembershipId')
    ALTER TABLE iam.TenantRoleAssignments WITH CHECK ADD CONSTRAINT [FK_iam_TenantRoleAssignments_MembershipId] FOREIGN KEY ([MembershipId]) REFERENCES ten.TenantMemberships ([MembershipId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.TenantRoleAssignments') AND name=N'FK_iam_TenantRoleAssignments_RoleId')
    ALTER TABLE iam.TenantRoleAssignments WITH CHECK ADD CONSTRAINT [FK_iam_TenantRoleAssignments_RoleId] FOREIGN KEY ([RoleId]) REFERENCES mst.Roles ([RoleId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.TenantRoleAssignments') AND name=N'FK_iam_TenantRoleAssignments_AssignedByUserId')
    ALTER TABLE iam.TenantRoleAssignments WITH CHECK ADD CONSTRAINT [FK_iam_TenantRoleAssignments_AssignedByUserId] FOREIGN KEY ([AssignedByUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.AuthSessions') AND name=N'FK_iam_AuthSessions_UserId')
    ALTER TABLE iam.AuthSessions WITH CHECK ADD CONSTRAINT [FK_iam_AuthSessions_UserId] FOREIGN KEY ([UserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.AuthSessions') AND name=N'FK_iam_AuthSessions_TenantId')
    ALTER TABLE iam.AuthSessions WITH CHECK ADD CONSTRAINT [FK_iam_AuthSessions_TenantId] FOREIGN KEY ([TenantId]) REFERENCES ten.Tenants ([TenantId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.RefreshTokens') AND name=N'FK_iam_RefreshTokens_AuthSessionId')
    ALTER TABLE iam.RefreshTokens WITH CHECK ADD CONSTRAINT [FK_iam_RefreshTokens_AuthSessionId] FOREIGN KEY ([AuthSessionId]) REFERENCES iam.AuthSessions ([AuthSessionId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'iam.RefreshTokens') AND name=N'FK_iam_RefreshTokens_PreviousTokenId')
    ALTER TABLE iam.RefreshTokens WITH CHECK ADD CONSTRAINT [FK_iam_RefreshTokens_PreviousTokenId] FOREIGN KEY ([PreviousTokenId]) REFERENCES iam.RefreshTokens ([RefreshTokenId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.AuditEvents') AND name=N'FK_aud_AuditEvents_TenantId')
    ALTER TABLE aud.AuditEvents WITH CHECK ADD CONSTRAINT [FK_aud_AuditEvents_TenantId] FOREIGN KEY ([TenantId]) REFERENCES ten.Tenants ([TenantId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.AuditEvents') AND name=N'FK_aud_AuditEvents_ActorUserId')
    ALTER TABLE aud.AuditEvents WITH CHECK ADD CONSTRAINT [FK_aud_AuditEvents_ActorUserId] FOREIGN KEY ([ActorUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.AuditEvents') AND name=N'FK_aud_AuditEvents_AuditActionTypeId')
    ALTER TABLE aud.AuditEvents WITH CHECK ADD CONSTRAINT [FK_aud_AuditEvents_AuditActionTypeId] FOREIGN KEY ([AuditActionTypeId]) REFERENCES mst.AuditActionTypes ([AuditActionTypeId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.AuditEvents') AND name=N'FK_aud_AuditEvents_AuditResultTypeId')
    ALTER TABLE aud.AuditEvents WITH CHECK ADD CONSTRAINT [FK_aud_AuditEvents_AuditResultTypeId] FOREIGN KEY ([AuditResultTypeId]) REFERENCES mst.AuditResultTypes ([AuditResultTypeId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.SecurityEvents') AND name=N'FK_aud_SecurityEvents_TenantId')
    ALTER TABLE aud.SecurityEvents WITH CHECK ADD CONSTRAINT [FK_aud_SecurityEvents_TenantId] FOREIGN KEY ([TenantId]) REFERENCES ten.Tenants ([TenantId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.SecurityEvents') AND name=N'FK_aud_SecurityEvents_ActorUserId')
    ALTER TABLE aud.SecurityEvents WITH CHECK ADD CONSTRAINT [FK_aud_SecurityEvents_ActorUserId] FOREIGN KEY ([ActorUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.SecurityEvents') AND name=N'FK_aud_SecurityEvents_SubjectUserId')
    ALTER TABLE aud.SecurityEvents WITH CHECK ADD CONSTRAINT [FK_aud_SecurityEvents_SubjectUserId] FOREIGN KEY ([SubjectUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.SecurityEvents') AND name=N'FK_aud_SecurityEvents_SecurityEventTypeId')
    ALTER TABLE aud.SecurityEvents WITH CHECK ADD CONSTRAINT [FK_aud_SecurityEvents_SecurityEventTypeId] FOREIGN KEY ([SecurityEventTypeId]) REFERENCES mst.SecurityEventTypes ([SecurityEventTypeId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.BusinessEvents') AND name=N'FK_aud_BusinessEvents_TenantId')
    ALTER TABLE aud.BusinessEvents WITH CHECK ADD CONSTRAINT [FK_aud_BusinessEvents_TenantId] FOREIGN KEY ([TenantId]) REFERENCES ten.Tenants ([TenantId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.BusinessEvents') AND name=N'FK_aud_BusinessEvents_ActorUserId')
    ALTER TABLE aud.BusinessEvents WITH CHECK ADD CONSTRAINT [FK_aud_BusinessEvents_ActorUserId] FOREIGN KEY ([ActorUserId]) REFERENCES iam.Users ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'aud.BusinessEvents') AND name=N'FK_aud_BusinessEvents_BusinessEventTypeId')
    ALTER TABLE aud.BusinessEvents WITH CHECK ADD CONSTRAINT [FK_aud_BusinessEvents_BusinessEventTypeId] FOREIGN KEY ([BusinessEventTypeId]) REFERENCES mst.BusinessEventTypes ([BusinessEventTypeId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.IdentityProviders') AND name=N'UX_IdentityProviders_Code')
    CREATE UNIQUE INDEX [UX_IdentityProviders_Code] ON mst.IdentityProviders ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.VerificationPurposes') AND name=N'UX_VerificationPurposes_Code')
    CREATE UNIQUE INDEX [UX_VerificationPurposes_Code] ON mst.VerificationPurposes ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.BusinessEventTypes') AND name=N'UX_BusinessEventTypes_Code')
    CREATE UNIQUE INDEX [UX_BusinessEventTypes_Code] ON mst.BusinessEventTypes ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.Users') AND name=N'UX_Users_PublicUserId')
    CREATE UNIQUE INDEX [UX_Users_PublicUserId] ON iam.Users ([PublicUserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.Users') AND name=N'UX_Users_NormalizedEmail')
    CREATE UNIQUE INDEX [UX_Users_NormalizedEmail] ON iam.Users ([NormalizedEmail]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.UserCredentials') AND name=N'UX_UserCredentials_UserId')
    CREATE UNIQUE INDEX [UX_UserCredentials_UserId] ON iam.UserCredentials ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.ExternalIdentities') AND name=N'UX_ExternalIdentities_ProviderIssuerSubject')
    CREATE UNIQUE INDEX [UX_ExternalIdentities_ProviderIssuerSubject] ON iam.ExternalIdentities ([IdentityProviderId], [Issuer], [Subject]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.ExternalIdentities') AND name=N'IX_ExternalIdentities_UserId')
    CREATE INDEX [IX_ExternalIdentities_UserId] ON iam.ExternalIdentities ([UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.VerificationChallenges') AND name=N'UX_VerificationChallenges_TokenHash')
    CREATE UNIQUE INDEX [UX_VerificationChallenges_TokenHash] ON iam.VerificationChallenges ([TokenHash]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.VerificationChallenges') AND name=N'IX_VerificationChallenges_UserPurposeExpiry')
    CREATE INDEX [IX_VerificationChallenges_UserPurposeExpiry] ON iam.VerificationChallenges ([UserId], [VerificationPurposeId], [ExpiresAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'ten.Tenants') AND name=N'UX_Tenants_PublicTenantId')
    CREATE UNIQUE INDEX [UX_Tenants_PublicTenantId] ON ten.Tenants ([PublicTenantId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'ten.Tenants') AND name=N'UX_Tenants_TenantCode')
    CREATE UNIQUE INDEX [UX_Tenants_TenantCode] ON ten.Tenants ([TenantCode]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'ten.Tenants') AND name=N'IX_Tenants_StatusType')
    CREATE INDEX [IX_Tenants_StatusType] ON ten.Tenants ([TenantStatusId], [TenantTypeId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'ten.Organizations') AND name=N'IX_Organizations_TypeStatus')
    CREATE INDEX [IX_Organizations_TypeStatus] ON ten.Organizations ([OrganizationTypeId], [VerificationStatusId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'ten.TenantMemberships') AND name=N'UX_Memberships_TenantUser')
    CREATE UNIQUE INDEX [UX_Memberships_TenantUser] ON ten.TenantMemberships ([TenantId], [UserId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'ten.TenantMemberships') AND name=N'IX_Memberships_UserStatus')
    CREATE INDEX [IX_Memberships_UserStatus] ON ten.TenantMemberships ([UserId], [MembershipStatusId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.PlatformRoleAssignments') AND name=N'UX_PlatformRoles_UserRole')
    CREATE UNIQUE INDEX [UX_PlatformRoles_UserRole] ON iam.PlatformRoleAssignments ([UserId], [RoleId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.TenantRoleAssignments') AND name=N'UX_TenantRoles_MembershipRole')
    CREATE UNIQUE INDEX [UX_TenantRoles_MembershipRole] ON iam.TenantRoleAssignments ([MembershipId], [RoleId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.TenantRoleAssignments') AND name=N'IX_TenantRoles_RoleId')
    CREATE INDEX [IX_TenantRoles_RoleId] ON iam.TenantRoleAssignments ([RoleId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.AuthSessions') AND name=N'UX_AuthSessions_PublicSessionId')
    CREATE UNIQUE INDEX [UX_AuthSessions_PublicSessionId] ON iam.AuthSessions ([PublicSessionId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.AuthSessions') AND name=N'IX_AuthSessions_UserActive')
    CREATE INDEX [IX_AuthSessions_UserActive] ON iam.AuthSessions ([UserId], [RevokedAtUtc], [ExpiresAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.RefreshTokens') AND name=N'UX_RefreshTokens_TokenHash')
    CREATE UNIQUE INDEX [UX_RefreshTokens_TokenHash] ON iam.RefreshTokens ([TokenHash]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.RefreshTokens') AND name=N'UX_RefreshTokens_PreviousToken')
    CREATE UNIQUE INDEX [UX_RefreshTokens_PreviousToken] ON iam.RefreshTokens ([PreviousTokenId]) WHERE [PreviousTokenId] IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'iam.RefreshTokens') AND name=N'IX_RefreshTokens_SessionExpiry')
    CREATE INDEX [IX_RefreshTokens_SessionExpiry] ON iam.RefreshTokens ([AuthSessionId], [RevokedAtUtc], [ExpiresAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'aud.AuditEvents') AND name=N'IX_AuditEvents_TenantTime')
    CREATE INDEX [IX_AuditEvents_TenantTime] ON aud.AuditEvents ([TenantId], [OccurredAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'aud.AuditEvents') AND name=N'IX_AuditEvents_Correlation')
    CREATE INDEX [IX_AuditEvents_Correlation] ON aud.AuditEvents ([CorrelationId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'aud.SecurityEvents') AND name=N'IX_SecurityEvents_TenantTime')
    CREATE INDEX [IX_SecurityEvents_TenantTime] ON aud.SecurityEvents ([TenantId], [OccurredAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'aud.SecurityEvents') AND name=N'IX_SecurityEvents_SubjectTime')
    CREATE INDEX [IX_SecurityEvents_SubjectTime] ON aud.SecurityEvents ([SubjectUserId], [OccurredAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'aud.BusinessEvents') AND name=N'IX_BusinessEvents_TenantTime')
    CREATE INDEX [IX_BusinessEvents_TenantTime] ON aud.BusinessEvents ([TenantId], [OccurredAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'aud.BusinessEvents') AND name=N'IX_BusinessEvents_Target')
    CREATE INDEX [IX_BusinessEvents_Target] ON aud.BusinessEvents ([TargetType], [TargetId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'iam.UserCredentials') AND name=N'CK_UserCredentials_FailedLoginCount')
    ALTER TABLE iam.UserCredentials WITH CHECK ADD CONSTRAINT [CK_UserCredentials_FailedLoginCount] CHECK ([FailedLoginCount] >= 0);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'iam.VerificationChallenges') AND name=N'CK_VerificationChallenges_Expiry')
    ALTER TABLE iam.VerificationChallenges WITH CHECK ADD CONSTRAINT [CK_VerificationChallenges_Expiry] CHECK ([ExpiresAtUtc] > [CreatedAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'ten.TenantMemberships') AND name=N'CK_TenantMemberships_Period')
    ALTER TABLE ten.TenantMemberships WITH CHECK ADD CONSTRAINT [CK_TenantMemberships_Period] CHECK ([LeftAtUtc] IS NULL OR [JoinedAtUtc] IS NULL OR [LeftAtUtc] >= [JoinedAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'iam.AuthSessions') AND name=N'CK_AuthSessions_Expiry')
    ALTER TABLE iam.AuthSessions WITH CHECK ADD CONSTRAINT [CK_AuthSessions_Expiry] CHECK ([ExpiresAtUtc] > [CreatedAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'iam.RefreshTokens') AND name=N'CK_RefreshTokens_Expiry')
    ALTER TABLE iam.RefreshTokens WITH CHECK ADD CONSTRAINT [CK_RefreshTokens_Expiry] CHECK ([ExpiresAtUtc] > [CreatedAtUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'aud.AuditEvents') AND name=N'CK_AuditEvents_Actor')
    ALTER TABLE aud.AuditEvents WITH CHECK ADD CONSTRAINT [CK_AuditEvents_Actor] CHECK ([ActorUserId] IS NOT NULL OR [ActorService] IS NOT NULL);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'aud.AuditEvents') AND name=N'CK_AuditEvents_Json')
    ALTER TABLE aud.AuditEvents WITH CHECK ADD CONSTRAINT [CK_AuditEvents_Json] CHECK ([ChangeSummaryJson] IS NULL OR ISJSON([ChangeSummaryJson]) = 1);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'aud.SecurityEvents') AND name=N'CK_SecurityEvents_Severity')
    ALTER TABLE aud.SecurityEvents WITH CHECK ADD CONSTRAINT [CK_SecurityEvents_Severity] CHECK ([SeverityCode] IN ('INFO','WARNING','CRITICAL'));
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'aud.SecurityEvents') AND name=N'CK_SecurityEvents_Json')
    ALTER TABLE aud.SecurityEvents WITH CHECK ADD CONSTRAINT [CK_SecurityEvents_Json] CHECK ([MetadataJson] IS NULL OR ISJSON([MetadataJson]) = 1);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'aud.BusinessEvents') AND name=N'CK_BusinessEvents_Json')
    ALTER TABLE aud.BusinessEvents WITH CHECK ADD CONSTRAINT [CK_BusinessEvents_Json] CHECK ([EventDataJson] IS NULL OR ISJSON([EventDataJson]) = 1);
GO
