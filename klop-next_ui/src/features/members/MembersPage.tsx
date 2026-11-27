import { zodResolver } from "@hookform/resolvers/zod";
import { KeyRound, UserRoundPlus, UserRoundX } from "lucide-react";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { useParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import {
  TENANT_MEMBERS_REMOVE,
  TENANT_ROLES_ASSIGN,
} from "../../app/tenantPermissions";
import {
  acceptMembership,
  assignRole,
  getMyTenants,
  getTenantPermissions,
  removeMember,
  revokeRole,
} from "../../api/tenants";
import { toApiRequestError } from "../../api/client";
import { Button, Dialog, Field, Notice, PageHeading, Skeleton, TextInput } from "../../components/ui";

const acceptSchema = z.object({ membershipId: z.string().regex(/^[1-9]\d*$/, "Enter a valid membership ID.") });
const targetSchema = z.object({
  tenantId: z.string().regex(/^[1-9]\d*$/, "Select a tenant."),
  membershipId: z.string().regex(/^[1-9]\d*$/, "Enter a valid membership ID."),
  roleCode: z.string().trim().max(50).optional(),
});
type AcceptValues = z.infer<typeof acceptSchema>;
type TargetValues = z.infer<typeof targetSchema>;
type RemoveTarget = Pick<TargetValues, "tenantId" | "membershipId">;
type TargetAction =
  | (RemoveTarget & { action: "assign" | "revoke"; roleCode: string })
  | (RemoveTarget & { action: "remove" });

export function MembersPage() {
  const queryClient = useQueryClient();
  const { tenantId: scopedTenantId } = useParams();
  const tenantsQuery = useQuery({ queryKey: ["tenants"], queryFn: getMyTenants });
  const [notice, setNotice] = useState<{ kind: "success" | "error"; text: string } | null>(null);
  const [removeTarget, setRemoveTarget] = useState<RemoveTarget | null>(null);
  const acceptForm = useForm<z.input<typeof acceptSchema>, unknown, AcceptValues>({
    resolver: zodResolver(acceptSchema),
  });
  const targetForm = useForm<z.input<typeof targetSchema>, unknown, TargetValues>({
    resolver: zodResolver(targetSchema),
    defaultValues: { tenantId: scopedTenantId ?? "" },
  });
  useEffect(() => {
    targetForm.setValue("tenantId", scopedTenantId ?? "");
  }, [scopedTenantId, targetForm.setValue]);
  const selectedTenantId = targetForm.watch("tenantId");
  const selectedTenant = tenantsQuery.data?.find(
    (tenant) => String(tenant.tenantId) === selectedTenantId,
  );
  const permissionsQuery = useQuery({
    queryKey: ["tenant-permissions", selectedTenantId],
    queryFn: () => getTenantPermissions(selectedTenantId),
    enabled: selectedTenant !== undefined,
    staleTime: 0,
    refetchOnMount: "always",
    refetchOnWindowFocus: true,
    retry: false,
  });
  const canAssignRoles =
    permissionsQuery.data?.permissions.includes(TENANT_ROLES_ASSIGN) === true;
  const canRemoveMembers =
    permissionsQuery.data?.permissions.includes(TENANT_MEMBERS_REMOVE) === true;

  const acceptMutation = useMutation({
    mutationFn: acceptMembership,
    onSuccess: async () => {
      setNotice({ kind: "success", text: "Membership invitation accepted." });
      acceptForm.reset();
      await queryClient.invalidateQueries({ queryKey: ["tenants"] });
    },
    onError: (error: unknown) => setNotice({ kind: "error", text: toApiRequestError(error).message }),
  });
  const targetMutation = useMutation({
    mutationFn: async (variables: TargetAction) => {
      if (variables.action === "assign") {
        return assignRole(variables.tenantId, variables.membershipId, {
          roleCode: variables.roleCode,
        });
      }
      if (variables.action === "revoke") {
        return revokeRole(
          variables.tenantId,
          variables.membershipId,
          variables.roleCode,
        );
      }
      return removeMember(variables.tenantId, variables.membershipId);
    },
    onSuccess: async (_result, variables) => {
      setNotice({
        kind: "success",
        text: variables.action === "assign"
          ? "Role assigned."
          : variables.action === "revoke"
            ? "Role revoked."
            : "Member removed.",
      });
      setRemoveTarget(null);
      targetForm.reset();
      await queryClient.invalidateQueries({ queryKey: ["tenant-permissions", variables.tenantId] });
      await queryClient.invalidateQueries({ queryKey: ["tenants"] });
    },
    onError: (error: unknown) => setNotice({ kind: "error", text: toApiRequestError(error).message }),
  });

  function runTargetAction(action: "assign" | "revoke" | "remove") {
    void targetForm.handleSubmit((values) => {
      setNotice(null);
      if (action === "remove") {
        setRemoveTarget({ tenantId: values.tenantId, membershipId: values.membershipId });
        return;
      }
      const roleCode = values.roleCode?.trim();
      if (!roleCode) {
        targetForm.setError("roleCode", { type: "required", message: "Enter a role code." });
        return;
      }
      targetMutation.mutate({
        action,
        tenantId: values.tenantId,
        membershipId: values.membershipId,
        roleCode,
      });
    })();
  }

  return (
    <>
      <PageHeading
        eyebrow={scopedTenantId ? `Tenant ${scopedTenantId} management` : "Tenant management"}
        title="Members & roles"
        description={scopedTenantId
          ? "Manage members in this tenant context. The API remains authoritative for tenant permissions."
          : "Select a tenant to manage supported membership actions. The API remains authoritative for tenant permissions."}
      />
      {notice && <div className="mb-5"><Notice kind={notice.kind}>{notice.text}</Notice></div>}
      {tenantsQuery.isError && (
        <div className="mb-5">
          <Notice>{toApiRequestError(tenantsQuery.error).message}</Notice>
          <Button className="mt-3" size="sm" variant="secondary" onClick={() => void tenantsQuery.refetch()}>Retry</Button>
        </div>
      )}
      <div className="grid gap-5 xl:grid-cols-[.8fr_1.2fr]">
        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
          <div className="mb-5 flex items-center gap-3">
            <span className="grid size-10 place-items-center rounded-xl bg-emerald-50 text-emerald-600 dark:bg-emerald-950/50 dark:text-emerald-300">
              <UserRoundPlus className="size-5" />
            </span>
            <div>
              <h2 className="text-sm font-bold">Accept an invitation</h2>
              <p className="mt-1 text-xs text-slate-500">The API verifies that the current user is the invitee.</p>
            </div>
          </div>
          <form
            className="space-y-4"
            onSubmit={acceptForm.handleSubmit((values) => {
              setNotice(null);
              acceptMutation.mutate(values.membershipId);
            })}
            noValidate
          >
            <Field label="Membership ID" htmlFor="accept-membership-id" error={acceptForm.formState.errors.membershipId?.message}>
              <TextInput id="accept-membership-id" type="number" min="1" {...acceptForm.register("membershipId")} />
            </Field>
            <Button type="submit" disabled={acceptMutation.isPending}>
              {acceptMutation.isPending ? "Accepting…" : "Accept invitation"}
            </Button>
          </form>
        </section>

        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
          <div className="mb-5 flex items-center gap-3">
            <span className="grid size-10 place-items-center rounded-xl bg-blue-50 text-blue-600 dark:bg-blue-950/50 dark:text-blue-300">
              <KeyRound className="size-5" />
            </span>
            <div>
              <h2 className="text-sm font-bold">Membership administration</h2>
              <p className="mt-1 text-xs text-slate-500">Assign/revoke a role or remove a member by known IDs.</p>
            </div>
          </div>
          <div className="space-y-4">
            <Field label="Tenant" htmlFor="target-tenant" error={targetForm.formState.errors.tenantId?.message}>
              <select
                id="target-tenant"
                className="field-control"
                disabled={Boolean(scopedTenantId)}
                {...targetForm.register("tenantId")}
              >
                <option value="">Select a tenant</option>
                {scopedTenantId && !tenantsQuery.data?.some((tenant) => String(tenant.tenantId) === scopedTenantId) && (
                  <option value={scopedTenantId}>Tenant ID {scopedTenantId}</option>
                )}
                {tenantsQuery.data?.map((tenant) => tenant.tenantId === undefined ? null : (
                  <option value={String(tenant.tenantId)} key={String(tenant.tenantId)}>
                    {tenant.displayName ?? "Unnamed tenant"} · ID {tenant.tenantId}
                  </option>
                ))}
              </select>
            </Field>
            {tenantsQuery.isPending && <Skeleton className="h-10" />}
            {selectedTenant && permissionsQuery.isPending && <Skeleton className="h-10" />}
            {selectedTenant && permissionsQuery.isError && (
              <div>
                <Notice>Tenant permissions could not be verified.</Notice>
                <Button className="mt-3" size="sm" variant="secondary" onClick={() => void permissionsQuery.refetch()}>
                  Retry
                </Button>
              </div>
            )}
            {selectedTenant && permissionsQuery.data && (canAssignRoles || canRemoveMembers) && (
              <form className="space-y-4" onSubmit={(event) => event.preventDefault()} noValidate>
                <Field label="Membership ID" htmlFor="target-membership" error={targetForm.formState.errors.membershipId?.message}>
                  <TextInput id="target-membership" type="number" min="1" {...targetForm.register("membershipId")} />
                </Field>
                {canAssignRoles && (
                  <Field label="Role code" htmlFor="target-role" hint="The backend validates the role and assignment policy." error={targetForm.formState.errors.roleCode?.message}>
                    <TextInput id="target-role" maxLength={50} {...targetForm.register("roleCode")} />
                  </Field>
                )}
                <div className="flex flex-wrap gap-2 border-t border-slate-100 pt-4 dark:border-slate-800">
                  {canAssignRoles && (
                    <>
                      <Button type="button" size="sm" disabled={targetMutation.isPending} onClick={() => runTargetAction("assign")}>
                        Assign role
                      </Button>
                      <Button type="button" size="sm" variant="secondary" disabled={targetMutation.isPending} onClick={() => runTargetAction("revoke")}>
                        Revoke role
                      </Button>
                    </>
                  )}
                  {canRemoveMembers && (
                    <Button type="button" size="sm" variant="danger" disabled={targetMutation.isPending} onClick={() => runTargetAction("remove")}>
                      <UserRoundX className="size-3.5" /> Remove member
                    </Button>
                  )}
                </div>
              </form>
            )}
            {selectedTenant && permissionsQuery.data && !canAssignRoles && !canRemoveMembers && (
              <Notice>
                {selectedTenant.tenantTypeCode?.toUpperCase() === "PERSONAL"
                  ? "Personal workspaces do not support additional members or membership administration."
                  : "Your account does not have membership-administration permissions for this tenant."}
              </Notice>
            )}
            {!selectedTenant && !tenantsQuery.isPending && (
              <p className="text-xs text-slate-500">Select a tenant you belong to to check its effective permissions.</p>
            )}
          </div>
        </section>
      </div>

      <Dialog
        open={removeTarget !== null}
        onOpenChange={(open) => { if (!open) setRemoveTarget(null); }}
        title="Remove tenant member?"
        description="This request will be sent to the backend, which verifies that your account may remove this member."
      >
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={() => setRemoveTarget(null)}>Cancel</Button>
          <Button
            type="button"
            variant="danger"
            disabled={targetMutation.isPending || removeTarget === null}
            onClick={() => {
              if (!removeTarget) return;
              targetMutation.mutate({ action: "remove", ...removeTarget });
            }}
          >
            {targetMutation.isPending ? "Removing…" : "Remove member"}
          </Button>
        </div>
      </Dialog>

      <section className="mt-6 rounded-2xl border border-amber-200 bg-amber-50/70 p-5 dark:border-amber-900/60 dark:bg-amber-950/20">
        <h2 className="text-sm font-bold text-amber-900 dark:text-amber-200">Current API limitation</h2>
        <p className="mt-1 text-xs leading-5 text-amber-800 dark:text-amber-300">
          There is no endpoint to list tenant members, invitations, roles, or permissions. This screen does not invent a directory or role catalog; operations may be rejected by the server if your account lacks permission.
        </p>
      </section>
    </>
  );
}
