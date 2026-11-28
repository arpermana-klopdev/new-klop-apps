import { api, responseData } from "./client";
import type {
  SystemConfigurationAccessResponse,
  SystemConfigurationCatalogPage,
  SystemConfigurationDecisionRequest,
  SystemConfigurationDraftRequest,
  SystemConfigurationDraftResult,
  SystemConfigurationDraftUpdate,
  SystemConfigurationHistoryPage,
  SystemConfigurationRequestPage,
  SystemConfigurationTransitionRequest,
} from "./contracts";

export async function getSystemConfigurationPermissions(): Promise<SystemConfigurationAccessResponse> {
  const response = await api.get("platform/configurations/permissions");
  return responseData(response);
}

export async function getSystemConfigurationCatalog(params: {
  category?: string;
  pageNumber?: number;
  pageSize?: number;
} = {}): Promise<SystemConfigurationCatalogPage> {
  const response = await api.get("platform/configurations/catalog", { params });
  return responseData(response);
}

export async function getSystemConfigurationRequests(
  status = "ALL",
  pageNumber = 1,
  pageSize = 25,
): Promise<SystemConfigurationRequestPage> {
  const response = await api.get("platform/configurations/requests", {
    params: { status, pageNumber, pageSize },
  });
  return responseData(response);
}

export async function getSystemConfigurationApprovals(
  pageNumber = 1,
  pageSize = 25,
): Promise<SystemConfigurationRequestPage> {
  const response = await api.get("platform/configurations/approvals", {
    params: { pageNumber, pageSize },
  });
  return responseData(response);
}

export async function getSystemConfigurationHistory(
  pageNumber = 1,
  pageSize = 25,
): Promise<SystemConfigurationHistoryPage> {
  const response = await api.get("platform/configurations/history", {
    params: { pageNumber, pageSize },
  });
  return responseData(response);
}

export async function createSystemConfigurationDraft(
  request: SystemConfigurationDraftRequest,
): Promise<SystemConfigurationDraftResult> {
  const response = await api.post("platform/configurations/requests", request);
  return responseData(response);
}

export async function updateSystemConfigurationDraft(
  requestId: string,
  request: SystemConfigurationDraftUpdate,
): Promise<SystemConfigurationDraftResult> {
  const response = await api.put(`platform/configurations/requests/${requestId}`, request);
  return responseData(response);
}

export async function submitSystemConfigurationDraft(
  requestId: string,
  request: SystemConfigurationTransitionRequest,
): Promise<SystemConfigurationDraftResult> {
  const response = await api.post(`platform/configurations/requests/${requestId}/submit`, request);
  return responseData(response);
}

export async function decideSystemConfigurationRequest(
  requestId: string,
  request: SystemConfigurationDecisionRequest,
): Promise<SystemConfigurationDraftResult> {
  const response = await api.post(`platform/configurations/requests/${requestId}/approval`, request);
  return responseData(response);
}

export async function cancelSystemConfigurationRequest(
  requestId: string,
  request: SystemConfigurationTransitionRequest,
): Promise<SystemConfigurationDraftResult> {
  const response = await api.post(`platform/configurations/requests/${requestId}/cancel`, request);
  return responseData(response);
}

export async function applySystemConfigurationRequest(
  requestId: string,
  request: SystemConfigurationTransitionRequest,
): Promise<SystemConfigurationDraftResult> {
  const response = await api.post(`platform/configurations/requests/${requestId}/apply`, request);
  return responseData(response);
}
