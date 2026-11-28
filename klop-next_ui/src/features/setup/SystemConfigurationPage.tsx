import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import {
  applySystemConfigurationRequest,
  cancelSystemConfigurationRequest,
  createSystemConfigurationDraft,
  decideSystemConfigurationRequest,
  getSystemConfigurationApprovals,
  getSystemConfigurationCatalog,
  getSystemConfigurationHistory,
  getSystemConfigurationPermissions,
  getSystemConfigurationRequests,
  submitSystemConfigurationDraft,
  updateSystemConfigurationDraft,
} from "../../api/systemConfiguration";
import { toApiRequestError } from "../../api/client";
import type {
  SystemConfigurationCatalogItem,
  SystemConfigurationDecisionRequest,
  SystemConfigurationDraftRequest,
  SystemConfigurationDraftUpdate,
  SystemConfigurationRequestItem,
} from "../../api/contracts";
import { Button, Notice, PageHeading, Skeleton, StatusBadge } from "../../components/ui";
import { Link } from "react-router-dom";

type View = "catalog" | "requests" | "approvals" | "history";

const reasons = ["ROUTINE_MAINTENANCE", "CAPACITY_ADJUSTMENT", "INCIDENT_FOLLOWUP"] as const;
const views: { id: View; label: string }[] = [
  { id: "catalog", label: "Catalog" },
  { id: "requests", label: "Change Requests" },
  { id: "approvals", label: "Approvals" },
  { id: "history", label: "History" },
];

