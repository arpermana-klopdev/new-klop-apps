import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { useMutation, useQuery, useQueryClient, type UseQueryResult } from "@tanstack/react-query";
import { resolveApiUrl, toApiRequestError } from "../../api/client";
import {
  archivePlatformLegalDocument,
  decidePlatformLegalDocument,
  getCurrentTerms,
  getPlatformLegalDocumentPermissions,
  getPlatformLegalDocumentPreview,
  getPlatformLegalDocuments,
  publishPlatformLegalDocument,
  submitPlatformLegalDocument,
  updatePlatformLegalDocumentDraft,
  uploadPlatformLegalDocument,
  type LegalDocumentDraftMetadata,
  type PlatformLegalDocument,
  type PlatformLegalDocumentVersion,
} from "../../api/legal";
import type { LegalTermsMetadata } from "../../api/contracts";
import { Button, Dialog, Notice, Skeleton, StatusBadge } from "../../components/ui";
import { TermsPdfViewer } from "../auth/TermsPdfViewer";
import {
  TERMS_DOCUMENT_CONFIG,
  type RegistrationType,
} from "../auth/termsDocuments";
import { SetupSectionPage } from "./PlatformSetupPages";

type ScopeQuery = {
  registrationType: RegistrationType;
  query: UseQueryResult<LegalTermsMetadata, Error>;
};

type PublishedTerms = {
  metadata: LegalTermsMetadata;
  registrationTypes: RegistrationType[];
};

type PreviewDocument = {
  title: string;
  documentUrl: string;
  source: "Published Terms" | "Local draft preview" | "Protected draft preview";
};

type DraftEditorState = {
  legalDocumentId?: string;
  documentVersion?: PlatformLegalDocumentVersion;
  title: string;
  versionIdentifier: string;
  effectiveAtLocal: string;
  personal: boolean;
  organization: boolean;
};

type AdminCommand =
  | { action: "upload"; metadata: LegalDocumentDraftMetadata; file: File; legalDocumentId?: string }
  | { action: "update"; version: PlatformLegalDocumentVersion; metadata: LegalDocumentDraftMetadata }
  | { action: "submit" | "publish" | "archive"; documentVersionId: string }
  | { action: "decide"; documentVersionId: string; decisionCode: "APPROVED" | "REJECTED" };

function isTermsUnavailable(error: unknown) {
  const apiError = toApiRequestError(error);
  return apiError.code === "TERMS_UNAVAILABLE";
}

function getScopeStatus({ registrationType, query }: ScopeQuery) {
  if (query.isPending) return "Checking";
  if (query.data?.registrationType === registrationType) return "Published";
  if (query.data) return "Scope mismatch";
  if (query.isError && isTermsUnavailable(query.error)) return "No published version";
  return "Could not load";
}

