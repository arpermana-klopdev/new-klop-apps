import { zodResolver } from "@hookform/resolvers/zod";
import { Building2, Plus, Search, UsersRound } from "lucide-react";
import { useMemo, useState } from "react";
import { useForm } from "react-hook-form";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import {
  createTenant,
  getMyTenants,
  getOrganizationTypes,
  inviteMember,
} from "../../api/tenants";
import { toApiRequestError } from "../../api/client";
import { Button, Dialog, Field, Notice, PageHeading, Skeleton, StatusBadge, TextInput } from "../../components/ui";
import type { TenantCreateRequest } from "../../api/contracts";

const tenantSchema = z.object({
  tenantCode: z.string().trim().min(1, "Tenant code is required.").max(50),
  tenantTypeCode: z.string().trim().min(1, "Tenant type code is required.").max(50),
  displayName: z.string().trim().min(1, "Display name is required.").max(200),
  organizationTypeId: z.string(),
  registeredName: z.string().trim().max(250),
}).superRefine((value, context) => {
  const hasOrganizationType = value.organizationTypeId !== "";
  const hasRegisteredName = value.registeredName.length > 0;
  if (hasOrganizationType !== hasRegisteredName) {
    context.addIssue({
      code: "custom",
      message: "Organization type and registered name must be supplied together.",
      path: ["registeredName"],
    });
  }
});

const inviteSchema = z.object({
  inviteeUserId: z.coerce.number().int().positive("Enter a valid existing user ID."),
});

type TenantFormValues = z.infer<typeof tenantSchema>;
type InviteFormValues = z.infer<typeof inviteSchema>;

