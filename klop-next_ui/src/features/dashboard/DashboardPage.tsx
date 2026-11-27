import { ArrowUpRight, Building2, CircleCheck, CircleDashed, MailCheck } from "lucide-react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getMyTenants } from "../../api/tenants";
import type { TenantSummary } from "../../api/contracts";
import { useAuth } from "../../app/AuthContext";
import { brand } from "../../app/brand";
import { modulesForContext } from "../../app/modules";
import { Button, Notice, PageHeading, Skeleton, StatusBadge } from "../../components/ui";

export function DashboardPage() {
  const { profile } = useAuth();
  const tenantsQuery = useQuery({ queryKey: ["tenants"], queryFn: getMyTenants });
  const tenants = tenantsQuery.data ?? [];
  const verified = Boolean(profile?.emailVerifiedAtUtc);

  return (
    <>
      <PageHeading
        eyebrow={`${brand.applicationName} · ${brand.tagline}`}
        title="Platform overview"
        description="A concise view of platform modules and the account-scoped tenant information currently returned by the API."
        action={
          <Link to="/tenants">
            <Button variant="secondary">
              View my tenants <ArrowUpRight aria-hidden="true" className="size-4" />
            </Button>
          </Link>
        }
      />

      <section
        aria-label="Account overview"
        className="mb-8 grid gap-4 lg:grid-cols-[minmax(0,1.5fr)_minmax(260px,1fr)]"
      >
        <div className="overflow-hidden rounded-2xl border border-blue-100 bg-gradient-to-br from-white via-white to-blue-50 p-5 shadow-soft dark:border-slate-800 dark:from-slate-900 dark:via-slate-900 dark:to-blue-950/30 sm:p-7">
          <div className="flex flex-wrap items-start justify-between gap-5">
            <div className="max-w-xl">
              <span className="inline-flex items-center gap-2 rounded-full bg-blue-50 px-3 py-1 text-[11px] font-semibold text-blue-700 dark:bg-blue-950/60 dark:text-blue-300">
                <CircleCheck aria-hidden="true" className="size-3.5" />
                Account context
              </span>
              <h2 className="mt-4 text-xl font-bold tracking-tight text-slate-950 dark:text-white sm:text-2xl">
                Your workspace memberships
              </h2>
              <p className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                This count reflects only tenants associated with your account. It is not a count of all tenants on the platform.
              </p>
            </div>
            <div className="min-w-24 rounded-2xl border border-white/80 bg-white/80 px-5 py-3 text-center shadow-sm dark:border-slate-700 dark:bg-slate-900/80">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">My tenants</p>
              {tenantsQuery.isPending ? (
                <Skeleton className="mx-auto mt-2 h-8 w-12" />
              ) : (
                <p className="mt-1 text-2xl font-bold text-slate-950 dark:text-white" aria-live="polite">
                  {tenantsQuery.isError ? "—" : tenants.length}
                </p>
              )}
            </div>
          </div>
          <div className="mt-6 flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-blue-100 pt-4 text-xs dark:border-slate-800">
            <span className="inline-flex items-center gap-1.5 text-slate-600 dark:text-slate-300">
              {verified
                ? <MailCheck aria-hidden="true" className="size-4 text-emerald-600 dark:text-emerald-300" />
                : <CircleDashed aria-hidden="true" className="size-4 text-amber-600 dark:text-amber-300" />}
              Email {verified ? "verified" : "not verified"}
            </span>
            <span className="text-slate-300 dark:text-slate-700" aria-hidden="true">•</span>
            <span className="text-slate-500">
              Access and authorization are enforced by {brand.backendName}.
            </span>
          </div>
        </div>

        <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
          <div className="flex items-start gap-3">
            <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300">
              <Building2 aria-hidden="true" className="size-5" />
            </span>
            <div>
              <h2 className="text-sm font-bold text-slate-950 dark:text-white">Platform context</h2>
              <p className="mt-1 text-xs leading-5 text-slate-500 dark:text-slate-400">
                Platform-wide totals and effective role information are not included in the current API response.
              </p>
            </div>
          </div>
          <p className="mt-5 border-t border-slate-100 pt-4 text-xs leading-5 text-slate-500 dark:border-slate-800 dark:text-slate-400">
            No platform role or tenant membership is inferred from this account profile.
          </p>
        </div>
      </section>

      {tenantsQuery.isError && (
        <div className="mb-7 flex flex-wrap items-center justify-between gap-3">
          <Notice>
            {tenantsQuery.error instanceof Error
              ? tenantsQuery.error.message
              : "Unable to load your tenant memberships."}
          </Notice>
          <Button size="sm" variant="secondary" onClick={() => void tenantsQuery.refetch()}>
            Retry
          </Button>
        </div>
      )}

      <section aria-labelledby="platform-modules-heading" className="mb-9">
        <div className="mb-4">
          <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-brand-600">
            Platform administration
          </p>
          <h2 id="platform-modules-heading" className="mt-1 text-lg font-bold text-slate-950 dark:text-white">
            Platform modules
          </h2>
          <p className="mt-1 max-w-2xl text-sm text-slate-500 dark:text-slate-400">
            These modules need supporting API contracts before they can show platform data or perform administration.
          </p>
        </div>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {modulesForContext("platform")
            .filter(
              (module) =>
                module.group === "Platform" &&
                module.id !== "overview" &&
                module.id !== "tenants" &&
                module.route !== null,
            )
            .map(({ id, label, route, icon: Icon, availability, description }) => (
              <Link
                key={id}
                to={route ?? "/"}
                className="group flex min-h-32 items-start gap-3 rounded-2xl border border-slate-200 bg-white p-4 shadow-soft transition hover:border-brand-200 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:border-slate-800 dark:bg-slate-900 dark:hover:border-brand-700"
              >
                <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300">
                  <Icon aria-hidden="true" className="size-5" />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="flex flex-wrap items-center justify-between gap-2">
                    <span className="text-sm font-semibold text-slate-900 dark:text-white">{label}</span>
                    <span className="rounded-full bg-slate-100 px-2 py-1 text-[10px] font-semibold text-slate-600 dark:bg-slate-800 dark:text-slate-300">
                      {availability === "coming-soon" ? "Coming soon" : "Available"}
                    </span>
                  </span>
                  <span className="mt-2 block text-xs leading-5 text-slate-500 dark:text-slate-400">
                    {description}
                  </span>
                </span>
              </Link>
            ))}
        </div>
      </section>

      <section aria-labelledby="tenant-memberships-heading">
        <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
          <div>
            <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-brand-600">Tenant context</p>
            <h2 id="tenant-memberships-heading" className="mt-1 text-lg font-bold text-slate-950 dark:text-white">
              My tenant memberships
            </h2>
            <p className="mt-1 text-sm text-slate-500 dark:text-slate-400">
              Only tenant information returned for your authenticated account is shown here.
            </p>
          </div>
          <Link to="/tenants" className="text-xs font-semibold text-brand-600 hover:text-brand-700">
            Manage tenants
          </Link>
        </div>

        {tenantsQuery.isPending ? (
          <div className="grid gap-3 md:grid-cols-2">
            <Skeleton className="h-28" />
            <Skeleton className="h-28" />
          </div>
        ) : tenantsQuery.isError ? null : tenants.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-slate-300 bg-white px-6 py-10 text-center dark:border-slate-700 dark:bg-slate-900">
            <Building2 aria-hidden="true" className="mx-auto size-6 text-slate-400" />
            <p className="mt-3 text-sm font-semibold text-slate-900 dark:text-white">
              No tenant memberships for this account
            </p>
            <p className="mx-auto mt-1 max-w-lg text-xs leading-5 text-slate-500">
              This is a valid account state and does not indicate the number of tenants on the platform or whether you have a platform role.
            </p>
            <Link to="/tenants" className="mt-4 inline-block">
              <Button size="sm" variant="secondary">Open tenant management</Button>
            </Link>
          </div>
        ) : (
          <TenantContextSection tenants={tenants} />
        )}
      </section>
    </>
  );
}