export function SystemConfigurationPage() {
  const [view, setView] = useState<View>("catalog");
  const [category, setCategory] = useState("");
  const [search, setSearch] = useState("");
  const [pageNumber, setPageNumber] = useState(1);
  const [selectedConfig, setSelectedConfig] = useState<SystemConfigurationCatalogItem | null>(null);
  const [selectedDraft, setSelectedDraft] = useState<SystemConfigurationRequestItem | null>(null);
  const [proposedInteger, setProposedInteger] = useState("");
  const [reasonCode, setReasonCode] = useState<(typeof reasons)[number]>(reasons[0]);
  const queryClient = useQueryClient();
  const access = useQuery({
    queryKey: ["platform-system-configuration", "permissions"],
    queryFn: getSystemConfigurationPermissions,
    staleTime: 0,
    refetchOnMount: "always",
    retry: false,
  });
  const canRead = access.isSuccess && !access.isFetching && access.data.canRead;
  const catalog = useQuery({
    queryKey: ["platform-system-configuration", "catalog", category, pageNumber],
    queryFn: () => getSystemConfigurationCatalog({
      category: category || undefined,
      pageNumber,
      pageSize: 25,
    }),
    enabled: canRead && view === "catalog",
    retry: false,
  });
  const requests = useQuery({
    queryKey: ["platform-system-configuration", "requests", pageNumber],
    queryFn: () => getSystemConfigurationRequests("ALL", pageNumber),
    enabled: canRead && view === "requests",
    retry: false,
  });
  const approvals = useQuery({
    queryKey: ["platform-system-configuration", "approvals", pageNumber],
    queryFn: () => getSystemConfigurationApprovals(pageNumber),
    enabled: canRead && access.data?.canApprove === true && view === "approvals",
    retry: false,
  });
  const history = useQuery({
    queryKey: ["platform-system-configuration", "history", pageNumber],
    queryFn: () => getSystemConfigurationHistory(pageNumber),
    enabled: canRead && access.data?.canReadHistory === true && view === "history",
    retry: false,
  });
  const mutation = useMutation({
    mutationFn: (operation: () => Promise<unknown>) => operation(),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["platform-system-configuration"] });
      setSelectedConfig(null);
      setSelectedDraft(null);
      setProposedInteger("");
    },
  });

  const authorizedViews = views.filter(({ id }) =>
    id !== "approvals" || access.data?.canApprove === true,
  ).filter(({ id }) =>
    id !== "history" || access.data?.canReadHistory === true,
  );
  const error = mutation.isError ? toApiRequestError(mutation.error) : null;

  function chooseView(next: View) {
    setView(next);
    setPageNumber(1);
    setSelectedConfig(null);
    setSelectedDraft(null);
  }

  function createDraft(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedConfig || selectedConfig.configurationKey !== "database.command_timeout_seconds" ||
        !selectedConfig.isEditable || !selectedConfig.versionNumber || !selectedConfig.concurrencyVersion)
      return;
    const value = Number(proposedInteger);
    if (!Number.isInteger(value) || value < (selectedConfig.minimum ?? 1) ||
        value > (selectedConfig.maximum ?? 120)) return;
    const request: SystemConfigurationDraftRequest = {
      configurationKey: selectedConfig.configurationKey,
      proposedInteger: value,
      expectedVersionNumber: selectedConfig.versionNumber,
      targetConcurrencyVersion: selectedConfig.concurrencyVersion,
      reasonCode,
    };
    mutation.mutate(() => createSystemConfigurationDraft(request));
  }

  function editDraft(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedDraft?.requestConcurrencyVersion) return;
    const value = Number(proposedInteger);
    if (!Number.isInteger(value) || value < 1 || value > 120) return;
    const request: SystemConfigurationDraftUpdate = {
      proposedInteger: value,
      reasonCode,
      requestConcurrencyVersion: selectedDraft.requestConcurrencyVersion,
    };
    mutation.mutate(() => updateSystemConfigurationDraft(selectedDraft.requestId, request));
  }

  function transitionRequest(item: SystemConfigurationRequestItem, action: "submit" | "cancel" | "apply") {
    if (!item.requestConcurrencyVersion) return;
    const request = { requestConcurrencyVersion: item.requestConcurrencyVersion };
    const operation = action === "submit"
      ? () => submitSystemConfigurationDraft(item.requestId, request)
      : action === "cancel"
        ? () => cancelSystemConfigurationRequest(item.requestId, request)
        : () => applySystemConfigurationRequest(item.requestId, request);
    mutation.mutate(operation);
  }

  function decideRequest(item: SystemConfigurationRequestItem, decision: "APPROVE" | "REJECT") {
    if (!item.requestConcurrencyVersion) return;
    const request: SystemConfigurationDecisionRequest = {
      decision,
      requestConcurrencyVersion: item.requestConcurrencyVersion,
    };
    mutation.mutate(() => decideSystemConfigurationRequest(item.requestId, request));
  }

  return (
    <>
      <PageHeading
        eyebrow="Platform administration / Platform Setup"
        title="System Configuration"
        description="Protected metadata catalog and separately authorized change workflow. Persisted configuration is distinct from startup in-memory runtime settings."
        action={<Link to="/platform-setup"><Button variant="secondary">Platform Setup</Button></Link>}
      />
      <nav aria-label="Platform Setup sections" className="mb-6 flex flex-wrap gap-2">
        <Link className="rounded-full border border-slate-200 px-3 py-1.5 text-xs" to="/platform-setup">Platform Setup</Link>
        <span aria-current="page" className="rounded-full border border-brand-300 px-3 py-1.5 text-xs">System Configuration</span>
      </nav>
      <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-sm font-bold">Protected configuration catalog</h2>
            <p className="mt-1 text-xs text-slate-500">Values are not read or displayed. Startup runtime values are not hot-reloaded.</p>
          </div>
          <StatusBadge value="Management policy HOLD by default" />
        </div>
        {access.isPending || access.isFetching ? (
          <div role="status" aria-label="Checking configuration permissions"><Skeleton className="h-20" /></div>
        ) : access.isError ? (
          <Notice>Configuration capability could not be verified. {toApiRequestError(access.error).message}</Notice>
        ) : !access.data.canRead ? (
          <Notice>You do not have permission to read the protected configuration catalog.</Notice>
        ) : (
          <>
            <div role="tablist" aria-label="Configuration management views" className="mb-5 flex flex-wrap gap-2 border-b border-slate-200 dark:border-slate-700">
              {authorizedViews.map((item) => (
                <button key={item.id} id={`configuration-tab-${item.id}`} type="button" role="tab"
                  aria-selected={view === item.id} aria-controls={`configuration-panel-${item.id}`}
                  tabIndex={view === item.id ? 0 : -1}
                  className="border-b-2 px-3 py-2 text-sm font-medium aria-selected:border-brand-600 aria-selected:text-brand-700 dark:aria-selected:text-brand-300"
                  onClick={() => chooseView(item.id)}>{item.label}</button>
              ))}
            </div>
            <div id={`configuration-panel-${view}`} role="tabpanel"
              aria-labelledby={`configuration-tab-${view}`} tabIndex={0}>
              {view === "catalog" && (
                <CatalogView query={catalog} category={category} search={search}
                  onCategory={(value) => { setCategory(value); setPageNumber(1); }}
                  onSearch={(value) => { setSearch(value); setPageNumber(1); }}
                  pageNumber={pageNumber} onPage={setPageNumber}
                  canCreate={access.data.canCreateRequest}
                  selectedConfig={selectedConfig} onSelect={setSelectedConfig}
                  proposedInteger={proposedInteger} onValue={setProposedInteger}
                  reasonCode={reasonCode} onReason={setReasonCode}
                  onCreate={createDraft} busy={mutation.isPending} />
              )}
              {view === "requests" && (
                <RequestsView query={requests} pageNumber={pageNumber} onPage={setPageNumber}
                  access={access.data} selectedDraft={selectedDraft} onSelectDraft={setSelectedDraft}
                  proposedInteger={proposedInteger} onValue={setProposedInteger}
                  reasonCode={reasonCode} onReason={setReasonCode} onEdit={editDraft}
                  onTransition={transitionRequest} busy={mutation.isPending} />
              )}
              {view === "approvals" && (
                <RequestsView query={approvals} pageNumber={pageNumber} onPage={setPageNumber}
                  access={access.data} approvals onDecision={decideRequest} busy={mutation.isPending} />
              )}
              {view === "history" && (
                <HistoryView query={history} pageNumber={pageNumber} onPage={setPageNumber} />
              )}
            </div>
            {error && <div className="mt-4"><Notice>{error.message}</Notice></div>}
            <div className="mt-5">
              <Notice kind="info">
                Persisted SQL metadata does not represent the process’s startup-loaded runtime value. Any future approved apply is separate, never auto-restarts the service, and remains pending restart until an owner-authorized operation.
              </Notice>
            </div>
          </>
        )}
      </section>
    </>
  );
}

