import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  getRolePermissionHistory,
  getRolePermissionMatrix,
  getRolePermissionMatrixAccess,
  saveRolePermissionChanges,
  validateRolePermissionChanges,
} from "../../api/rolePermissionMatrix";
import { toApiRequestError } from "../../api/client";
import type {
  RolePermissionMatrixBatchRequest,
  RolePermissionMatrixCell,
  RolePermissionMatrixColumn,
  RolePermissionMatrixChange,
  RolePermissionMatrixRow,
} from "../../api/contracts";
import { Button, Notice, PageHeading, Skeleton, StatusBadge } from "../../components/ui";

type ChangeMap = Map<string, RolePermissionMatrixChange>;
type GrantFilter = "all" | "allowed" | "denied";

function cellKey(permissionId: number, roleId: number, tenantTypeId: number | null): string {
  return `${permissionId}:${roleId}:${tenantTypeId ?? "platform"}`;
}

function columnKey(roleId: number, tenantTypeId: number | null): string {
  return `${roleId}:${tenantTypeId ?? "platform"}`;
}

function groupLabel(scopeCode: string, tenantTypeCode: string | null): string {
  if (scopeCode === "PLATFORM") return "PLATFORM";
  return tenantTypeCode ?? scopeCode;
}

function errorText(error: unknown): string {
  return toApiRequestError(error).message;
}

function filterRows(
  rows: RolePermissionMatrixRow[],
  search: string,
  module: string,
  scope: string,
  readiness: string,
  grant: GrantFilter,
): RolePermissionMatrixRow[] {
  const normalizedSearch = search.trim().toLocaleLowerCase();
  return rows.filter((row) => {
    const matchesText = !normalizedSearch ||
      `${row.permissionCode} ${row.permissionName} ${row.permissionDescription}`
        .toLocaleLowerCase().includes(normalizedSearch);
    const matchesModule = module === "all" || row.module === module;
    const matchesScope = scope === "all" || row.scopeCode === scope;
    const matchesReadiness = readiness === "all" || row.readinessStatus === readiness;
    const matchesGrant = grant === "all" || row.isAccountPolicy ||
      row.cells.some((cell) => cell.configuredGrant === (grant === "allowed"));
    return matchesText && matchesModule && matchesScope && matchesReadiness && matchesGrant;
  });
}

