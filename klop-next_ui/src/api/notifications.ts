import { api, responseData } from "./client";
import type { ApiEnvelope } from "./contracts";
import type { components } from "./schema";

export type NotificationPermissions = components["schemas"]["NotificationPermissionsResponse"];
export type NotificationTemplate = components["schemas"]["NotificationTemplateSummary"];
export type NotificationTemplateDetail = components["schemas"]["NotificationTemplateDetail"];
export type NotificationTemplateVersion = components["schemas"]["NotificationTemplateVersion"];
export type NotificationChannel = components["schemas"]["NotificationChannelStatus"];
export type NotificationHistoryPage = components["schemas"]["NotificationDeliveryHistoryPage"];
export type NotificationReadiness = components["schemas"]["NotificationSettingsReadiness"];
export type NotificationTemplatePreview = components["schemas"]["NotificationTemplatePreviewResponse"];
export type NotificationDraftResult = components["schemas"]["NotificationTemplateDraftResult"];
export type NotificationDraftRequest = components["schemas"]["NotificationTemplateDraftRequest"];
export type NotificationCreateDraftRequest = components["schemas"]["CreateNotificationTemplateRequest"];
export type NotificationDecisionRequest = components["schemas"]["NotificationDecisionRequest"];

export async function getNotificationPermissions(): Promise<NotificationPermissions> {
  const response = await api.get<ApiEnvelope<NotificationPermissions>>("platform/notifications/permissions");
  return responseData(response);
}

export async function getNotificationTemplates(): Promise<NotificationTemplate[]> {
  const response = await api.get<ApiEnvelope<NotificationTemplate[]>>("platform/notifications/templates");
  return responseData(response);
}

export async function getNotificationTemplate(templateId: string): Promise<NotificationTemplateDetail> {
  const response = await api.get<ApiEnvelope<NotificationTemplateDetail>>(
    `platform/notifications/templates/${encodeURIComponent(templateId)}`,
  );
  return responseData(response);
}

export async function createNotificationDraft(
  request: NotificationCreateDraftRequest,
): Promise<NotificationDraftResult> {
  const response = await api.post<ApiEnvelope<NotificationDraftResult>>(
    "platform/notifications/templates",
    request,
  );
  return responseData(response);
}

export async function updateNotificationDraft(
  versionId: string,
  request: NotificationDraftRequest,
): Promise<NotificationDraftResult> {
  const response = await api.put<ApiEnvelope<NotificationDraftResult>>(
    `platform/notifications/versions/${encodeURIComponent(versionId)}`,
    request,
  );
  return responseData(response);
}

export async function previewNotificationDraft(versionId: string): Promise<NotificationTemplatePreview> {
  const response = await api.post<ApiEnvelope<NotificationTemplatePreview>>(
    `platform/notifications/versions/${encodeURIComponent(versionId)}/preview`,
  );
  return responseData(response);
}

export async function transitionNotificationVersion(
  versionId: string,
  action: "submit" | "approval" | "activate" | "archive",
  request: NotificationDecisionRequest,
): Promise<NotificationTemplateVersion[]> {
  const response = await api.post<ApiEnvelope<NotificationTemplateVersion[]>>(
    `platform/notifications/versions/${encodeURIComponent(versionId)}/${action}`,
    request,
  );
  return responseData(response);
}

export async function getNotificationChannels(): Promise<NotificationChannel[]> {
  const response = await api.get<ApiEnvelope<NotificationChannel[]>>("platform/notifications/channels");
  return responseData(response);
}

export async function getNotificationHistory(pageNumber = 1, pageSize = 20): Promise<NotificationHistoryPage> {
  const response = await api.get<ApiEnvelope<NotificationHistoryPage>>("platform/notifications/history", {
    params: { pageNumber, pageSize },
  });
  return responseData(response);
}

export async function getNotificationReadiness(): Promise<NotificationReadiness> {
  const response = await api.get<ApiEnvelope<NotificationReadiness>>(
    "platform/notifications/settings/readiness",
  );
  return responseData(response);
}