export function LegalDocumentsPage() {
  const personalQuery = useQuery({
    queryKey: ["platform-setup", "legal-terms", "PERSONAL"],
    queryFn: () => getCurrentTerms("PERSONAL"),
    retry: false,
    staleTime: 60_000,
  });
  const organizationQuery = useQuery({
    queryKey: ["platform-setup", "legal-terms", "ORGANIZATION"],
    queryFn: () => getCurrentTerms("ORGANIZATION"),
    retry: false,
    staleTime: 60_000,
  });
  const [preview, setPreview] = useState<PreviewDocument | null>(null);
  const [previewLoaded, setPreviewLoaded] = useState(false);
  const [draftEditor, setDraftEditor] = useState<DraftEditorState | null>(null);
  const [draftFile, setDraftFile] = useState<File | null>(null);
  const [adminMessage, setAdminMessage] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const permissionsQuery = useQuery({
    queryKey: ["platform-setup", "legal-document-permissions"],
    queryFn: getPlatformLegalDocumentPermissions,
    retry: false,
  });
  const permissions = permissionsQuery.data?.permissions ?? [];
  const can = (permission: string) => permissions.includes(permission);
  const documentsQuery = useQuery({
    queryKey: ["platform-setup", "legal-documents"],
    queryFn: getPlatformLegalDocuments,
    enabled: can("platform.legal_documents.read"),
    retry: false,
  });
  const adminMutation = useMutation({
    mutationFn: async (command: AdminCommand) => {
      switch (command.action) {
        case "upload":
          return uploadPlatformLegalDocument(command.metadata, command.file, command.legalDocumentId);
        case "update":
          return updatePlatformLegalDocumentDraft(
            command.version.documentVersionId,
            command.metadata,
            command.version.rowVersion,
          );
        case "submit":
          return submitPlatformLegalDocument(command.documentVersionId);
        case "decide":
          return decidePlatformLegalDocument(command.documentVersionId, command.decisionCode);
        case "publish":
          return publishPlatformLegalDocument(command.documentVersionId);
        case "archive":
          return archivePlatformLegalDocument(command.documentVersionId);
      }
    },
    onSuccess: async (_, command) => {
      setAdminMessage("Legal document update completed.");
      if (command.action === "upload" || command.action === "update") {
        setDraftEditor(null);
        setDraftFile(null);
      }
      await queryClient.invalidateQueries({ queryKey: ["platform-setup", "legal-documents"] });
    },
    onError: (error: unknown) => setAdminMessage(toApiRequestError(error).message),
  });

  const scopeQueries: ScopeQuery[] = [
    { registrationType: "PERSONAL", query: personalQuery },
    { registrationType: "ORGANIZATION", query: organizationQuery },
  ];
  const publishedTerms = useMemo(() => {
    const termsByVersion = new Map<string, PublishedTerms>();
    for (const { registrationType, query } of scopeQueries) {
      const metadata = query.data;
      if (!metadata || metadata.registrationType !== registrationType) continue;
      const existing = termsByVersion.get(metadata.documentVersionId);
      if (existing) {
        if (!existing.registrationTypes.includes(registrationType)) {
          existing.registrationTypes.push(registrationType);
        }
      } else {
        termsByVersion.set(metadata.documentVersionId, {
          metadata,
          registrationTypes: [registrationType],
        });
      }
    }
    return [...termsByVersion.values()];
  }, [personalQuery.data, organizationQuery.data]);

  const onPreviewLoaded = useCallback(() => setPreviewLoaded(true), []);
  const onPreviewError = useCallback(() => setPreviewLoaded(false), []);
  useEffect(() => () => {
    if (preview?.documentUrl.startsWith("blob:")) URL.revokeObjectURL(preview.documentUrl);
  }, [preview]);

  function openPreview(document: PreviewDocument) {
    setPreviewLoaded(false);
    setPreview(document);
  }

  function closePreview() {
    setPreviewLoaded(false);
    setPreview(null);
  }

  function startDraftEditor(document?: PlatformLegalDocument, version?: PlatformLegalDocumentVersion) {
    const now = new Date();
    now.setMinutes(now.getMinutes() - now.getTimezoneOffset());
    setDraftEditor({
      legalDocumentId: document?.legalDocumentId,
      documentVersion: version,
      title: version?.title ?? "Terms & Conditions",
      versionIdentifier: "",
      effectiveAtLocal: now.toISOString().slice(0, 16),
      personal: version ? version.registrationScopes.includes("PERSONAL") : true,
      organization: version ? version.registrationScopes.includes("ORGANIZATION") : true,
    });
    setDraftFile(null);
    setAdminMessage(null);
  }

  function updateDraftField<K extends keyof DraftEditorState>(field: K, value: DraftEditorState[K]) {
    setDraftEditor((current) => current ? { ...current, [field]: value } : current);
  }

  function submitDraftEditor(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!draftEditor) return;
    if (!draftEditor.title.trim() || !draftEditor.versionIdentifier.trim() ||
      !draftEditor.effectiveAtLocal || (!draftEditor.personal && !draftEditor.organization) ||
      (!draftEditor.documentVersion && (!draftFile || draftFile.type !== "application/pdf"))) {
      setAdminMessage("Complete the required metadata, scope, and PDF fields.");
      return;
    }
    const effectiveDate = new Date(draftEditor.effectiveAtLocal);
    if (Number.isNaN(effectiveDate.getTime())) {
      setAdminMessage("Enter a valid effective date and time.");
      return;
    }
    const registrationTypes = [
      ...(draftEditor.personal ? ["PERSONAL" as const] : []),
      ...(draftEditor.organization ? ["ORGANIZATION" as const] : []),
    ];
    const metadata: LegalDocumentDraftMetadata = {
      title: draftEditor.title,
      versionIdentifier: draftEditor.versionIdentifier,
      effectiveAtUtc: effectiveDate.toISOString(),
      registrationTypes,
    };
    if (draftEditor.documentVersion) {
      adminMutation.mutate({ action: "update", version: draftEditor.documentVersion, metadata });
    } else if (draftFile) {
      adminMutation.mutate({
        action: "upload",
        metadata,
        file: draftFile,
        legalDocumentId: draftEditor.legalDocumentId,
      });
    }
  }

  async function openProtectedPreview(version: PlatformLegalDocumentVersion) {
    try {
      setAdminMessage(null);
      const pdf = await getPlatformLegalDocumentPreview(version.documentVersionId);
      openPreview({
        title: version.title,
        documentUrl: URL.createObjectURL(pdf),
        source: "Protected draft preview",
      });
    } catch (error) {
      setAdminMessage(toApiRequestError(error).message);
    }
  }

  const draftConfig = TERMS_DOCUMENT_CONFIG.PERSONAL;
  const draftDocumentUrl = draftConfig.documentUrl;
  const draftAvailable = Boolean(draftDocumentUrl);

  return (
    <>
      <SetupSectionPage
        title="Legal Documents"
        description="Published Terms use the existing public API. Protected draft management and approval require explicit PLATFORM permissions."
        status={can("platform.legal_documents.read") ? "Administration enabled" : "Read only"}
      >
        <section aria-labelledby="legal-current-status-heading">
          <div className="mb-4">
            <h2 id="legal-current-status-heading" className="text-sm font-semibold">Current Terms by registration scope</h2>
            <p className="mt-1 text-xs text-slate-500">
              Source: GET /api/v1/public/legal/terms/current
            </p>
          </div>
          <dl className="divide-y divide-slate-100 rounded-xl border border-slate-200 px-4 dark:divide-slate-800 dark:border-slate-800">
            {scopeQueries.map((scope) => (
              <div
                key={scope.registrationType}
                className="flex flex-wrap items-center justify-between gap-3 py-3"
              >
                <dt className="text-sm font-medium">{scope.registrationType}</dt>
                <dd className="flex items-center gap-2">
                  <StatusBadge value={getScopeStatus(scope)} />
                  {scope.query.isError && !isTermsUnavailable(scope.query.error) && (
                    <span className="sr-only">
                      {toApiRequestError(scope.query.error).message}
                    </span>
                  )}
                </dd>
              </div>
            ))}
          </dl>
          {(personalQuery.isPending || organizationQuery.isPending) && (
            <div className="mt-4" role="status" aria-label="Loading current Terms metadata">
              <Skeleton className="h-10" />
            </div>
          )}
          {scopeQueries.some(
            (scope) => scope.query.isError && !isTermsUnavailable(scope.query.error),
          ) && (
            <div className="mt-4">
              <Notice kind="info">
                Current Terms metadata could not be fully loaded from the API. Retry the affected request before treating the document status as unavailable.
              </Notice>
              <div className="mt-3 flex flex-wrap gap-2">
                {personalQuery.isError && !isTermsUnavailable(personalQuery.error) && (
                  <Button size="sm" variant="secondary" onClick={() => void personalQuery.refetch()}>
                    Retry PERSONAL
                  </Button>
                )}
                {organizationQuery.isError && !isTermsUnavailable(organizationQuery.error) && (
                  <Button size="sm" variant="secondary" onClick={() => void organizationQuery.refetch()}>
                    Retry ORGANIZATION
                  </Button>
                )}
              </div>
            </div>
          )}
          {scopeQueries.some(
            (scope) => scope.query.data && scope.query.data.registrationType !== scope.registrationType,
          ) && (
            <div className="mt-4">
              <Notice>
                Terms metadata returned for a different registration scope is not treated as current or consent-eligible.
              </Notice>
            </div>
          )}
        </section>

        <section aria-labelledby="legal-published-versions-heading" className="mt-7 border-t border-slate-100 pt-6 dark:border-slate-800">
          <div className="mb-4">
            <h2 id="legal-published-versions-heading" className="text-sm font-semibold">Published document details</h2>
            <p className="mt-1 text-xs text-slate-500">Versions are grouped by their actual backend document version ID.</p>
          </div>
          {publishedTerms.length === 0 ? (
            <p className="rounded-xl border border-dashed border-slate-300 px-4 py-6 text-center text-sm text-slate-500 dark:border-slate-700">
              No published Terms version was returned for either registration scope.
            </p>
          ) : (
            <ul className="space-y-3">
              {publishedTerms.map(({ metadata, registrationTypes: scopes }) => (
                <li
                  key={metadata.documentVersionId}
                  className="rounded-xl border border-slate-200 p-4 dark:border-slate-800"
                >
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <h3 className="text-sm font-semibold">{metadata.title}</h3>
                      <p className="mt-1 text-xs text-slate-500">Version {metadata.version}</p>
                    </div>
                    <StatusBadge value={metadata.publicationStatus} />
                  </div>
                  <dl className="mt-4 grid gap-3 text-xs sm:grid-cols-2">
                    <div>
                      <dt className="text-slate-500">Effective date</dt>
                      <dd className="mt-1 font-medium">{new Date(metadata.effectiveAtUtc).toLocaleString()}</dd>
                    </div>
                    <div>
                      <dt className="text-slate-500">Registration scopes</dt>
                      <dd className="mt-1 font-medium">{scopes.join(", ")}</dd>
                    </div>
                    <div className="sm:col-span-2">
                      <dt className="text-slate-500">Document version ID</dt>
                      <dd className="mt-1 break-all font-mono">{metadata.documentVersionId}</dd>
                    </div>
                  </dl>
                  <Button
                    className="mt-4"
                    size="sm"
                    variant="secondary"
                    disabled={!metadata.documentUrl}
                    onClick={() =>
                      openPreview({
                        title: metadata.title,
                        documentUrl: resolveApiUrl(metadata.documentUrl),
                        source: "Published Terms",
                      })
                    }
                  >
                    Preview published PDF
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section aria-labelledby="legal-draft-preview-heading" className="mt-7 border-t border-slate-100 pt-6 dark:border-slate-800">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <h2 id="legal-draft-preview-heading" className="text-sm font-semibold">Existing local PDF</h2>
              <p className="mt-1 max-w-2xl text-xs leading-5 text-slate-500">
                The local file is a draft preview only. It is not shown as a registered, approved, published, or consent-eligible backend document.
              </p>
            </div>
            <Button
              size="sm"
              variant="secondary"
              disabled={!draftAvailable}
              onClick={() => {
                if (!draftDocumentUrl) return;
                openPreview({
                  title: "Terms & Conditions draft preview",
                  documentUrl: draftDocumentUrl,
                  source: "Local draft preview",
                });
              }}
            >
              Preview local draft PDF
            </Button>
          </div>
        </section>

        <section aria-labelledby="legal-management-status-heading" className="mt-7 border-t border-slate-100 pt-6 dark:border-slate-800">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 id="legal-management-status-heading" className="text-sm font-semibold">Document administration</h2>
              <p className="mt-1 text-xs text-slate-500">
                Platform-scoped permissions are checked by the API for every administrative operation.
              </p>
            </div>
            {can("platform.legal_documents.read") && <StatusBadge value="Protected API" />}
          </div>

          {permissionsQuery.isPending && (
            <div role="status" aria-label="Checking legal document permissions"><Skeleton className="h-10" /></div>
          )}
          {permissionsQuery.isError && (
            <Notice kind="info">
              {toApiRequestError(permissionsQuery.error).status === 404
                ? "Protected legal-document administration is not enabled on this backend."
                : toApiRequestError(permissionsQuery.error).message}
            </Notice>
          )}
          {permissionsQuery.data && !can("platform.legal_documents.read") && (
            <Notice>
              Legal document administration is available only to authenticated users with explicit PLATFORM permissions.
            </Notice>
          )}

          {can("platform.legal_documents.read") && (
            <>
              {can("platform.legal_documents.draft.create") && (
                <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
                  <p className="text-xs text-slate-500">Create a new draft or upload a replacement as a new version.</p>
                  <Button size="sm" onClick={() => startDraftEditor()}>Create draft</Button>
                </div>
              )}
              {adminMessage && (
                <div className="mb-4" role="status">
                  <Notice kind={adminMutation.isError ? "info" : "success"}>{adminMessage}</Notice>
                </div>
              )}
              {draftEditor && (
                <form
                  className="mb-5 space-y-3 rounded-xl border border-slate-200 p-4 dark:border-slate-800"
                  onSubmit={submitDraftEditor}
                  noValidate
                >
                  <div className="flex items-center justify-between gap-3">
                    <h3 className="text-sm font-semibold">
                      {draftEditor.documentVersion
                        ? "Edit draft metadata"
                        : draftEditor.legalDocumentId ? "Upload replacement version" : "New legal document draft"}
                    </h3>
                    <Button type="button" size="sm" variant="secondary" onClick={() => setDraftEditor(null)}>
                      Cancel
                    </Button>
                  </div>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <label className="text-xs font-medium">
                      Title
                      <input
                        required
                        maxLength={300}
                        value={draftEditor.title}
                        onChange={(event) => updateDraftField("title", event.target.value)}
                        className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950"
                      />
                    </label>
                    <label className="text-xs font-medium">
                      Version
                      <input
                        required
                        maxLength={50}
                        value={draftEditor.versionIdentifier}
                        onChange={(event) => updateDraftField("versionIdentifier", event.target.value)}
                        className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950"
                      />
                    </label>
                    <label className="text-xs font-medium">
                      Effective date and time
                      <input
                        required
                        type="datetime-local"
                        value={draftEditor.effectiveAtLocal}
                        onChange={(event) => updateDraftField("effectiveAtLocal", event.target.value)}
                        className="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950"
                      />
                    </label>
                    <fieldset className="text-xs">
                      <legend className="font-medium">Registration scopes</legend>
                      <div className="mt-2 flex gap-4">
                        <label className="inline-flex items-center gap-2">
                          <input
                            type="checkbox"
                            checked={draftEditor.personal}
                            onChange={(event) => updateDraftField("personal", event.target.checked)}
                          />
                          PERSONAL
                        </label>
                        <label className="inline-flex items-center gap-2">
                          <input
                            type="checkbox"
                            checked={draftEditor.organization}
                            onChange={(event) => updateDraftField("organization", event.target.checked)}
                          />
                          ORGANIZATION
                        </label>
                      </div>
                    </fieldset>
                  </div>
                  {!draftEditor.documentVersion && (
                    <label className="block text-xs font-medium">
                      PDF document
                      <input
                        required
                        type="file"
                        accept="application/pdf,.pdf"
                        onChange={(event) => setDraftFile(event.target.files?.[0] ?? null)}
                        className="mt-1 block w-full text-sm"
                      />
                    </label>
                  )}
                  <p className="text-xs text-slate-500">
                    Uploads are stored privately and checked for PDF signature, size, and SHA-256 integrity.
                  </p>
                  <Button
                    type="submit"
                    size="sm"
                    disabled={adminMutation.isPending || (!draftEditor.personal && !draftEditor.organization) ||
                      (!draftEditor.documentVersion && !draftFile)}
                  >
                    {adminMutation.isPending ? "Saving…" : draftEditor.documentVersion ? "Save draft" : "Upload draft"}
                  </Button>
                </form>
              )}

              {documentsQuery.isPending && <div role="status" aria-label="Loading legal documents"><Skeleton className="h-16" /></div>}
              {documentsQuery.isError && (
                <Notice kind="info">{toApiRequestError(documentsQuery.error).message}</Notice>
              )}
              {documentsQuery.data?.length === 0 && (
                <p className="rounded-xl border border-dashed border-slate-300 px-4 py-6 text-center text-sm text-slate-500 dark:border-slate-700">
                  No legal document drafts or versions are registered yet.
                </p>
              )}
              <div className="space-y-4">
                {documentsQuery.data?.map((document) => (
                  <article key={document.legalDocumentId} className="rounded-xl border border-slate-200 p-4 dark:border-slate-800">
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <h3 className="text-sm font-semibold">Terms &amp; Conditions</h3>
                        <p className="mt-1 break-all font-mono text-[11px] text-slate-500">{document.legalDocumentId}</p>
                      </div>
                      {can("platform.legal_documents.draft.create") && (
                        <Button size="sm" variant="secondary" onClick={() => startDraftEditor(document)}>
                          Upload new version
                        </Button>
                      )}
                    </div>
                    <ul className="mt-4 space-y-3">
                      {document.versions.map((version) => (
                        <li key={version.documentVersionId} className="rounded-lg bg-slate-50 p-3 dark:bg-slate-900">
                          <div className="flex flex-wrap items-start justify-between gap-3">
                            <div>
                              <p className="text-sm font-medium">{version.title} · {version.versionIdentifier}</p>
                              <p className="mt-1 text-xs text-slate-500">
                                Effective {new Date(version.effectiveAtUtc).toLocaleString()} · {version.registrationScopes.join(", ")} · {(version.fileSizeBytes / 1024).toFixed(1)} KB
                              </p>
                              <p className="mt-1 text-xs text-slate-500">
                                Version ID: <span className="break-all font-mono">{version.documentVersionId}</span>
                              </p>
                              {version.latestApprovalDecisionNote && (
                                <p className="mt-1 text-xs text-slate-500">Decision note: {version.latestApprovalDecisionNote}</p>
                              )}
                            </div>
                            <StatusBadge value={version.publicationStatus} />
                          </div>
                          <div className="mt-3 flex flex-wrap gap-2">
                            {can("platform.legal_documents.draft.preview") &&
                              ["DRAFT", "PENDING_APPROVAL", "APPROVED"].includes(version.publicationStatus) && (
                                <Button size="sm" variant="secondary" onClick={() => void openProtectedPreview(version)}>
                                  Preview PDF
                                </Button>
                              )}
                            {version.publicationStatus === "DRAFT" && can("platform.legal_documents.draft.edit") && (
                              <Button size="sm" variant="secondary" onClick={() => startDraftEditor(document, version)}>
                                Edit draft
                              </Button>
                            )}
                            {version.publicationStatus === "DRAFT" && can("platform.legal_documents.submit") && (
                              <Button
                                size="sm"
                                disabled={adminMutation.isPending}
                                onClick={() => adminMutation.mutate({ action: "submit", documentVersionId: version.documentVersionId })}
                              >
                                Submit for approval
                              </Button>
                            )}
                            {version.publicationStatus === "PENDING_APPROVAL" && can("platform.legal_documents.approve") && (
                              <>
                                <Button
                                  size="sm"
                                  disabled={adminMutation.isPending}
                                  onClick={() => adminMutation.mutate({ action: "decide", documentVersionId: version.documentVersionId, decisionCode: "APPROVED" })}
                                >
                                  Approve
                                </Button>
                                <Button
                                  size="sm"
                                  variant="secondary"
                                  disabled={adminMutation.isPending}
                                  onClick={() => adminMutation.mutate({ action: "decide", documentVersionId: version.documentVersionId, decisionCode: "REJECTED" })}
                                >
                                  Reject
                                </Button>
                              </>
                            )}
                            {version.publicationStatus === "APPROVED" && can("platform.legal_documents.publish") && (
                              <Button
                                size="sm"
                                disabled={adminMutation.isPending}
                                onClick={() => adminMutation.mutate({ action: "publish", documentVersionId: version.documentVersionId })}
                              >
                                Publish
                              </Button>
                            )}
                            {version.publicationStatus === "PUBLISHED" && can("platform.legal_documents.archive") && (
                              <Button
                                size="sm"
                                variant="secondary"
                                disabled={adminMutation.isPending}
                                onClick={() => adminMutation.mutate({ action: "archive", documentVersionId: version.documentVersionId })}
                              >
                                Archive
                              </Button>
                            )}
                          </div>
                        </li>
                      ))}
                    </ul>
                  </article>
                ))}
              </div>
            </>
          )}
        </section>
      </SetupSectionPage>

      <Dialog
        open={preview !== null}
        onOpenChange={(open) => {
          if (!open) closePreview();
        }}
        className="auth-terms-dialog"
        title={preview?.title ?? "Legal document preview"}
        description={preview?.source ?? "PDF preview"}
      >
        {preview && (
          <div className="auth-terms-dialog-body">
            <div className="auth-terms-document-area">
              <TermsPdfViewer
                documentUrl={preview.documentUrl}
                documentTitle={preview.title}
                onDocumentLoad={onPreviewLoaded}
                onDocumentError={onPreviewError}
              />
            </div>
            <div className="auth-terms-modal-footer">
              <p className="text-xs text-slate-500">
                {previewLoaded
                  ? `${preview.source} · Read only · No consent is recorded`
                  : `${preview.source} · Read-only PDF preview · No consent is recorded`}
              </p>
              <div className="auth-terms-modal-actions">
                <Button type="button" variant="secondary" onClick={closePreview}>
                  Close
                </Button>
              </div>
            </div>
          </div>
        )}
      </Dialog>
    </>
  );
}