export function RolePermissionMatrixPage() {
  const queryClient = useQueryClient();
  const accessQuery = useQuery({
    queryKey: ["platform-role-permission-matrix", "access"],
    queryFn: getRolePermissionMatrixAccess,
    staleTime: 0,
    refetchOnMount: "always",
    retry: false,
  });
  const canRead = accessQuery.isSuccess && !accessQuery.isFetching && accessQuery.data?.canRead === true;
  const canUpdate = canRead && accessQuery.data?.canUpdate === true;
  const matrixQuery = useQuery({
    queryKey: ["platform-role-permission-matrix"],
    queryFn: getRolePermissionMatrix,
    enabled: canRead,
  });
  const historyQuery = useQuery({
    queryKey: ["platform-role-permission-history"],
    queryFn: getRolePermissionHistory,
    enabled: canRead,
  });
  const [changes, setChanges] = useState<ChangeMap>(() => new Map());
  const [search, setSearch] = useState("");
  const [moduleFilter, setModuleFilter] = useState("all");
  const [scopeFilter, setScopeFilter] = useState("all");
  const [readinessFilter, setReadinessFilter] = useState("all");
  const [grantFilter, setGrantFilter] = useState<GrantFilter>("all");
  const [reason, setReason] = useState("");
  const [reviewedBatch, setReviewedBatch] = useState<string | null>(null);
  const [requiresReload, setRequiresReload] = useState(false);
  const reviewed = reviewedBatch !== null && reviewedBatch === JSON.stringify(batchRequest());
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [validationIssues, setValidationIssues] = useState<string[]>([]);

  const rows = matrixQuery.data?.rows ?? [];
  const columns = matrixQuery.data?.columns ?? [];
  const modules = useMemo(
    () => [...new Set(rows.map((row) => row.module))].sort((a, b) => a.localeCompare(b)),
    [rows],
  );
  const readinessStatuses = useMemo(
    () => [...new Set(rows.map((row) => row.readinessStatus))].sort((a, b) => a.localeCompare(b)),
    [rows],
  );
  const visibleRows = useMemo(
    () => filterRows(rows, search, moduleFilter, scopeFilter, readinessFilter, grantFilter),
    [rows, search, moduleFilter, scopeFilter, readinessFilter, grantFilter],
  );
  const groupedRows = useMemo(() => {
    const groups = new Map<string, Map<string, RolePermissionMatrixRow[]>>();
    for (const row of visibleRows) {
      const resources = groups.get(row.module) ?? new Map<string, RolePermissionMatrixRow[]>();
      const permissions = resources.get(row.resource) ?? [];
      permissions.push(row);
      resources.set(row.resource, permissions);
      groups.set(row.module, resources);
    }
    return groups;
  }, [visibleRows]);

  const validationMutation = useMutation({
    mutationFn: validateRolePermissionChanges,
    onSuccess: (result, request) => {
      if (result.issues.some((issue) => issue.code === "STALE_CONCURRENCY")) setRequiresReload(true);
      setValidationIssues(result.issues.map((issue) =>
        `${issue.permissionCode ?? "Permission"}: ${issue.message}`));
      setReviewedBatch(result.isValid ? JSON.stringify(request) : null);
    },
  });
  const saveMutation = useMutation({
    mutationFn: saveRolePermissionChanges,
    onError: (error) => {
      setReviewedBatch(null);
      setConfirmOpen(false);
      if (toApiRequestError(error).code === "STALE_PERMISSION_MATRIX") setRequiresReload(true);
    },
    onSuccess: async () => {
      setChanges(new Map());
      setRequiresReload(false);
      setReason("");
      setReviewedBatch(null);
      setValidationIssues([]);
      setConfirmOpen(false);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["platform-role-permission-matrix"] }),
        queryClient.invalidateQueries({ queryKey: ["platform-role-permission-history"] }),
        queryClient.invalidateQueries({ queryKey: ["tenant-permissions"] }),
      ]);
    },
  });

  const busy = validationMutation.isPending || saveMutation.isPending;
  const canEdit = canUpdate && matrixQuery.isSuccess && !matrixQuery.isFetching && !busy && !requiresReload && !confirmOpen;

  function currentValue(cell: RolePermissionMatrixCell, row: RolePermissionMatrixRow): boolean {
    if (row.permissionId == null) return false;
    return changes.get(cellKey(row.permissionId, cell.roleId, cell.tenantTypeId))?.isGranted ??
      cell.configuredGrant;
  }

  function editCell(row: RolePermissionMatrixRow, cell: RolePermissionMatrixCell, nextValue: boolean) {
    if (!canEdit || row.permissionId == null || !cell.isEditable || row.isAccountPolicy) return;
    const key = cellKey(row.permissionId, cell.roleId, cell.tenantTypeId);
    const next = new Map(changes);
    if (nextValue === cell.configuredGrant) {
      next.delete(key);
    } else {
      next.set(key, {
        permissionId: row.permissionId,
        roleId: cell.roleId,
        tenantTypeId: cell.tenantTypeId,
        isGranted: nextValue,
        concurrencyVersion: cell.concurrencyVersion,
      });
    }
    setChanges(next);
    setReviewedBatch(null);
    setValidationIssues([]);
  }

  function batchRequest(): RolePermissionMatrixBatchRequest {
    return { reason: reason.trim(), changes: [...changes.values()] };
  }

  function discardChanges() {
    if (busy) return;
    setConfirmOpen(false);
    setChanges(new Map());
    setReason("");
    setReviewedBatch(null);
    setValidationIssues([]);
    validationMutation.reset();
    saveMutation.reset();
  }

  async function reloadMatrix() {
    if (busy) return;
    discardChanges();
    setRequiresReload(true);
    const result = await matrixQuery.refetch();
    if (result.isSuccess) setRequiresReload(false);
  }

  function reviewChanges() {
    if (!canEdit || changes.size < 1 || changes.size > 100 || reason.trim().length < 10) return;
    setValidationIssues([]);
    setReviewedBatch(null);
    validationMutation.mutate(batchRequest());
  }

  function confirmSave() {
    if (!canUpdate || !matrixQuery.isSuccess || matrixQuery.isFetching || busy || requiresReload || !reviewed || !confirmOpen) return;
    saveMutation.mutate(batchRequest());
  }

  const sections = [...groupedRows.entries()];
  const columnGroups = columns.reduce<Array<{ label: string; key: string; count: number }>>((result, column) => {
    const label = groupLabel(column.scopeCode, column.tenantTypeCode);
    const key = column.scopeCode === "PLATFORM" ? "PLATFORM" : column.tenantTypeCode ?? "TENANT";
    const previous = result.at(-1);
    if (previous?.key === key) previous.count += 1;
    else result.push({ label, key, count: 1 });
    return result;
  }, []);

  return (
    <>
      <PageHeading
        eyebrow="Platform administration / Platform Setup"
        title="Role & Permission Matrix"
        description="Database-backed configured grants and context restrictions. Effective policy status is not a substitute for resource-level authorization."
        action={
          <Link to="/platform-setup">
            <Button variant="secondary">Platform Setup</Button>
          </Link>
        }
      />
      {accessQuery.isPending || accessQuery.isFetching ? (
        <div className="space-y-3"><Skeleton className="h-10" /><Skeleton className="h-48" /></div>
      ) : accessQuery.isError ? (
        <div><Notice>{errorText(accessQuery.error)}</Notice><Button variant="secondary" onClick={() => void accessQuery.refetch()}>Retry access check</Button></div>
      ) : !canRead ? (
        <Notice kind="info">You do not have permission to view the Role & Permission Matrix.</Notice>
      ) : (
        <>
          {matrixQuery.isError && <div><Notice>{errorText(matrixQuery.error)}</Notice><Button variant="secondary" onClick={() => void reloadMatrix()} disabled={busy}>Reload Matrix (discard edits)</Button></div>}
          {matrixQuery.isPending && <div className="space-y-3"><Skeleton className="h-10" /><Skeleton className="h-64" /></div>}
          {matrixQuery.isSuccess && (
            <section className="space-y-5">
              <div className="flex flex-wrap items-end gap-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-soft dark:border-slate-800 dark:bg-slate-900">
                <label className="min-w-52 flex-1 text-xs font-semibold text-slate-600 dark:text-slate-300">
                  Search permissions
                  <input value={search} onChange={(event) => setSearch(event.target.value)}
                    placeholder="Name, description, or code"
                    className="mt-1.5 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
                </label>
                <FilterSelect label="Module" value={moduleFilter} onChange={setModuleFilter}
                  values={modules} />
                <FilterSelect label="Scope" value={scopeFilter} onChange={setScopeFilter}
                  values={["PLATFORM", "TENANT", "ACCOUNT"]} />
                <FilterSelect label="Readiness" value={readinessFilter} onChange={setReadinessFilter}
                  values={readinessStatuses} />
                <label className="text-xs font-semibold text-slate-600 dark:text-slate-300">
                  Configured grants
                  <select value={grantFilter} onChange={(event) => setGrantFilter(event.target.value as GrantFilter)}
                    className="mt-1.5 block rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950">
                    <option value="all">All</option>
                    <option value="allowed">Granted</option>
                    <option value="denied">Denied</option>
                  </select>
                </label>
              </div>

              {requiresReload && (
                <div className="space-y-2">
                  <Notice>The matrix changed on the server. Reload the current values and review your changes again.</Notice>
                  <Button variant="secondary" onClick={() => void reloadMatrix()} disabled={busy || matrixQuery.isFetching}>Reload Matrix (discard edits)</Button>
                </div>
              )}
              {changes.size > 0 && (
                <div className="rounded-2xl border border-amber-300 bg-amber-50 p-4 dark:border-amber-900 dark:bg-amber-950/30">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <p className="text-sm font-bold text-amber-950 dark:text-amber-100">
                        {changes.size} unsaved permission change{changes.size === 1 ? "" : "s"}
                      </p>
                      <p className="mt-1 text-xs text-amber-900/80 dark:text-amber-200/80">
                        Review validates the full batch. Saving revalidates and checks every concurrency token atomically.
                      </p>
                    </div>
                    <div className="flex gap-2">
                      <Button variant="secondary" onClick={discardChanges}
                        disabled={validationMutation.isPending || saveMutation.isPending}>Discard Changes</Button>
                      <Button onClick={() => void reviewChanges()}
                        disabled={!canEdit || reason.trim().length < 10 || changes.size > 100}>
                        {validationMutation.isPending ? "Reviewing..." : "Review Changes"}
                      </Button>
                      <Button onClick={() => setConfirmOpen(true)}
                        disabled={!reviewed || !canEdit}>
                        Confirm & Save
                      </Button>
                    </div>
                  </div>
                  <label className="mt-4 block text-xs font-semibold text-amber-950 dark:text-amber-100">
                    Change reason (required, 10–500 characters)
                    <textarea value={reason} disabled={!canEdit} onChange={(event) => {
                      if (!canEdit) return;
                      setReason(event.target.value);
                      setReviewedBatch(null);
                    }} maxLength={500} rows={2}
                      className="mt-1.5 w-full rounded-lg border border-amber-300 bg-white px-3 py-2 text-sm text-slate-900 dark:border-amber-900 dark:bg-slate-950 dark:text-slate-100" />
                  </label>
                  {changes.size > 100 && <p role="alert">A batch may contain at most 100 changes.</p>}
                  {!canUpdate && <p className="mt-2 text-xs">This session has read-only matrix access.</p>}
                  {validationMutation.isError && <p role="alert" className="mt-2 text-sm text-rose-700">{errorText(validationMutation.error)}</p>}
                  {validationIssues.length > 0 && (
                    <ul role="alert" className="mt-3 list-disc space-y-1 pl-5 text-sm text-rose-800 dark:text-rose-200">
                      {validationIssues.map((issue, index) => <li key={`${index}-${issue}`}>{issue}</li>)}
                    </ul>
                  )}
                  {reviewed && validationIssues.length === 0 && (
                    <p role="status" className="mt-2 text-sm font-medium text-emerald-800 dark:text-emerald-200">
                      All proposed changes passed server-side validation.
                    </p>
                  )}
                  {saveMutation.isError && <p role="alert" className="mt-2 text-sm text-rose-700">{errorText(saveMutation.error)}</p>}
                </div>
              )}

              <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-soft dark:border-slate-800 dark:bg-slate-900">
                <div className="overflow-x-auto">
                  <table className="min-w-full border-separate border-spacing-0 text-left text-xs">
                    <thead className="sticky top-0 z-10 bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-200">
                      <tr>
                        <th rowSpan={2} className="sticky left-0 z-20 min-w-72 border-b border-r border-slate-200 bg-slate-100 px-4 py-3 dark:border-slate-700 dark:bg-slate-800">
                          Permission
                        </th>
                        {columnGroups.map((group) => (
                          <th key={group.key} colSpan={group.count} className="border-b border-slate-200 px-3 py-2 text-center font-bold dark:border-slate-700">
                            {group.label}
                          </th>
                        ))}
                        <th rowSpan={2} className="min-w-32 border-b border-l border-slate-200 px-3 py-3 dark:border-slate-700">Readiness</th>
                      </tr>
                      <tr>
                        {columns.map((column) => (
                          <th key={columnKey(column.roleId, column.tenantTypeId)}
                            className="min-w-28 border-b border-slate-200 px-3 py-2 text-center dark:border-slate-700">
                            <span className="block font-bold">{column.roleCode}</span>
                            <span className="mt-0.5 block font-normal text-slate-500">{column.tenantTypeCode ?? "Platform"}</span>
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {sections.length === 0 && (
                        <tr><td colSpan={columns.length + 2} className="px-4 py-8 text-center text-slate-500">No permissions match these filters.</td></tr>
                      )}
                      {sections.map(([moduleName, resources]) => (
                        <ModuleGroup key={moduleName} moduleName={moduleName} resources={resources}
                          columns={columns} changes={changes} canUpdate={canEdit} onEdit={editCell}
                          currentValue={currentValue} />
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>

              <section className="rounded-2xl border border-slate-200 bg-white p-4 shadow-soft dark:border-slate-800 dark:bg-slate-900">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <h2 className="text-sm font-bold">Permission change history</h2>
                    <p className="mt-1 text-xs text-slate-500">Successful and rejected batches written by the database audit procedure.</p>
                  </div>
                  <Button size="sm" variant="secondary" onClick={() => void historyQuery.refetch()}
                    disabled={historyQuery.isFetching}>Refresh</Button>
                </div>
                {historyQuery.isError && <div className="mt-3"><Notice>{errorText(historyQuery.error)}</Notice></div>}
                {historyQuery.isPending ? <div className="mt-4"><Skeleton className="h-24" /></div> : (
                  <div className="mt-4 overflow-x-auto">
                    <table className="min-w-full text-left text-xs">
                      <thead><tr className="text-slate-500">
                        <th className="p-2">When (UTC)</th><th className="p-2">Permission</th><th className="p-2">Role / context</th>
                        <th className="p-2">Change</th><th className="p-2">Actor</th><th className="p-2">Reason</th><th className="p-2">Outcome</th>
                      </tr></thead>
                      <tbody>
                        {(historyQuery.data ?? []).map((entry) => (
                          <tr key={entry.auditEventId} className="border-t border-slate-100 dark:border-slate-800">
                            <td className="whitespace-nowrap p-2">{new Date(entry.occurredAtUtc).toLocaleString(undefined, { timeZone: "UTC" })}</td>
                            <td className="p-2 font-mono">{entry.permissionCode}</td>
                            <td className="p-2">{entry.roleCode} / {entry.tenantTypeCode ?? entry.scopeCode}</td>
                            <td className="p-2">{entry.previousGrant ? "Granted" : "Denied"} → {entry.newGrant ? "Granted" : "Denied"}</td>
                            <td className="p-2">{entry.actorDisplayName ?? "System actor"}</td>
                            <td className="max-w-64 p-2">{entry.changeReason}</td>
                            <td className="p-2"><StatusBadge value={entry.outcome} /></td>
                          </tr>
                        ))}
                        {historyQuery.data?.length === 0 && (
                          <tr><td colSpan={7} className="p-4 text-center text-slate-500">No matrix changes have been recorded.</td></tr>
                        )}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>
            </section>
          )}
        </>
      )}
      {confirmOpen && canUpdate && matrixQuery.isSuccess && !requiresReload && reviewed && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/50 p-4">
          <section role="dialog" aria-modal="true" aria-labelledby="matrix-confirm-title"
            className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl dark:bg-slate-900">
            <h2 id="matrix-confirm-title" className="text-lg font-bold">Confirm permission changes</h2>
            <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
              Save {changes.size} reviewed change{changes.size === 1 ? "" : "s"} as one atomic batch?
            </p>
            <p className="mt-3 rounded-lg bg-slate-50 p-3 text-sm dark:bg-slate-800">{reason.trim()}</p>
            <div className="mt-5 flex justify-end gap-2">
              <Button variant="secondary" onClick={() => setConfirmOpen(false)} disabled={saveMutation.isPending}>Cancel</Button>
              <Button onClick={() => void confirmSave()} disabled={busy || matrixQuery.isFetching || !reviewed || !canUpdate}>
                {saveMutation.isPending ? "Saving..." : "Confirm & Save"}
              </Button>
            </div>
          </section>
        </div>
      )}
    </>
  );
}

function FilterSelect({
  label,
  value,
  onChange,
  values,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  values: string[];
}) {
  return (
    <label className="text-xs font-semibold text-slate-600 dark:text-slate-300">
      {label}
      <select value={value} onChange={(event) => onChange(event.target.value)}
        className="mt-1.5 block max-w-48 rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950">
        <option value="all">All</option>
        {values.map((item) => <option key={item} value={item}>{item}</option>)}
      </select>
    </label>
  );
}

function ModuleGroup({
  moduleName,
  resources,
  columns,
  changes,
  canUpdate,
  onEdit,
  currentValue,
}: {
  moduleName: string;
  resources: Map<string, RolePermissionMatrixRow[]>;
  columns: RolePermissionMatrixColumn[];
  changes: ChangeMap;
  canUpdate: boolean;
  onEdit: (row: RolePermissionMatrixRow, cell: RolePermissionMatrixCell, value: boolean) => void;
  currentValue: (cell: RolePermissionMatrixCell, row: RolePermissionMatrixRow) => boolean;
}) {
  return (
    <tr>
      <td colSpan={columns.length + 2} className="p-0">
        <details open className="group">
          <summary className="sticky left-0 cursor-pointer list-none border-b border-slate-200 bg-slate-50 px-4 py-2 font-bold text-slate-800 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-100">
            <span aria-hidden="true" className="mr-2 inline-block transition group-open:rotate-90">▸</span>
            {moduleName}
          </summary>
          {[...resources.entries()].map(([resource, rows]) => (
            <table key={resource} className="min-w-full table-fixed border-separate border-spacing-0 text-left text-xs">
              <tbody>
                <tr>
                  <th colSpan={columns.length + 2} className="sticky left-0 border-b border-slate-200 bg-white px-4 py-2 font-semibold text-slate-500 dark:border-slate-800 dark:bg-slate-900">
                    {resource}
                  </th>
                </tr>
                {rows.map((row) => (
                  <tr key={row.permissionCode} className="hover:bg-slate-50 dark:hover:bg-slate-800/60">
                    <td className="sticky left-0 z-[1] min-w-72 border-b border-r border-slate-100 bg-white px-4 py-3 dark:border-slate-800 dark:bg-slate-900">
                      <span className="block font-semibold text-slate-900 dark:text-slate-100">{row.permissionName}</span>
                      <span className="mt-1 block font-mono text-[10px] text-slate-500">{row.permissionCode}</span>
                      <span className="mt-1 block max-w-80 text-[11px] leading-4 text-slate-500">{row.permissionDescription}</span>
                      {row.isAccountPolicy && row.accountPolicy && (
                        <span className="mt-2 block text-[10px] text-slate-500">
                          Policy — Public: {row.accountPolicy.publicAllowed ? "Allowed" : "Denied"} ·
                          Unverified: {row.accountPolicy.unverifiedAllowed ? "Allowed" : "Denied"} ·
                          Verified: {row.accountPolicy.verifiedAllowed ? "Allowed" : "Denied"}
                        </span>
                      )}
                    </td>
                    {row.isAccountPolicy ? (
                      <td colSpan={columns.length} className="border-b border-slate-100 px-4 py-2 text-center text-slate-500 dark:border-slate-800">
                        Read-only policy information; not assigned to roles
                      </td>
                    ) : columns.map((column) => {
                      const permissionId = row.permissionId;
                      if (permissionId == null) {
                        return <td key={columnKey(column.roleId, column.tenantTypeId)} className="border-b border-slate-100 p-2 text-center dark:border-slate-800">—</td>;
                      }
                      const cell = row.cells.find((candidate) =>
                        candidate.roleId === column.roleId && candidate.tenantTypeId === column.tenantTypeId);
                      if (!cell) return <td key={columnKey(column.roleId, column.tenantTypeId)} className="border-b border-slate-100 p-2 text-center dark:border-slate-800">—</td>;
                      const key = cellKey(permissionId, cell.roleId, cell.tenantTypeId);
                      const checked = currentValue(cell, row);
                      const editable = canUpdate && cell.isEditable && !row.isAccountPolicy;
                      return (
                        <td key={columnKey(column.roleId, column.tenantTypeId)} className="border-b border-slate-100 px-3 py-2 text-center dark:border-slate-800">
                          <label className="inline-flex items-center gap-1.5" title={cell.restrictionReason ?? undefined}>
                            <input type="checkbox" checked={checked} disabled={!editable}
                              aria-label={`${row.permissionCode} ${column.roleCode} ${column.tenantTypeCode ?? "PLATFORM"}`}
                              onChange={(event) => onEdit(row, cell, event.target.checked)}
                              className="size-4 rounded border-slate-300 text-brand-600 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50" />
                            <span className="sr-only">{checked ? "Configured grant" : "No configured grant"}</span>
                          </label>
                          <span className="mt-1 block text-[10px] text-slate-500">
                            {checked ? "Configured" : "Not configured"} · Effective {cell.effectiveAllowed == null ? "Not evaluated" : cell.effectiveAllowed ? "Allowed" : "Denied"}
                          </span>
                          {!editable && cell.restrictionReason && (
                            <span className="mt-1 block max-w-32 text-[10px] text-amber-700 dark:text-amber-300">{cell.restrictionReason}</span>
                          )}
                          {changes.has(key) && <span className="mt-1 block text-[10px] font-semibold text-brand-700">Unsaved</span>}
                        </td>
                      );
                    })}
                    <td className="min-w-32 border-b border-l border-slate-100 px-3 py-2 dark:border-slate-800">
                      <StatusBadge value={row.readinessStatus} />
                      <span className="mt-1 block text-[10px] text-slate-500">{row.action}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ))}
        </details>
      </td>
    </tr>
  );
}
