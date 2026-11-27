SET NOCOUNT ON;
GO
CREATE OR ALTER PROCEDURE mst.usp_TenantType_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.TenantTypes WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_TenantStatuse_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.TenantStatuses WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_OrganizationType_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.OrganizationTypes WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_IdentityDocumentType_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.IdentityDocumentTypes WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_OrganizationIdentityRequirementGroup_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.OrganizationIdentityRequirementGroups WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_MembershipStatuse_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.MembershipStatuses WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_RoleScope_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.RoleScopes WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_Role_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.Roles WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_Permission_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.Permissions WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_VerificationStatuse_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.VerificationStatuses WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_AuditActionType_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.AuditActionTypes WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_SecurityEventType_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.SecurityEventTypes WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_AuditResultType_GetAll @ActiveOnly BIT = 1 AS BEGIN SET NOCOUNT ON; SELECT * FROM mst.AuditResultTypes WHERE (@ActiveOnly = 0 OR IsActive = 1) ORDER BY [SortOrder], [Name]; END;
GO
CREATE OR ALTER PROCEDURE cfg.usp_Configuration_GetByKey @ConfigurationKey VARCHAR(150) AS BEGIN SET NOCOUNT ON; SELECT ConfigurationKey, ConfigurationValue, ValueType, Category, StorageType, VersionNumber, RequiresRestart, RowVersion FROM cfg.SystemConfigurations WHERE ConfigurationKey=@ConfigurationKey AND IsActive=1; END;
GO
CREATE OR ALTER PROCEDURE cfg.usp_Configuration_GetAll AS BEGIN SET NOCOUNT ON; SELECT ConfigurationKey, ConfigurationValue, ValueType, Category, StorageType, VersionNumber, RequiresRestart FROM cfg.SystemConfigurations WHERE IsActive=1 ORDER BY Category, ConfigurationKey; END;
GO
CREATE OR ALTER PROCEDURE mst.usp_OrganizationIdentityRequirement_GetByOrganizationType @OrganizationTypeId BIGINT, @AsOfUtc DATETIME2(3) AS BEGIN SET NOCOUNT ON; SELECT g.RequirementGroupId,g.Code AS GroupCode,g.SelectionMode,g.MinimumRequired,r.RequirementId,r.RequirementLevel,d.Code AS DocumentCode,d.Name AS DocumentName FROM mst.OrganizationIdentityRequirementGroups g JOIN mst.OrganizationIdentityRequirements r ON r.RequirementGroupId=g.RequirementGroupId JOIN mst.IdentityDocumentTypes d ON d.IdentityDocumentTypeId=r.IdentityDocumentTypeId JOIN mst.OrganizationTypes o ON o.OrganizationTypeId=g.OrganizationTypeId WHERE g.OrganizationTypeId=@OrganizationTypeId AND g.IsActive=1 AND r.IsActive=1 AND d.IsActive=1 AND d.CountryCode=o.CountryCode AND @AsOfUtc>=g.EffectiveFromUtc AND (g.EffectiveToUtc IS NULL OR @AsOfUtc<g.EffectiveToUtc) AND @AsOfUtc>=r.EffectiveFromUtc AND (r.EffectiveToUtc IS NULL OR @AsOfUtc<r.EffectiveToUtc); END;
GO
-- NOTE: Read procedures are privileged internal operations; DO NOT expose all columns to public HTTP clients. Project to safe DTOs and authorize endpoints.
