import { ApiRequestError, resolveApiUrl } from "../../api/client";
import { getCurrentTerms } from "../../api/legal";

export type RegistrationType = "PERSONAL" | "ORGANIZATION";
export type TermsDocumentType = "TERMS_AND_CONDITIONS";
export type TermsPublicationStatus = "DRAFT" | "PUBLISHED" | "WITHDRAWN";

function isRegistrationType(value: string): value is RegistrationType {
  return value === "PERSONAL" || value === "ORGANIZATION";
}

function isTermsPublicationStatus(value: string): value is TermsPublicationStatus {
  return value === "DRAFT" || value === "PUBLISHED" || value === "WITHDRAWN";
}

export type TermsDocument = {
  documentVersionId: string | null;
  sourceFileName?: string;
  documentType: TermsDocumentType;
  registrationType: RegistrationType;
  title: string;
  version: string | null;
  effectiveDate: string | null;
  publicationStatus: TermsPublicationStatus;
  documentContent?: string | null;
  documentUrl?: string | null;
  contentHash?: string;
};

export type PublishedTermsDocument = TermsDocument & {
  documentVersionId: string;
  version: string;
  publicationStatus: "PUBLISHED";
};

export type TermsDocumentLoader = (
  registrationType: RegistrationType,
) => Promise<TermsDocument | null>;

export type TermsDocumentApi = {
  getCurrentPublishedTerms: TermsDocumentLoader;
};

const termsPdfFileName = "KLOP_Next_Terms_and_Conditions.pdf";
const termsPdfUrl = `${import.meta.env.BASE_URL.replace(/\/?$/, "/")}documents/${termsPdfFileName}`;

export const TERMS_DOCUMENT_CONFIG: Readonly<Record<RegistrationType, TermsDocument>> = {
  PERSONAL: {
    documentVersionId: null,
    sourceFileName: termsPdfFileName,
    documentType: "TERMS_AND_CONDITIONS",
    registrationType: "PERSONAL",
    title: "KLOP Next - One Portal | Terms & Conditions Draft (PERSONAL dan ORGANIZATION)",
    version: "0.1 (draft; not approved)",
    effectiveDate: null,
    publicationStatus: "DRAFT",
    documentUrl: termsPdfUrl,
  },
  ORGANIZATION: {
    documentVersionId: null,
    sourceFileName: termsPdfFileName,
    documentType: "TERMS_AND_CONDITIONS",
    registrationType: "ORGANIZATION",
    title: "KLOP Next - One Portal | Terms & Conditions Draft (PERSONAL dan ORGANIZATION)",
    version: "0.1 (draft; not approved)",
    effectiveDate: null,
    publicationStatus: "DRAFT",
    documentUrl: termsPdfUrl,
  },
};

export function isAvailableTermsDocument(
  document: TermsDocument | null,
  registrationType: RegistrationType,
): document is TermsDocument {
  return Boolean(
    document &&
      (document.documentVersionId?.trim() || document.sourceFileName?.trim()) &&
      document.documentType === "TERMS_AND_CONDITIONS" &&
      document.registrationType === registrationType &&
      document.title.trim() &&
      (document.documentContent?.trim() || document.documentUrl?.trim()),
  );
}

export function isPublishedTermsDocument(
  document: TermsDocument | null,
  registrationType: RegistrationType,
): document is PublishedTermsDocument {
  return Boolean(
    isAvailableTermsDocument(document, registrationType) &&
      document.documentVersionId?.trim() &&
      document.version?.trim() &&
      document.publicationStatus === "PUBLISHED",
  );
}

export function createTermsDocumentLoader(api: TermsDocumentApi): TermsDocumentLoader {
  return async (registrationType) => {
    const document = await api.getCurrentPublishedTerms(registrationType);
    return isPublishedTermsDocument(document, registrationType) ? document : null;
  };
}

export async function loadCurrentTermsDocument(
  registrationType: RegistrationType,
): Promise<TermsDocument | null> {
  try {
    const metadata = await getCurrentTerms(registrationType);
    if (
      !isRegistrationType(metadata.registrationType) ||
      !isTermsPublicationStatus(metadata.publicationStatus)
    ) {
      return null;
    }

    return {
      documentVersionId: metadata.documentVersionId,
      documentType: "TERMS_AND_CONDITIONS",
      registrationType: metadata.registrationType,
      title: metadata.title,
      version: metadata.version,
      effectiveDate: metadata.effectiveAtUtc,
      publicationStatus: metadata.publicationStatus,
      documentUrl: resolveApiUrl(metadata.documentUrl),
      contentHash: metadata.contentHash,
    };
  } catch (error: unknown) {
    if (error instanceof ApiRequestError && error.code === "TERMS_UNAVAILABLE") {
      return TERMS_DOCUMENT_CONFIG[registrationType];
    }
    throw error;
  }
}
