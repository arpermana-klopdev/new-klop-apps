SET NOCOUNT ON;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.TenantTypes') AND name=N'UX_TenantTypes_Code') CREATE UNIQUE INDEX [UX_TenantTypes_Code] ON mst.TenantTypes ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.TenantStatuses') AND name=N'UX_TenantStatuses_Code') CREATE UNIQUE INDEX [UX_TenantStatuses_Code] ON mst.TenantStatuses ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.MembershipStatuses') AND name=N'UX_MembershipStatuses_Code') CREATE UNIQUE INDEX [UX_MembershipStatuses_Code] ON mst.MembershipStatuses ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.RoleScopes') AND name=N'UX_RoleScopes_Code') CREATE UNIQUE INDEX [UX_RoleScopes_Code] ON mst.RoleScopes ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.VerificationStatuses') AND name=N'UX_VerificationStatuses_Code') CREATE UNIQUE INDEX [UX_VerificationStatuses_Code] ON mst.VerificationStatuses ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.AuditActionTypes') AND name=N'UX_AuditActionTypes_Code') CREATE UNIQUE INDEX [UX_AuditActionTypes_Code] ON mst.AuditActionTypes ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.SecurityEventTypes') AND name=N'UX_SecurityEventTypes_Code') CREATE UNIQUE INDEX [UX_SecurityEventTypes_Code] ON mst.SecurityEventTypes ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.AuditResultTypes') AND name=N'UX_AuditResultTypes_Code') CREATE UNIQUE INDEX [UX_AuditResultTypes_Code] ON mst.AuditResultTypes ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.OrganizationTypes') AND name=N'UX_OrganizationTypes_CountryCode_Code') CREATE UNIQUE INDEX [UX_OrganizationTypes_CountryCode_Code] ON mst.OrganizationTypes ([CountryCode], [Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.IdentityDocumentTypes') AND name=N'UX_IdentityDocumentTypes_CountryCode_Code') CREATE UNIQUE INDEX [UX_IdentityDocumentTypes_CountryCode_Code] ON mst.IdentityDocumentTypes ([CountryCode], [Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.OrganizationIdentityRequirementGroups') AND name=N'UX_OrganizationIdentityRequirementGroups_OrgType_Code') CREATE UNIQUE INDEX [UX_OrganizationIdentityRequirementGroups_OrgType_Code] ON mst.OrganizationIdentityRequirementGroups ([OrganizationTypeId], [Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.Roles') AND name=N'UX_Roles_RoleScope_Code') CREATE UNIQUE INDEX [UX_Roles_RoleScope_Code] ON mst.Roles ([RoleScopeId], [Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.Permissions') AND name=N'UX_Permissions_Code') CREATE UNIQUE INDEX [UX_Permissions_Code] ON mst.Permissions ([Code]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'cfg.SystemConfigurations') AND name=N'UX_SystemConfigurations_ConfigurationKey') CREATE UNIQUE INDEX [UX_SystemConfigurations_ConfigurationKey] ON cfg.SystemConfigurations ([ConfigurationKey]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.OrganizationIdentityRequirements') AND name=N'UX_OrganizationIdentityRequirements_Group_Document_Start') CREATE UNIQUE INDEX [UX_OrganizationIdentityRequirements_Group_Document_Start] ON mst.OrganizationIdentityRequirements ([RequirementGroupId], [IdentityDocumentTypeId], [EffectiveFromUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.RolePermissions') AND name=N'UX_RolePermissions_RoleId_PermissionId') CREATE UNIQUE INDEX [UX_RolePermissions_RoleId_PermissionId] ON mst.RolePermissions ([RoleId], [PermissionId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'mst.RolePermissions') AND name=N'IX_RolePermissions_PermissionId') CREATE INDEX [IX_RolePermissions_PermissionId] ON mst.RolePermissions ([PermissionId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_ReqGroup_OrgType') ALTER TABLE mst.OrganizationIdentityRequirementGroups WITH CHECK ADD CONSTRAINT FK_ReqGroup_OrgType FOREIGN KEY (OrganizationTypeId) REFERENCES mst.OrganizationTypes (OrganizationTypeId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Requirement_Group') ALTER TABLE mst.OrganizationIdentityRequirements WITH CHECK ADD CONSTRAINT FK_Requirement_Group FOREIGN KEY (RequirementGroupId) REFERENCES mst.OrganizationIdentityRequirementGroups (RequirementGroupId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Requirement_DocumentType') ALTER TABLE mst.OrganizationIdentityRequirements WITH CHECK ADD CONSTRAINT FK_Requirement_DocumentType FOREIGN KEY (IdentityDocumentTypeId) REFERENCES mst.IdentityDocumentTypes (IdentityDocumentTypeId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Roles_Scope') ALTER TABLE mst.Roles WITH CHECK ADD CONSTRAINT FK_Roles_Scope FOREIGN KEY (RoleScopeId) REFERENCES mst.RoleScopes (RoleScopeId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Permissions_Scope') ALTER TABLE mst.Permissions WITH CHECK ADD CONSTRAINT FK_Permissions_Scope FOREIGN KEY (RoleScopeId) REFERENCES mst.RoleScopes (RoleScopeId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_RolePermissions_Role') ALTER TABLE mst.RolePermissions WITH CHECK ADD CONSTRAINT FK_RolePermissions_Role FOREIGN KEY (RoleId) REFERENCES mst.Roles (RoleId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_RolePermissions_Permission') ALTER TABLE mst.RolePermissions WITH CHECK ADD CONSTRAINT FK_RolePermissions_Permission FOREIGN KEY (PermissionId) REFERENCES mst.Permissions (PermissionId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_RequirementGroup_Mode') ALTER TABLE mst.OrganizationIdentityRequirementGroups WITH CHECK ADD CONSTRAINT CK_RequirementGroup_Mode CHECK ([SelectionMode] IN ('ALL','ANY','MINIMUM'));
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_RequirementGroup_Min') ALTER TABLE mst.OrganizationIdentityRequirementGroups WITH CHECK ADD CONSTRAINT CK_RequirementGroup_Min CHECK ([MinimumRequired] >= 1);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_RequirementGroup_Period') ALTER TABLE mst.OrganizationIdentityRequirementGroups WITH CHECK ADD CONSTRAINT CK_RequirementGroup_Period CHECK ([EffectiveToUtc] IS NULL OR [EffectiveToUtc] > [EffectiveFromUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_Requirement_Level') ALTER TABLE mst.OrganizationIdentityRequirements WITH CHECK ADD CONSTRAINT CK_Requirement_Level CHECK ([RequirementLevel] IN ('REQUIRED','OPTIONAL','CONDITIONAL'));
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_Requirement_Period') ALTER TABLE mst.OrganizationIdentityRequirements WITH CHECK ADD CONSTRAINT CK_Requirement_Period CHECK ([EffectiveToUtc] IS NULL OR [EffectiveToUtc] > [EffectiveFromUtc]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_Severity') ALTER TABLE mst.SecurityEventTypes WITH CHECK ADD CONSTRAINT CK_Severity CHECK ([DefaultSeverity] IN ('INFO','WARNING','CRITICAL'));
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_Config_ValueType') ALTER TABLE cfg.SystemConfigurations WITH CHECK ADD CONSTRAINT CK_Config_ValueType CHECK ([ValueType] IN ('STRING','INTEGER','BOOLEAN','DECIMAL','JSON'));
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_Config_StorageType') ALTER TABLE cfg.SystemConfigurations WITH CHECK ADD CONSTRAINT CK_Config_StorageType CHECK ([StorageType] IN ('PLAIN','KEYVAULT_REFERENCE'));
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_Config_MinMax') ALTER TABLE cfg.SystemConfigurations WITH CHECK ADD CONSTRAINT CK_Config_MinMax CHECK ([MinNumericValue] IS NULL OR [MaxNumericValue] IS NULL OR [MinNumericValue] <= [MaxNumericValue]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_Config_PositiveVersion') ALTER TABLE cfg.SystemConfigurations WITH CHECK ADD CONSTRAINT CK_Config_PositiveVersion CHECK ([VersionNumber] >= 1);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_Config_Json') ALTER TABLE cfg.SystemConfigurations WITH CHECK ADD CONSTRAINT CK_Config_Json CHECK ([AllowedValuesJson] IS NULL OR ISJSON([AllowedValuesJson]) = 1);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name=N'CK_Config_ValueJson') ALTER TABLE cfg.SystemConfigurations WITH CHECK ADD CONSTRAINT CK_Config_ValueJson CHECK ([ValueType] <> 'JSON' OR [ConfigurationValue] IS NULL OR ISJSON([ConfigurationValue]) = 1);
GO
-- Cross-country consistency, group cardinality, period overlap and role/permission scope MUST also be validated by future audited write Stored Procedures.
