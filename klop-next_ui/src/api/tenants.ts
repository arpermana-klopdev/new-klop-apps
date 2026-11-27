import { api, responseData } from "./client";
import type {
  ApiEnvelope,
  InviteRequest,
  OrganizationType,
  RoleRequest,
  TenantCreateRequest,
  TenantCreateResult,
  TenantPermissionsResponse,
  TenantSummary,
  TenantTypeReference,
} from "./contracts";

export async function getTenantPermissions(
  tenantId: number | string,
): Promise<TenantPermissionsResponse> {
  const response = await api.get<ApiEnvelope<TenantPermissionsResponse>>(
    `tenants/${tenantId}/permissions`,
  );
  return responseData(response);
}

export async function getMyTenants(): Promise<TenantSummary[]> {
  const response = await api.get<ApiEnvelope<TenantSummary[]>>("tenants/mine");
  return responseData(response);
}

export async function getOrganizationTypes(): Promise<OrganizationType[]> {
  const response = await api.get<ApiEnvelope<OrganizationType[]>>(
    "master/organization-types",
  );
  return responseData(response);
}

export async function getTenantTypes(): Promise<TenantTypeReference[]> {
  const response = await api.get<ApiEnvelope<TenantTypeReference[]>>("master/tenant-types");
  return responseData(response);
}

export async function createTenant(
  request: TenantCreateRequest,
): Promise<TenantCreateResult> {
  const response = await api.post<ApiEnvelope<TenantCreateResult>>("tenants", request);
  return responseData(response);
}

export async function inviteMember(
  tenantId: number | string,
  request: InviteRequest,
): Promise<{ membershipId: number | string }> {
  const response = await api.post<ApiEnvelope<{ membershipId: number | string }>>(
    `tenants/${tenantId}/invitations`,
    request,
  );
  return responseData(response);
}

export async function acceptMembership(membershipId: number | string): Promise<void> {
  const response = await api.post<ApiEnvelope<{ accepted: boolean }>>(
    `tenants/memberships/${membershipId}/accept`,
  );
  responseData(response);
}

export async function removeMember(
  tenantId: number | string,
  membershipId: number | string,
): Promise<void> {
  const response = await api.delete<ApiEnvelope<{ removed: boolean }>>(
    `tenants/${tenantId}/memberships/${membershipId}`,
  );
  responseData(response);
}

export async function assignRole(
  tenantId: number | string,
  membershipId: number | string,
  request: RoleRequest,
): Promise<void> {
  const response = await api.post<ApiEnvelope<{ assigned: boolean }>>(
    `tenants/${tenantId}/memberships/${membershipId}/roles`,
    request,
  );
  responseData(response);
}

export async function revokeRole(
  tenantId: number | string,
  membershipId: number | string,
  roleCode: string,
): Promise<void> {
  const response = await api.delete<ApiEnvelope<{ revoked: boolean }>>(
    `tenants/${tenantId}/memberships/${membershipId}/roles/${encodeURIComponent(roleCode)}`,
  );
  responseData(response);
}