export function TenantsPage() {
  const queryClient = useQueryClient();
  const tenantsQuery = useQuery({ queryKey: ["tenants"], queryFn: getMyTenants });
  const [createOpen, setCreateOpen] = useState(false);
  const [inviteTenantId, setInviteTenantId] = useState<number | string | null>(null);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [currentPage, setCurrentPage] = useState(1);
  const [notice, setNotice] = useState<{ kind: "success" | "error"; text: string } | null>(null);

  const createMutation = useMutation({
    mutationFn: createTenant,
    onSuccess: async (created) => {
      setNotice({ kind: "success", text: `Tenant created. Tenant ID: ${created.tenantId}.` });
      setCreateOpen(false);
      await queryClient.invalidateQueries({ queryKey: ["tenants"] });
    },
    onError: (error: unknown) => setNotice({ kind: "error", text: toApiRequestError(error).message }),
  });
  const inviteMutation = useMutation({
    mutationFn: ({ tenantId, userId }: { tenantId: number | string; userId: number }) =>
      inviteMember(tenantId, { inviteeUserId: userId }),
    onSuccess: async (result) => {
      setNotice({
        kind: "success",
        text: `Invitation created. Membership ID: ${result.membershipId}.`,
      });
      setInviteTenantId(null);
      await queryClient.invalidateQueries({ queryKey: ["tenants"] });
    },
    onError: (error: unknown) => setNotice({ kind: "error", text: toApiRequestError(error).message }),
  });

  const tenants = tenantsQuery.data ?? [];
  const filteredTenants = useMemo(() => {
    const term = search.trim().toLowerCase();
    return tenants.filter((tenant) => {
      const matchesSearch = !term ||
        [tenant.displayName ?? "", tenant.tenantCode ?? "", tenant.tenantTypeCode ?? "", tenant.tenantStatusCode ?? ""]
          .some((value) => value.toLowerCase().includes(term));
      const matchesStatus = !statusFilter || tenant.tenantStatusCode === statusFilter;
      return matchesSearch && matchesStatus;
    });
  }, [search, statusFilter, tenants]);
  const pageSize = 8;
  const pageCount = Math.max(1, Math.ceil(filteredTenants.length / pageSize));
  const visibleTenants = filteredTenants.slice(
    (currentPage - 1) * pageSize,
    currentPage * pageSize,
  );
  const tenantStatuses = [...new Set(
    tenants
      .map((tenant) => tenant.tenantStatusCode)
      .filter((status): status is string => status !== undefined),
  )].sort();

  return (
    <>
      <PageHeading
        eyebrow="Workspace administration"
        title="Tenants"
        description="Manage tenants available to the authenticated account. This is not a platform-wide tenant directory."
        action={
          <Button onClick={() => { setNotice(null); setCreateOpen(true); }}>
            <Plus aria-hidden="true" className="size-4" /> Create tenant
          </Button>
        }
      />
      {notice && <div className="mb-5"><Notice kind={notice.kind}>{notice.text}</Notice></div>}
      <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-soft dark:border-slate-800 dark:bg-slate-900">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 px-5 py-4 dark:border-slate-800">
          <div>
            <h2 className="text-sm font-bold">Tenant workspaces</h2>
            <p className="mt-1 text-xs text-slate-500">Tenant and membership statuses are provided by the API.</p>
          </div>
          <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row">
            <label className="relative w-full sm:w-56">
              <Search aria-hidden="true" className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-slate-400" />
              <TextInput
                aria-label="Search tenants"
                className="pl-9"
                placeholder="Search tenants"
                value={search}
                onChange={(event) => { setSearch(event.target.value); setCurrentPage(1); }}
              />
            </label>
            <select
              aria-label="Filter by tenant status"
              className="field-control w-full sm:w-44"
              value={statusFilter}
              onChange={(event) => { setStatusFilter(event.target.value); setCurrentPage(1); }}
            >
              <option value="">All tenant statuses</option>
              {tenantStatuses.map((status) => <option key={status} value={status}>{status}</option>)}
            </select>
          </div>
        </div>
        {tenantsQuery.isPending ? (
          <div className="space-y-3 p-5">
            <Skeleton className="h-12" /><Skeleton className="h-12" /><Skeleton className="h-12" />
          </div>
        ) : tenantsQuery.isError ? (
          <div className="p-5">
            <Notice>{toApiRequestError(tenantsQuery.error).message}</Notice>
            <Button className="mt-4" variant="secondary" size="sm" onClick={() => void tenantsQuery.refetch()}>Retry</Button>
          </div>
        ) : filteredTenants.length === 0 ? (
          <div className="px-5 py-14 text-center">
            <Building2 className="mx-auto size-7 text-slate-400" />
            <p className="mt-3 text-sm font-semibold">{tenants.length ? "No tenants match this search" : "No tenants found"}</p>
            <p className="mt-1 text-xs text-slate-500">{tenants.length ? "Try another tenant name or code." : "Create a tenant if registration is enabled by the platform."}</p>
          </div>
        ) : (
          <>
            <div className="hidden overflow-x-auto sm:block">
              <table className="w-full min-w-[680px] text-left text-sm">
                <thead className="bg-slate-50 text-[11px] uppercase tracking-wide text-slate-500 dark:bg-slate-950/60">
                  <tr>
                    <th scope="col" className="px-5 py-3 font-semibold">Tenant</th>
                    <th scope="col" className="px-5 py-3 font-semibold">Type</th>
                    <th scope="col" className="px-5 py-3 font-semibold">Tenant status</th>
                    <th scope="col" className="px-5 py-3 font-semibold">Membership</th>
                    <th scope="col" className="px-5 py-3 text-right font-semibold">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                  {visibleTenants.map((tenant, index) => (
                    <tr key={`${tenant.tenantId ?? "tenant"}-${index}`} className="hover:bg-slate-50/80 dark:hover:bg-slate-800/30">
                      <td className="px-5 py-4">
                        <p className="font-semibold">{tenant.displayName ?? "Unnamed tenant"}</p>
                        <p className="mt-1 text-xs text-slate-500">{tenant.tenantCode ?? "Code unavailable"} · ID {tenant.tenantId ?? "Unavailable"}</p>
                      </td>
                      <td className="px-5 py-4"><StatusBadge value={tenant.tenantTypeCode ?? "Unavailable"} /></td>
                      <td className="px-5 py-4"><StatusBadge value={tenant.tenantStatusCode ?? "Unavailable"} /></td>
                      <td className="px-5 py-4"><StatusBadge value={tenant.membershipStatusCode ?? "Unavailable"} /></td>
                      <td className="px-5 py-4 text-right">
                        <div className="inline-flex items-center gap-2">
                          {tenant.tenantId !== undefined && (
                            <Link
                              to={`/tenants/${encodeURIComponent(String(tenant.tenantId))}/members`}
                              aria-label={`Manage members & roles for ${tenant.displayName ?? "tenant"}`}
                              className="rounded-lg px-2 py-2 text-xs font-semibold text-brand-700 hover:bg-brand-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:text-blue-300 dark:hover:bg-slate-800"
                            >
                              Members &amp; roles
                            </Link>
                          )}
                          <Button
                            size="sm"
                            variant="secondary"
                            disabled={tenant.tenantId === undefined}
                            onClick={() => {
                              if (tenant.tenantId === undefined) return;
                              setNotice(null);
                              setInviteTenantId(tenant.tenantId);
                            }}
                          >
                            <UsersRound className="size-3.5" /> Invite
                          </Button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="space-y-3 p-4 sm:hidden">
              {visibleTenants.map((tenant, index) => (
                <article key={`${tenant.tenantId ?? "tenant"}-${index}`} className="rounded-xl border border-slate-200 p-4 dark:border-slate-800">
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <h3 className="text-sm font-bold">{tenant.displayName ?? "Unnamed tenant"}</h3>
                      <p className="mt-1 text-xs text-slate-500">{tenant.tenantCode ?? "Code unavailable"} · ID {tenant.tenantId ?? "Unavailable"}</p>
                    </div>
                    <StatusBadge value={tenant.tenantStatusCode ?? "Unavailable"} />
                  </div>
                  <div className="mt-3 flex flex-wrap gap-2">
                    <StatusBadge value={tenant.tenantTypeCode ?? "Unavailable"} />
                    <StatusBadge value={tenant.membershipStatusCode ?? "Unavailable"} />
                  </div>
                  <Button
                    className="mt-4 w-full"
                    size="sm"
                    variant="secondary"
                    disabled={tenant.tenantId === undefined}
                    onClick={() => {
                      if (tenant.tenantId !== undefined) setInviteTenantId(tenant.tenantId);
                    }}
                  >
                    <UsersRound className="size-3.5" /> Invite existing user
                  </Button>
                  {tenant.tenantId !== undefined && (
                    <Link
                      to={`/tenants/${encodeURIComponent(String(tenant.tenantId))}/members`}
                      aria-label={`Manage members & roles for ${tenant.displayName ?? "tenant"}`}
                      className="mt-2 flex min-h-9 items-center justify-center rounded-lg border border-slate-200 px-3 text-xs font-semibold text-slate-700 hover:bg-slate-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:border-slate-700 dark:text-slate-200 dark:hover:bg-slate-800"
                    >
                      Manage members &amp; roles
                    </Link>
                  )}
                </article>
              ))}
            </div>
          </>
        )}
        {!tenantsQuery.isPending && !tenantsQuery.isError && filteredTenants.length > 0 && (
          <div className="flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 px-5 py-3 dark:border-slate-800">
            <p className="text-xs text-slate-500">
              Showing {(currentPage - 1) * pageSize + 1}–{Math.min(currentPage * pageSize, filteredTenants.length)} of {filteredTenants.length}
            </p>
            <div className="flex items-center gap-2">
              <Button
                size="sm"
                variant="secondary"
                disabled={currentPage === 1}
                onClick={() => setCurrentPage((page) => Math.max(1, page - 1))}
              >
                Previous
              </Button>
              <span className="min-w-16 text-center text-xs text-slate-500">Page {currentPage} of {pageCount}</span>
              <Button
                size="sm"
                variant="secondary"
                disabled={currentPage === pageCount}
                onClick={() => setCurrentPage((page) => Math.min(pageCount, page + 1))}
              >
                Next
              </Button>
            </div>
          </div>
        )}
      </section>

      <CreateTenantDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        pending={createMutation.isPending}
        onCreate={(values) => createMutation.mutate(values)}
      />
      <InviteDialog
        open={inviteTenantId !== null}
        onOpenChange={(open) => { if (!open) setInviteTenantId(null); }}
        pending={inviteMutation.isPending}
        onInvite={(userId) => {
          if (inviteTenantId !== null) inviteMutation.mutate({ tenantId: inviteTenantId, userId });
        }}
      />
    </>
  );
}

function CreateTenantDialog({
  open,
  onOpenChange,
  pending,
  onCreate,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  pending: boolean;
  onCreate: (request: TenantCreateRequest) => void;
}) {
  const typesQuery = useQuery({
    queryKey: ["organization-types"],
    queryFn: getOrganizationTypes,
    enabled: open,
  });
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<TenantFormValues>({
    resolver: zodResolver(tenantSchema),
    defaultValues: {
      tenantCode: "",
      tenantTypeCode: "",
      displayName: "",
      organizationTypeId: "",
      registeredName: "",
    },
  });

  function submit(values: TenantFormValues) {
    onCreate({
      tenantCode: values.tenantCode.trim(),
      tenantTypeCode: values.tenantTypeCode.trim(),
      displayName: values.displayName.trim(),
      organizationTypeId: values.organizationTypeId ? Number(values.organizationTypeId) : null,
      registeredName: values.registeredName.trim() || null,
    });
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next) reset();
        onOpenChange(next);
      }}
      title="Create tenant"
      description="Tenant types and registration eligibility are validated by the platform."
    >
      <form className="space-y-4" onSubmit={handleSubmit(submit)} noValidate>
        <Field label="Display name" htmlFor="tenant-name" error={errors.displayName?.message}>
          <TextInput id="tenant-name" maxLength={200} {...register("displayName")} />
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Tenant code" htmlFor="tenant-code" error={errors.tenantCode?.message}>
            <TextInput id="tenant-code" maxLength={50} {...register("tenantCode")} />
          </Field>
          <Field
            label="Tenant type code"
            htmlFor="tenant-type"
            hint="Enter a type code supported by the backend."
            error={errors.tenantTypeCode?.message}
          >
            <TextInput id="tenant-type" maxLength={50} placeholder="Provided by your platform admin" {...register("tenantTypeCode")} />
          </Field>
        </div>
        <Field
          label="Organization type"
          htmlFor="organization-type"
          hint="Optional. Select this together with a registered name."
          error={errors.organizationTypeId?.message}
        >
          <select id="organization-type" className="field-control" {...register("organizationTypeId")}>
            <option value="">Not applicable</option>
            {typesQuery.data?.map((type) => (
              <option key={type.organizationTypeId} value={type.organizationTypeId}>
                {type.name} ({type.countryCode})
              </option>
            ))}
          </select>
        </Field>
        {typesQuery.isError && <Notice>{toApiRequestError(typesQuery.error).message}</Notice>}
        <Field label="Registered name" htmlFor="registered-name" error={errors.registeredName?.message}>
          <TextInput id="registered-name" maxLength={250} {...register("registeredName")} />
        </Field>
        {errors.registeredName?.message && <Notice>{errors.registeredName.message}</Notice>}
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="secondary" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button type="submit" disabled={pending || typesQuery.isLoading}>
            {pending ? "Creating…" : "Create tenant"}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

function InviteDialog({
  open,
  onOpenChange,
  pending,
  onInvite,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  pending: boolean;
  onInvite: (userId: number) => void;
}) {
  const { register, handleSubmit, reset, formState: { errors } } = useForm<
    z.input<typeof inviteSchema>,
    unknown,
    InviteFormValues
  >({
    resolver: zodResolver(inviteSchema),
  });
  return (
    <Dialog
      open={open}
      onOpenChange={(next) => { if (!next) reset(); onOpenChange(next); }}
      title="Invite existing user"
      description="The current API accepts a user ID and does not provide a searchable user directory."
    >
      <form
        className="space-y-4"
        onSubmit={handleSubmit((values) => onInvite(values.inviteeUserId))}
        noValidate
      >
        <Field label="Existing user ID" htmlFor="invite-user-id" error={errors.inviteeUserId?.message}>
          <TextInput id="invite-user-id" type="number" min="1" {...register("inviteeUserId")} />
        </Field>
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="secondary" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button type="submit" disabled={pending}>{pending ? "Sending…" : "Send invitation"}</Button>
        </div>
      </form>
    </Dialog>
  );
}
