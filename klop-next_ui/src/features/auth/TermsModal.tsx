import { useCallback, useEffect, useState, type RefObject } from "react";
import { Button, Dialog } from "../../components/ui";
import {
  hasCurrentDisplayedTermsDecision,
  useRegistrationFlow,
} from "./RegistrationFlowContext";
import {
  isAvailableTermsDocument,
  isPublishedTermsDocument,
  loadCurrentTermsDocument,
  TERMS_DOCUMENT_CONFIG,
  type RegistrationType,
  type TermsDocument,
} from "./termsDocuments";
import { TermsPdfViewer } from "./TermsPdfViewer";

export function TermsModal({
  open,
  onOpenChange,
  registrationType,
  triggerRef,
  onDocumentChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  registrationType: RegistrationType;
  triggerRef: RefObject<HTMLButtonElement | null>;
  onDocumentChange: (document: TermsDocument | null) => void;
}) {
  const { recordDisplayedTermsDecision, resetTermsAcceptance, termsAcceptance } =
    useRegistrationFlow();
  const [document, setDocument] = useState<TermsDocument | null>(null);
  const [documentReady, setDocumentReady] = useState(false);
  const [documentLoaded, setDocumentLoaded] = useState(false);
  const [explicitlyAgreed, setExplicitlyAgreed] = useState(false);
  const handlePdfLoaded = useCallback(() => setDocumentLoaded(true), []);
  const handlePdfError = useCallback(() => setDocumentLoaded(false), []);

  useEffect(() => {
    if (!open) return;

    let active = true;
    setDocumentReady(false);
    setDocument(null);
    onDocumentChange(null);
    setDocumentLoaded(false);
    setExplicitlyAgreed(false);

    loadCurrentTermsDocument(registrationType)
      .then((loadedDocument) => {
        if (!active) return;
        const displayedDocument = isAvailableTermsDocument(loadedDocument, registrationType)
          ? loadedDocument
          : TERMS_DOCUMENT_CONFIG[registrationType];

        setDocument(displayedDocument);
        onDocumentChange(displayedDocument);
        setDocumentReady(true);
        setDocumentLoaded(
          !displayedDocument.documentUrl && Boolean(displayedDocument.documentContent?.trim()),
        );
      })
      .catch(() => {
        if (!active) return;
        const draftDocument = TERMS_DOCUMENT_CONFIG[registrationType];
        setDocument(draftDocument);
        onDocumentChange(draftDocument);
        setDocumentReady(true);
        setDocumentLoaded(false);
      });

    return () => {
      active = false;
    };
  }, [
    open,
    registrationType,
    onDocumentChange,
  ]);

  useEffect(() => {
    if (
      document &&
      termsAcceptance.decision !== "NONE" &&
      !hasCurrentDisplayedTermsDecision(registrationType, document, termsAcceptance)
    ) {
      resetTermsAcceptance();
    }
  }, [document, registrationType, termsAcceptance, resetTermsAcceptance]);

  function close() {
    setExplicitlyAgreed(false);
    onOpenChange(false);
  }

  function agree() {
    if (
      !document ||
      !documentLoaded ||
      !explicitlyAgreed ||
      !recordDisplayedTermsDecision(document, documentLoaded)
    ) {
      return;
    }
    close();
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen) setExplicitlyAgreed(false);
        onOpenChange(nextOpen);
      }}
      className="auth-terms-dialog"
      onCloseAutoFocus={(event) => {
        event.preventDefault();
        triggerRef.current?.focus();
      }}
      title="Terms & Conditions"
      description="KLOP Next – One Portal"
    >
      <div className="auth-terms-dialog-body">
        <div className="auth-terms-document-area">
          {!documentReady && (
            <p className="auth-terms-document-message" role="status">
              Loading the Terms document…
            </p>
          )}
          {documentReady && document?.documentContent?.trim() && (
            <div
              className="auth-terms-document-viewer auth-terms-document-text-viewer"
              role="region"
              aria-label="Terms document content"
              tabIndex={0}
            >
              <article aria-label={document.title} className="auth-terms-document-text">
                {document.documentContent}
              </article>
            </div>
          )}
          {document?.documentUrl && (
            <TermsPdfViewer
              documentUrl={document.documentUrl}
              documentTitle={document.title}
              onDocumentLoad={handlePdfLoaded}
              onDocumentError={handlePdfError}
            />
          )}
        </div>

        <div className="auth-terms-modal-footer">
          <div className="auth-terms-modal-consent">
            <label className="auth-terms-modal-checkbox">
              <input
                type="checkbox"
                checked={explicitlyAgreed}
                disabled={!documentLoaded}
                onChange={(event) => setExplicitlyAgreed(event.target.checked)}
              />
              <span>
                {isPublishedTermsDocument(document, registrationType)
                  ? "I have read and agree to the Terms & Conditions."
                  : "I acknowledge this draft preview; it is not registration consent."}
              </span>
            </label>
          </div>

          <div className="auth-terms-modal-actions">
            <Button type="button" variant="secondary" onClick={close}>
              Cancel
            </Button>
            <Button
              type="button"
              disabled={!documentLoaded || !explicitlyAgreed}
              onClick={agree}
            >
              I Agree
            </Button>
          </div>
        </div>
      </div>
    </Dialog>
  );
}
