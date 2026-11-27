import { api, responseData } from "./client";
import type { ApiEnvelope, LegalTermsMetadata } from "./contracts";

export type PlatformLegalDocumentVersion = {
  documentVersionId: string;
  versionIdentifier: string;
  title: string;
  effectiveAtUtc: string;
  publicationStatus: "DRAFT" | "PENDING_APPROVAL" | "APPROVED" | "PUBLISHED" | "ARCHIVED";
  fileSizeBytes: number;
  contentHash: string;
  createdAtUtc: string;
  submittedAtUtc: string | null;
  approvedAtUtc: string | null;
  publishedAtUtc: string | null;
  archivedAtUtc: string | null;
  latestApprovalDecisionCode: "APPROVED" | "REJECTED" | null;
  latestApprovalDecisionAtUtc: string | null;
  latestApprovalDecisionNote: string | null;
  registrationScopes: ("PERSONAL" | "ORGANIZATION")[];
  rowVersion: string;
};

export type PlatformLegalDocument = {
  legalDocumentId: string;
  documentTypeCode: string;
  versions: PlatformLegalDocumentVersion[];
};

export type PlatformLegalDocumentPermissions = {
  permissions: string[];
};

export type LegalDocumentDraftMetadata = {
  title: string;
  versionIdentifier: string;
  effectiveAtUtc: string;
  registrationTypes: ("PERSONAL" | "ORGANIZATION")[];
};

export async function getCurrentTerms(
  registrationType: "PERSONAL" | "ORGANIZATION",
): Promise<LegalTermsMetadata> {
  const response = await api.get<ApiEnvelope<LegalTermsMetadata>>(
    "public/legal/terms/current",
    {
      params: { registrationType },
      headers: { "Cache-Control": "no-cache" },
    },
  );
  return responseData(response);
}

export async function getPlatformLegalDocumentPermissions(): Promise<PlatformLegalDocumentPermissions> {
  const response = await api.get<ApiEnvelope<PlatformLegalDocumentPermissions>>(
    "platform/legal-documents/permissions",
  );
  return responseData(response);
}

export async function getPlatformLegalDocuments(): Promise<PlatformLegalDocument[]> {
  const response = await api.get<ApiEnvelope<PlatformLegalDocument[]>>(
    "platform/legal-documents",
  );
  return responseData(response);
}

export async function uploadPlatformLegalDocument(
  metadata: LegalDocumentDraftMetadata,
  file: File,
  legalDocumentId?: string,
): Promise<PlatformLegalDocument> {
  const form = new FormData();
  form.append("title", metadata.title);
  form.append("versionIdentifier", metadata.versionIdentifier);
  form.append("effectiveAtUtc", metadata.effectiveAtUtc);
  metadata.registrationTypes.forEach((registrationType) =>
    form.append("registrationTypes", registrationType),
  );
  if (legalDocumentId) form.append("legalDocumentId", legalDocumentId);
  form.append("file", file);

  const response = await api.post<ApiEnvelope<PlatformLegalDocument>>(
    "platform/legal-documents",
    form,
    { headers: { "Content-Type": "multipart/form-data" } },
  );
  return responseData(response);
}

export async function updatePlatformLegalDocumentDraft(
  documentVersionId: string,
  metadata: LegalDocumentDraftMetadata,
  rowVersion: string,
): Promise<PlatformLegalDocument> {
  const response = await api.put<ApiEnvelope<PlatformLegalDocument>>(
    `platform/legal-documents/versions/${encodeURIComponent(documentVersionId)}`,
    { ...metadata, rowVersion },
  );
  return responseData(response);
}

export async function getPlatformLegalDocumentPreview(
  documentVersionId: string,
): Promise<Blob> {
  const response = await api.get<Blob>(
    `platform/legal-documents/versions/${encodeURIComponent(documentVersionId)}/preview`,
    { responseType: "blob" },
  );
  return response.data;
}

export async function submitPlatformLegalDocument(
  documentVersionId: string,
): Promise<PlatformLegalDocument> {
  const response = await api.post<ApiEnvelope<PlatformLegalDocument>>(
    `platform/legal-documents/versions/${encodeURIComponent(documentVersionId)}/submit-for-approval`,
  );
  return responseData(response);
}

export async function decidePlatformLegalDocument(
  documentVersionId: string,
  decisionCode: "APPROVED" | "REJECTED",
  decisionNote?: string,
): Promise<PlatformLegalDocument> {
  const response = await api.post<ApiEnvelope<PlatformLegalDocument>>(
    `platform/legal-documents/versions/${encodeURIComponent(documentVersionId)}/approve`,
    { decisionCode, decisionNote },
  );
  return responseData(response);
}

export async function publishPlatformLegalDocument(
  documentVersionId: string,
): Promise<PlatformLegalDocument> {
  const response = await api.post<ApiEnvelope<PlatformLegalDocument>>(
    `platform/legal-documents/versions/${encodeURIComponent(documentVersionId)}/publish`,
  );
  return responseData(response);
}

export async function archivePlatformLegalDocument(
  documentVersionId: string,
): Promise<PlatformLegalDocument> {
  const response = await api.post<ApiEnvelope<PlatformLegalDocument>>(
    `platform/legal-documents/versions/${encodeURIComponent(documentVersionId)}/archive`,
  );
  return responseData(response);
}
