import { api, responseData } from "../../api/client";
import type { ApiEnvelope } from "../../api/contracts";
import type { components } from "../../api/schema";

export type RegistrationType =
  components["schemas"]["PlatformRegistrationSummary"]["registrationType"];
export type RegistrationSummary = components["schemas"]["PlatformRegistrationSummary"];
export type RegistrationPermissions = components["schemas"]["PlatformRegistrationPermissions"];
export type RegistrationListItem = components["schemas"]["PlatformRegistrationListItem"];
export type RegistrationListResult = components["schemas"]["PlatformRegistrationPage"];

export type RegistrationListParams = {
  registrationType: RegistrationType;
  search?: string;
  emailVerificationStatus?: string;
  applicationStatus?: string;
  pageNumber: number;
  pageSize: number;
};

export type RegistrationDetail = components["schemas"]["PlatformRegistrationDetail"];
export type RegistrationTimelineEvent =
  components["schemas"]["PlatformRegistrationTimelineEvent"];

export async function getRegistrationPermissions(): Promise<RegistrationPermissions> {
  const response = await api.get<ApiEnvelope<RegistrationPermissions>>(
    "platform/registrations/permissions",
  );
  return responseData(response);
}

export async function getRegistrationSummary(
  registrationType: RegistrationType,
): Promise<RegistrationSummary> {
  const response = await api.get<ApiEnvelope<RegistrationSummary>>(
    "platform/registrations/summary",
    { params: { registrationType } },
  );
  return responseData(response);
}

export async function getRegistrations(
  params: RegistrationListParams,
): Promise<RegistrationListResult> {
  const response = await api.get<ApiEnvelope<RegistrationListResult>>(
    "platform/registrations",
    { params },
  );
  return responseData(response);
}

export async function getRegistrationDetail(id: number): Promise<RegistrationDetail> {
  const response = await api.get<ApiEnvelope<RegistrationDetail>>(`platform/registrations/${id}`);
  return responseData(response);
}

export async function getRegistrationTimeline(id: number): Promise<RegistrationTimelineEvent[]> {
  const response = await api.get<ApiEnvelope<RegistrationTimelineEvent[]>>(
    `platform/registrations/${id}/timeline`,
  );
  return responseData(response);
}