function TenantContextSection({ tenants }: { tenants: TenantSummary[] }) {
  const groups = [
    { type: "PERSONAL", title: "Personal overview" },
    { type: "ORGANIZATION", title: "Organization overview" },
  ];
  const knownTypes = new Set(groups.map((group) => group.type));
  const otherTenants = tenants.filter(
    (tenant) => !knownTypes.has((tenant.tenantTypeCode ?? "").toUpperCase()),
  );
  const visibleGroups = [
    ...groups.map((group) => ({
      ...group,
      tenants: tenants.filter(
        (tenant) => (tenant.tenantTypeCode ?? "").toUpperCase() === group.type,
      ),
    })),
    ...(otherTenants.length ? [{ type: "OTHER", title: "Other tenant types", tenants: otherTenants }] : []),
  ].filter((group) => group.tenants.length > 0);

  if (visibleGroups.length === 0) {
    return (
      <div className="rounded-2xl border border-slate-200 bg-white p-5 text-sm text-slate-600 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
        Tenant memberships were returned, but their type is not available in the response.
      </div>
    );
  }

  return (
    <div className="space-y-7">
      {visibleGroups.map((group) => (
        <div key={group.type}>
          <h3 className="mb-3 text-sm font-semibold text-slate-700 dark:text-slate-200">{group.title}</h3>
          <div className="grid gap-3 md:grid-cols-2">
            {group.tenants.map((tenant, index) => (
              <TenantCard
                key={`${tenant.tenantId ?? group.type}-${index}`}
                tenant={tenant}
              />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function TenantCard({ tenant }: { tenant: TenantSummary }) {
  return (
    <Link
      to="/tenants"
      className="group rounded-2xl border border-slate-200 bg-white p-4 shadow-soft transition hover:border-brand-200 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:border-slate-800 dark:bg-slate-900 dark:hover:border-brand-700"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <div className="grid size-10 shrink-0 place-items-center rounded-xl bg-blue-50 text-brand-600 dark:bg-blue-950/50 dark:text-blue-300">
            <Building2 aria-hidden="true" className="size-5" />
          </div>
          <div className="min-w-0">
            <p className="truncate text-sm font-bold text-slate-900 dark:text-white">
              {tenant.displayName ?? "Unnamed tenant"}
            </p>
            <p className="mt-1 truncate text-xs text-slate-500">
              {tenant.tenantCode ?? "Code unavailable"}
            </p>
          </div>
        </div>
        <ArrowUpRight aria-hidden="true" className="size-4 shrink-0 text-slate-400 transition group-hover:text-brand-600" />
      </div>
      <div className="mt-4 flex flex-wrap items-center gap-2">
        <StatusBadge value={tenant.tenantTypeCode ?? "Type unavailable"} />
        <StatusBadge value={tenant.tenantStatusCode ?? "Status unavailable"} />
        <span className="text-xs text-slate-500">
          Membership: {tenant.membershipStatusCode ?? "Unavailable"}
        </span>
      </div>
    </Link>
  );
}
