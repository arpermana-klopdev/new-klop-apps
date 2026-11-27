import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { Outlet } from "react-router-dom";
import type { RegistrationType, TermsDocument } from "./termsDocuments";
import {
  isAvailableTermsDocument,
  isPublishedTermsDocument,
} from "./termsDocuments";

export type RegistrationDraft = {
  displayName: string;
  email: string;
  password: string;
  confirmPassword: string;
};

export type TermsDecision =
  | "NONE"
  | "DRAFT_ACKNOWLEDGED"
  | "PUBLISHED_ACCEPTED";

export type TermsAcceptance = {
  registrationType: RegistrationType | null;
  documentVersionId: string | null;
  documentKey: string | null;
  decision: TermsDecision;
};

type RegistrationFlowContextValue = {
  registrationType: RegistrationType | null;
  setRegistrationType: (type: RegistrationType | null) => void;
  registrationDraft: RegistrationDraft;
  setRegistrationDraft: (draft: RegistrationDraft) => void;
  clearSensitiveDraft: () => void;
  termsAcceptance: TermsAcceptance;
  recordDisplayedTermsDecision: (document: TermsDocument, documentLoaded: boolean) => boolean;
  resetTermsAcceptance: () => void;
};

const RegistrationFlowContext = createContext<RegistrationFlowContextValue | null>(null);

function emptyDraft(): RegistrationDraft {
  return { displayName: "", email: "", password: "", confirmPassword: "" };
}

function emptyAcceptance(): TermsAcceptance {
  return {
    registrationType: null,
    documentVersionId: null,
    documentKey: null,
    decision: "NONE",
  };
}

function termsDocumentKey(document: TermsDocument): string {
  return JSON.stringify([
    document.documentType,
    document.registrationType,
    document.documentVersionId,
    document.version,
    document.publicationStatus,
    document.effectiveDate,
    document.documentUrl,
    document.documentContent,
    document.contentHash,
    document.title,
  ]);
}

export function RegistrationFlowProvider({ children }: { children?: ReactNode }) {
  const [registrationType, setRegistrationTypeState] = useState<RegistrationType | null>(null);
  const [registrationDraft, setRegistrationDraft] = useState<RegistrationDraft>(emptyDraft);
  const [termsAcceptance, setTermsAcceptance] = useState<TermsAcceptance>(emptyAcceptance);

  const resetTermsAcceptance = useCallback(() => setTermsAcceptance(emptyAcceptance()), []);

  const setRegistrationType = useCallback(
    (type: RegistrationType | null) => {
      if (registrationType !== type) resetTermsAcceptance();
      setRegistrationTypeState(type);
    },
    [registrationType, resetTermsAcceptance],
  );

  const clearSensitiveDraft = useCallback(() => {
    setRegistrationDraft((draft) => ({
      ...draft,
      password: "",
      confirmPassword: "",
    }));
  }, []);

  const recordDisplayedTermsDecision = useCallback(
    (document: TermsDocument, documentLoaded: boolean) => {
      if (
        !registrationType ||
        !documentLoaded ||
        !isAvailableTermsDocument(document, registrationType)
      ) {
        return false;
      }

      const isPublished = isPublishedTermsDocument(document, registrationType);
      setTermsAcceptance({
        registrationType,
        documentVersionId: isPublished ? document.documentVersionId : null,
        documentKey: termsDocumentKey(document),
        decision: isPublished ? "PUBLISHED_ACCEPTED" : "DRAFT_ACKNOWLEDGED",
      });
      return true;
    },
    [registrationType],
  );

  const value = useMemo(
    () => ({
      registrationType,
      setRegistrationType,
      registrationDraft,
      setRegistrationDraft,
      clearSensitiveDraft,
      termsAcceptance,
      recordDisplayedTermsDecision,
      resetTermsAcceptance,
    }),
    [
      registrationType,
      setRegistrationType,
      registrationDraft,
      clearSensitiveDraft,
      termsAcceptance,
      recordDisplayedTermsDecision,
      resetTermsAcceptance,
    ],
  );

  return (
    <RegistrationFlowContext.Provider value={value}>
      {children ?? <Outlet />}
    </RegistrationFlowContext.Provider>
  );
}

export function useRegistrationFlow(): RegistrationFlowContextValue {
  const context = useContext(RegistrationFlowContext);
  if (!context) {
    throw new Error("useRegistrationFlow must be used within RegistrationFlowProvider.");
  }
  return context;
}

export function hasCurrentDisplayedTermsDecision(
  registrationType: RegistrationType | null,
  document: TermsDocument | null,
  acceptance: TermsAcceptance,
): boolean {
  return Boolean(
    registrationType &&
      document &&
      isAvailableTermsDocument(document, registrationType) &&
      acceptance.registrationType === registrationType &&
      acceptance.documentKey === termsDocumentKey(document) &&
      acceptance.decision !== "NONE",
  );
}

export function hasCurrentPublishedTermsAcceptance(
  registrationType: RegistrationType | null,
  document: TermsDocument | null,
  acceptance: TermsAcceptance,
): boolean {
  return Boolean(
    registrationType &&
      isPublishedTermsDocument(document, registrationType) &&
      acceptance.registrationType === registrationType &&
      acceptance.documentVersionId === document.documentVersionId &&
      acceptance.documentKey === termsDocumentKey(document) &&
      acceptance.decision === "PUBLISHED_ACCEPTED",
  );
}
