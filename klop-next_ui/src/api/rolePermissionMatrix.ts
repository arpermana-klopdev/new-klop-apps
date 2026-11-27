import { api, responseData } from "./client";
import type {
  RolePermissionMatrixAccessResponse,
  RolePermissionMatrixBatchRequest,
  RolePermissionMatrixHistoryEntry,
  RolePermissionMatrixResponse,
  RolePermissionMatrixSaveResponse,
  RolePermissionMatrixValidationResponse,
} from "./contracts";

export async function getRolePermissionMatrixAccess(): Promise<RolePermissionMatrixAccessResponse> {
  const response = await api.get("platform/role-permissions/access");
  return responseData(response);
}

export async function getRolePermissionMatrix(): Promise<RolePermissionMatrixResponse> {
  const response = await api.get("platform/role-permissions/matrix");
  return responseData(response);
}

export async function validateRolePermissionChanges(
  request: RolePermissionMatrixBatchRequest,
): Promise<RolePermissionMatrixValidationResponse> {
  const response = await api.post("platform/role-permissions/changes/validate", request);
  return responseData(response);
}

export async function saveRolePermissionChanges(
  request: RolePermissionMatrixBatchRequest,
): Promise<RolePermissionMatrixSaveResponse> {
  const response = await api.post("platform/role-permissions/changes", request);
  return responseData(response);
}

export async function getRolePermissionHistory(): Promise<RolePermissionMatrixHistoryEntry[]> {
  const response = await api.get("platform/role-permissions/history");
  return responseData(response);
}