function CatalogView({
  query, category, search, onCategory, onSearch, pageNumber, onPage, canCreate,
  selectedConfig, onSelect, proposedInteger, onValue, reasonCode, onReason, onCreate, busy,
}: {
  query: ReturnType<typeof useQuery<Awaited<ReturnType<typeof getSystemConfigurationCatalog>>>>;
  category: string;
  search: string;
  onCategory: (value: string) => void;
  onSearch: (value: string) => void;
  pageNumber: number;
  onPage: (value: number) => void;
  canCreate: boolean;
  selectedConfig: SystemConfigurationCatalogItem | null;
  onSelect: (item: SystemConfigurationCatalogItem | null) => void;
  proposedInteger: string;
  onValue: (value: string) => void;
  reasonCode: (typeof reasons)[number];
  onReason: (value: (typeof reasons)[number]) => void;
  onCreate: (event: FormEvent<HTMLFormElement>) => void;
  busy: boolean;
}) {
  const rows = query.data?.items;
  const options = [...new Set(rows?.map((row) => row.category) ?? [])].sort();
  const searchTerm = search.trim().toLocaleLowerCase();
  const visibleRows = (rows ?? []).filter((row) =>
    [row.configurationKey, row.category, row.valueType, row.storageType]
      .some((value) => value.toLocaleLowerCase().includes(searchTerm)),
  );
  return (
    <div>
      <div className="mb-4 flex flex-wrap items-end gap-3">
        <label className="text-xs font-medium">Search approved keys
          <input value={search} onChange={(event) => onSearch(event.target.value)} maxLength={100}
            className="mt-1 block rounded-lg border border-slate-300 bg-transparent px-3 py-2 text-sm dark:border-slate-600" />
        </label>
        <label className="text-xs font-medium">Category
          <select value={category} onChange={(event) => onCategory(event.target.value)}
            className="mt-1 block rounded-lg border border-slate-300 bg-transparent px-3 py-2 text-sm dark:border-slate-600">
            <option value="">All categories</option>
            {options.map((option) => <option key={option} value={option}>{option}</option>)}
          </select>
        </label>
        {query.data && <p className="text-xs text-slate-500">Unclassified keys withheld: {query.data.unclassifiedCount}</p>}
      </div>
      {query.isPending || query.isFetching ? (
        <div role="status" aria-label="Loading configuration catalog"><Skeleton className="h-28" /></div>
      ) : query.isError ? (
        <Notice>The configuration catalog could not be loaded. {toApiRequestError(query.error).message}</Notice>
      ) : !rows?.length ? (
        <p className="py-5 text-sm text-slate-500">No approved catalog metadata matches these filters.</p>
      ) : !visibleRows.length ? (
        <p className="py-5 text-sm text-slate-500">No approved catalog metadata matches this local search.</p>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="min-w-full text-left text-sm">
              <caption className="sr-only">Allowlisted configuration metadata; persisted values are withheld.</caption>
              <thead><tr className="border-b border-slate-200 text-xs text-slate-500 dark:border-slate-700">
                <th scope="col" className="p-2">Approved key</th><th scope="col" className="p-2">Category / type</th>
                <th scope="col" className="p-2">Readiness</th><th scope="col" className="p-2">Management</th>
                <th scope="col" className="p-2">Version / restart</th><th scope="col" className="p-2">Safe bounds</th>
                <th scope="col" className="p-2">Action</th></tr></thead>
              <tbody>
                {visibleRows.map((row) => (
                  <tr key={row.configurationKey} className="border-b border-slate-100 dark:border-slate-800">
                    <th scope="row" className="p-2 font-mono text-xs">{row.configurationKey}</th>
                    <td className="p-2">{row.category} · {row.valueType} / {row.storageType}</td>
                    <td className="p-2"><StatusBadge value={row.readiness} /></td>
                    <td className="p-2"><StatusBadge value={row.isEditable ? row.managementStatus : "HOLD"} /></td>
                    <td className="p-2">{row.versionNumber ?? "—"} · {row.requiresRestart ? "Restart required" : "No restart flag"}</td>
                    <td className="p-2">{row.minimum ?? "—"}{row.maximum !== null ? `–${row.maximum}` : ""}</td>
                    <td className="p-2">
                      {canCreate && row.isEditable ? (
                        <Button size="sm" variant="secondary" onClick={() => {
                          onSelect(row);
                          onValue("");
                        }}>Request change</Button>
                      ) : <span className="text-xs text-slate-500">Metadata only</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-2 text-xs text-slate-500">Showing {visibleRows.length} safe catalog entries. Search stays in this page and is not sent to the API.</p>
          {selectedConfig && canCreate && selectedConfig.isEditable && (
            <form className="mt-5 grid gap-3 rounded-xl border border-slate-200 p-4 sm:grid-cols-4 dark:border-slate-700"
              aria-label={`Create request for ${selectedConfig.configurationKey}`} onSubmit={onCreate}>
              <p className="text-sm font-semibold sm:col-span-4">Draft proposed change: {selectedConfig.configurationKey}</p>
              <label className="text-xs font-medium">Proposed integer
                <input type="number" min={selectedConfig.minimum ?? 1} max={selectedConfig.maximum ?? 120}
                  step="1" required value={proposedInteger} onChange={(event) => onValue(event.target.value)}
                  className="mt-1 block w-full rounded-lg border border-slate-300 bg-transparent px-3 py-2 text-sm" />
              </label>
              <ReasonSelect value={reasonCode} onChange={onReason} />
              <div className="flex items-end gap-2">
                <Button type="submit" disabled={busy || !selectedConfig.versionNumber || !selectedConfig.concurrencyVersion}>Create draft</Button>
                <Button type="button" variant="secondary" onClick={() => onSelect(null)}>Close</Button>
              </div>
            </form>
          )}
          <Pagination pageNumber={pageNumber} pageSize={query.data.pageSize} totalCount={query.data.totalCount} onPage={onPage} />
        </>
      )}
    </div>
  );
}

function RequestsView({
  query, pageNumber, onPage, access, approvals = false, selectedDraft, onSelectDraft,
  proposedInteger, onValue, reasonCode, onReason, onEdit, onTransition, onDecision, busy,
}: {
  query: ReturnType<typeof useQuery<Awaited<ReturnType<typeof getSystemConfigurationRequests>>>>;
  pageNumber: number;
  onPage: (value: number) => void;
  access: Awaited<ReturnType<typeof getSystemConfigurationPermissions>>;
  approvals?: boolean;
  selectedDraft?: SystemConfigurationRequestItem | null;
  onSelectDraft?: (item: SystemConfigurationRequestItem | null) => void;
  proposedInteger?: string;
  onValue?: (value: string) => void;
  reasonCode?: (typeof reasons)[number];
  onReason?: (value: (typeof reasons)[number]) => void;
  onEdit?: (event: FormEvent<HTMLFormElement>) => void;
  onTransition?: (item: SystemConfigurationRequestItem, action: "submit" | "cancel" | "apply") => void;
  onDecision?: (item: SystemConfigurationRequestItem, decision: "APPROVE" | "REJECT") => void;
  busy: boolean;
}) {
  const rows = query.data?.items;
  return query.isPending || query.isFetching ? (
    <div role="status" aria-label={`Loading ${approvals ? "approvals" : "change requests"}`}><Skeleton className="h-28" /></div>
  ) : query.isError ? (
    <Notice>{approvals ? "Approval queue" : "Change requests"} could not be loaded. {toApiRequestError(query.error).message}</Notice>
  ) : !rows?.length ? (
    <p className="py-5 text-sm text-slate-500">{approvals ? "No requests are awaiting approval." : "No configuration change requests were returned."}</p>
  ) : (
    <>
      <div className="overflow-x-auto">
        <table className="min-w-full text-left text-sm">
          <caption className="sr-only">Safe configuration request metadata. Proposed values are allowlisted integers only.</caption>
          <thead><tr className="border-b border-slate-200 text-xs text-slate-500 dark:border-slate-700">
            <th scope="col" className="p-2">Key</th><th scope="col" className="p-2">Status</th>
            <th scope="col" className="p-2">Proposed integer</th><th scope="col" className="p-2">Reason</th>
            <th scope="col" className="p-2">Updated</th><th scope="col" className="p-2">Actions</th></tr></thead>
          <tbody>{rows.map((item) => (
            <tr key={item.requestId} className="border-b border-slate-100 dark:border-slate-800">
              <th scope="row" className="p-2 font-mono text-xs">{item.configurationKey}</th>
              <td className="p-2"><StatusBadge value={item.status} /></td>
              <td className="p-2">{item.proposedInteger ?? "—"}</td>
              <td className="p-2">{item.reasonCode}</td>
              <td className="p-2">{item.updatedAtUtc ? new Date(item.updatedAtUtc).toLocaleString() : new Date(item.createdAtUtc).toLocaleString()}</td>
              <td className="p-2">
                <div className="flex flex-wrap gap-2">
                  {!approvals && item.status === "DRAFT" && access.canEditRequest && onSelectDraft && (
                    <Button size="sm" variant="secondary" onClick={() => {
                      onSelectDraft(item);
                      onValue?.(String(item.proposedInteger ?? ""));
                    }}>Edit draft</Button>
                  )}
                  {!approvals && item.status === "DRAFT" && access.canSubmit &&
                    <Button size="sm" variant="secondary" disabled={busy} onClick={() => onTransition?.(item, "submit")}>Submit</Button>}
                  {!approvals && ["DRAFT", "SUBMITTED"].includes(item.status) && access.canCancel &&
                    <Button size="sm" variant="secondary" disabled={busy} onClick={() => onTransition?.(item, "cancel")}>Cancel</Button>}
                  {approvals && item.status === "SUBMITTED" && access.canApprove && <>
                    <Button size="sm" variant="secondary" disabled={busy} onClick={() => onDecision?.(item, "APPROVE")}>Approve</Button>
                    <Button size="sm" variant="secondary" disabled={busy} onClick={() => onDecision?.(item, "REJECT")}>Reject</Button>
                  </>}
                  {!approvals && item.status === "APPROVED" && access.canApply &&
                    <Button size="sm" variant="secondary" disabled={busy} onClick={() => onTransition?.(item, "apply")}>Apply</Button>}
                  {item.status === "APPLIED" && <span className="text-xs text-slate-500">Restart not automatic</span>}
                </div>
              </td>
            </tr>
          ))}</tbody>
        </table>
      </div>
      {selectedDraft && !approvals && onEdit && onSelectDraft && onValue && onReason && proposedInteger !== undefined && reasonCode && (
        <form className="mt-4 grid gap-3 rounded-xl border border-slate-200 p-4 sm:grid-cols-4 dark:border-slate-700"
          aria-label={`Edit draft for ${selectedDraft.configurationKey}`} onSubmit={onEdit}>
          <label className="text-xs font-medium">Proposed integer
            <input type="number" min="1" max="120" step="1" required value={proposedInteger}
              onChange={(event) => onValue(event.target.value)}
              className="mt-1 block w-full rounded-lg border border-slate-300 bg-transparent px-3 py-2 text-sm" />
          </label>
          <ReasonSelect value={reasonCode} onChange={onReason} />
          <div className="flex items-end gap-2">
            <Button type="submit" disabled={busy || !selectedDraft.requestConcurrencyVersion}>Save draft</Button>
            <Button type="button" variant="secondary" onClick={() => onSelectDraft(null)}>Close</Button>
          </div>
        </form>
      )}
      <Pagination pageNumber={pageNumber} pageSize={query.data.pageSize} totalCount={query.data.totalCount} onPage={onPage} />
    </>
  );
}

function HistoryView({
  query, pageNumber, onPage,
}: {
  query: ReturnType<typeof useQuery<Awaited<ReturnType<typeof getSystemConfigurationHistory>>>>;
  pageNumber: number;
  onPage: (value: number) => void;
}) {
  if (query.isPending || query.isFetching)
    return <div role="status" aria-label="Loading configuration history"><Skeleton className="h-28" /></div>;
  if (query.isError)
    return <Notice>Configuration history could not be loaded. {toApiRequestError(query.error).message}</Notice>;
  if (!query.data?.items.length)
    return <p className="py-5 text-sm text-slate-500">No applied configuration history was returned.</p>;
  return (
    <>
      <div className="overflow-x-auto">
        <table className="min-w-full text-left text-sm">
          <caption className="sr-only">Applied history for explicitly classified configurations.</caption>
          <thead><tr className="border-b border-slate-200 text-xs text-slate-500 dark:border-slate-700">
            <th scope="col" className="p-2">Key</th><th scope="col" className="p-2">Version</th>
            <th scope="col" className="p-2">Applied integer</th><th scope="col" className="p-2">Reason</th>
            <th scope="col" className="p-2">Actor</th><th scope="col" className="p-2">Occurred</th></tr></thead>
          <tbody>{query.data.items.map((item) => (
            <tr key={item.historyId} className="border-b border-slate-100 dark:border-slate-800">
              <th scope="row" className="p-2 font-mono text-xs">{item.configurationKey}</th>
              <td className="p-2">{item.versionNumber}</td><td className="p-2">{item.appliedInteger ?? "—"}</td>
              <td className="p-2">{item.reasonCode}</td><td className="p-2">{item.actorUserId}</td>
              <td className="p-2">{new Date(item.occurredAtUtc).toLocaleString()}</td>
            </tr>
          ))}</tbody>
        </table>
      </div>
      <Pagination pageNumber={pageNumber} pageSize={query.data.pageSize} totalCount={query.data.totalCount} onPage={onPage} />
    </>
  );
}

function ReasonSelect({
  value, onChange,
}: {
  value: (typeof reasons)[number];
  onChange: (value: (typeof reasons)[number]) => void;
}) {
  return (
    <label className="text-xs font-medium">Reason code
      <select value={value} onChange={(event) => onChange(event.target.value as (typeof reasons)[number])}
        className="mt-1 block w-full rounded-lg border border-slate-300 bg-transparent px-3 py-2 text-sm">
        {reasons.map((reason) => <option key={reason} value={reason}>{reason.replaceAll("_", " ")}</option>)}
      </select>
    </label>
  );
}

function Pagination({
  pageNumber, pageSize, totalCount, onPage,
}: {
  pageNumber: number;
  pageSize: number;
  totalCount: number;
  onPage: (value: number) => void;
}) {
  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));
  return (
    <nav aria-label="Configuration results pages" className="mt-4 flex items-center justify-end gap-3">
      <span className="text-xs text-slate-500">Page {pageNumber} of {pageCount} · {totalCount} records</span>
      <Button size="sm" variant="secondary" disabled={pageNumber <= 1} onClick={() => onPage(pageNumber - 1)}>Previous</Button>
      <Button size="sm" variant="secondary" disabled={pageNumber >= pageCount} onClick={() => onPage(pageNumber + 1)}>Next</Button>
    </nav>
  );
}
