import {
  ArrowUpRight,
  Bell,
  ClipboardList,
  Database,
  FileText,
  Settings2,
  ShieldCheck,
} from "lucide-react";
import { useState, type ReactNode } from "react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getRegistrationPolicy } from "../../api/auth";
import { getCurrentTerms } from "../../api/legal";
import { getOrganizationTypes, getTenantTypes } from "../../api/tenants";
import { getRolePermissionMatrixAccess } from "../../api/rolePermissionMatrix";
import { toApiRequestError } from "../../api/client";
import type { OrganizationType } from "../../api/contracts";
import { Button, Notice, PageHeading, Skeleton, StatusBadge } from "../../components/ui";
import { RolePermissionMatrixPage } from "./RolePermissionMatrixPage";
import { NotificationManagementPage } from "./NotificationManagementPage";

const setupSections = [
  {
    title: "Registration Setup",
    route: "/platform-setup/registration",
    description: "Inspect effective registration policy and published Terms readiness from the existing APIs.",
    status: "Read only",
    icon: ClipboardList,
  },
  {
    title: "Legal Documents",
    route: "/platform-setup/legal-documents",
    description: "View published Terms metadata and PDF, or preview the existing local draft.",
    status: "Read only",
    icon: FileText,
  },
  {
    title: "Master Data",
    route: "/platform-setup/master-data",
    description: "Search active tenant and organization reference catalogs from the API.",
    status: "Partial read only",
    icon: Database,
  },
  {
    title: "System Configuration",
    route: "/platform-setup/system-configuration",
    description: "Configuration values and approval controls are not exposed to the frontend.",
    status: "API unavailable",
    icon: Settings2,
  },
  {
    title: "Notifications",
    route: "/platform-setup/notifications",
    description: "Manage versioned email templates, delivery history, channel readiness, and safe settings.",
    status: "Email only",
    icon: Bell,
  },
  {
    title: "Role & Permission Matrix",
    route: "/platform-setup/access-approval",
    description: "Manage database-backed permission grants across platform and tenant contexts.",
    status: "Database-backed",
    icon: ShieldCheck,
  },
] as const;

function SetupSectionNav() {
  const matrixAccessQuery = useQuery({
    queryKey: ["platform-role-permission-matrix", "access"],
    queryFn: getRolePermissionMatrixAccess,
    staleTime: 0,
    refetchOnMount: "always",
    retry: false,
  });
  const sections = setupSections.filter(({ route }) =>
    route !== "/platform-setup/access-approval" || (matrixAccessQuery.isSuccess && !matrixAccessQuery.isFetching && matrixAccessQuery.data?.canRead === true),
  );
  return (
    <nav aria-label="Platform Setup sections" className="mb-6 flex flex-wrap gap-2">
      {sections.map(({ title, route }) => (
        <Link
          key={route}
          to={route}
          className="rounded-full border border-slate-200 px-3 py-1.5 text-xs font-medium text-slate-600 transition hover:border-brand-300 hover:text-brand-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:border-slate-700 dark:text-slate-300 dark:hover:border-brand-700"
        >
          {title}
        </Link>
      ))}
    </nav>
  );
}

export function SetupSectionPage({
  title,
  description,
  status,
  children,
}: {
  title: string;
  description: string;
  status: string;
  children: ReactNode;
}) {
  return (
    <>
      <PageHeading
        eyebrow="Platform administration / Platform Setup"
        title={title}
        description={description}
        action={
          <Link to="/platform-setup">
            <Button variant="secondary">
              Platform Setup <ArrowUpRight aria-hidden="true" className="size-4" />
            </Button>
          </Link>
        }
      />
      <SetupSectionNav />
      <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-sm font-bold text-slate-950 dark:text-white">Current implementation status</h2>
          <StatusBadge value={status} />
        </div>
        {children}
      </section>
    </>
  );
}

export function PlatformSetupPage() {
  const matrixAccessQuery = useQuery({
    queryKey: ["platform-role-permission-matrix", "access"],
    queryFn: getRolePermissionMatrixAccess,
    staleTime: 0,
    refetchOnMount: "always",
    retry: false,
  });
  const sections = setupSections.filter(({ route }) =>
    route !== "/platform-setup/access-approval" || (matrixAccessQuery.isSuccess && !matrixAccessQuery.isFetching && matrixAccessQuery.data?.canRead === true),
  );
  return (
    <>
      <PageHeading
        eyebrow="Platform administration"
        title="Platform Setup"
        description="A single entry point for platform configuration and operational setup, with availability based only on verified backend capabilities."
      />
      <Notice kind="info">
        The unified Role & Permission Matrix uses database-backed policy, authorization, concurrency, and audit APIs. Other Platform Setup Center enhancements remain read-only or on HOLD.
      </Notice>
      <section aria-label="Platform Setup sections" className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {sections.map(({ title, route, description, status, icon: Icon }) => (
          <Link
            key={route}
            to={route}
            className="group flex min-h-40 flex-col rounded-2xl border border-slate-200 bg-white p-5 shadow-soft transition hover:border-brand-200 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:border-slate-800 dark:bg-slate-900 dark:hover:border-brand-700"
          >
            <div className="flex items-start justify-between gap-3">
              <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300">
                <Icon aria-hidden="true" className="size-5" />
              </span>
              <StatusBadge value={status} />
            </div>
            <span className="mt-4 text-sm font-semibold text-slate-950 dark:text-white">{title}</span>
            <span className="mt-1 text-xs leading-5 text-slate-500 dark:text-slate-400">{description}</span>
          </Link>
        ))}
      </section>
    </>
  );
}

export function RegistrationSetupPage() {
  const policyQuery = useQuery({
    queryKey: ["platform-setup", "registration-policy"],
    queryFn: getRegistrationPolicy,
    staleTime: 0,
    retry: false,
    refetchOnMount: "always",
  });
  const policy = policyQuery.isSuccess && !policyQuery.isFetching ? policyQuery.data : undefined;

  return (
    <SetupSectionPage
      title="Registration Setup"
      description="Inspect effective registration policy for PERSONAL and ORGANIZATION without altering authentication or configuration."
      status="Read only"
    >
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h3 className="text-sm font-semibold">Effective registration policy</h3>
          <p className="mt-1 text-xs text-slate-500">Source: GET /api/v1/auth/registration-policy</p>
        </div>
        <Button size="sm" variant="secondary" onClick={() => void policyQuery.refetch()} disabled={policyQuery.isFetching}>Refresh policy</Button>
      </div>
      {policyQuery.isFetching || policyQuery.isPending ? (
        <div role="status" aria-label="Loading registration policy"><Skeleton className="h-28" /></div>
      ) : policyQuery.isError ? (
        <Notice>Registration policy could not be verified. {toApiRequestError(policyQuery.error).message}</Notice>
      ) : policy ? (
        <>
          <dl className="divide-y divide-slate-100 dark:divide-slate-800">
            <div className="flex flex-wrap items-center justify-between gap-3 py-3">
              <dt className="text-sm font-medium">Terms consent</dt>
              <dd><StatusBadge value={policy.termsRequired ? "Required" : "Not required by effective policy"} /></dd>
            </div>
            <div className="flex flex-wrap items-center justify-between gap-3 py-3">
              <dt className="text-sm font-medium">Password length</dt>
              <dd className="text-sm">{policy.passwordMinLength}–{policy.passwordMaxLength} characters</dd>
            </div>
          </dl>
          <div className="mt-5 grid gap-3 md:grid-cols-2">
            {(["PERSONAL", "ORGANIZATION"] as const).map((scope) => (
              <RegistrationScopeReadiness key={scope} scope={scope}
                enabled={policy.allowedRegistrationTypes.includes(scope)} termsRequired={policy.termsRequired} />
            ))}
          </div>
        </>
      ) : <Notice>Registration policy is unavailable.</Notice>}
      <div className="mt-5">
        <Notice kind="info">
          These are effective runtime values, not editable database settings. Email delivery, verification configuration, and onboarding submission behavior are not exposed by this policy API. No setting is changed here.
        </Notice>
      </div>
    </SetupSectionPage>
  );
}

function RegistrationScopeReadiness({ scope, enabled, termsRequired }: {
  scope: "PERSONAL" | "ORGANIZATION";
  enabled: boolean;
  termsRequired: boolean;
}) {
  const terms = useQuery({
    queryKey: ["platform-setup", "registration-terms-readiness", scope],
    queryFn: () => getCurrentTerms(scope),
    staleTime: 0,
    retry: false,
    refetchOnMount: "always",
  });
  const published = terms.isSuccess && terms.data.registrationType === scope &&
    terms.data.publicationStatus === "PUBLISHED" ? terms.data : undefined;
  const missing = terms.isError && toApiRequestError(terms.error).code === "TERMS_UNAVAILABLE";
  return (
    <section aria-label={scope + " registration"} className="rounded-xl border border-slate-200 p-4 dark:border-slate-700">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h4 className="text-sm font-semibold">{scope}</h4>
        <StatusBadge value={enabled ? "Registration enabled" : "Registration disabled"} />
      </div>
      <p className="mt-3 text-xs font-medium text-slate-500">Published Terms</p>
      {terms.isPending || terms.isFetching ? (
        <p role="status" className="mt-1 text-sm">Checking Terms readiness...</p>
      ) : published ? (
        <div className="mt-1 text-sm">
          <p>{published.title}</p>
          <p className="text-xs text-slate-500">Version {published.version}</p>
        </div>
      ) : missing ? (
        <p className="mt-1 text-sm">No published Terms for this scope.</p>
      ) : (
        <p role="alert" className="mt-1 text-sm">Terms readiness could not be verified.</p>
      )}
      {enabled && termsRequired && !terms.isFetching && !published && (
        <p className="mt-2 text-xs text-amber-700 dark:text-amber-300">Required Terms are not verified; registration readiness is incomplete.</p>
      )}
      <Button className="mt-3" size="sm" variant="secondary" onClick={() => void terms.refetch()} disabled={terms.isFetching}>Refresh Terms</Button>
    </section>
  );
}

export function MasterDataSetupPage() {
  return (
    <SetupSectionPage
      title="Master Data"
      description="Read-only active reference catalogs from the database-backed API. Catalog availability is not the same as effective registration or access permission."
      status="Partial read only"
    >
      <div className="space-y-6">
        <ReferenceCatalog title="Tenant types" endpoint="tenant-types" load={getTenantTypes} />
        <ReferenceCatalog title="Organization types" endpoint="organization-types" load={getOrganizationTypes} />
      </div>
      <div className="mt-5 border-t border-slate-100 pt-4 dark:border-slate-800">
        <p className="text-xs leading-5 text-slate-500 dark:text-slate-400">
          Other master-data catalogs, editing, and approval are not exposed by the current API. No records are changed here.
        </p>
      </div>
    </SetupSectionPage>
  );
}

function ReferenceCatalog({ title, endpoint, load }: {
  title: string;
  endpoint: "tenant-types" | "organization-types";
  load: () => Promise<OrganizationType[]>;
}) {
  const [search, setSearch] = useState("");
  const query = useQuery({
    queryKey: ["platform-setup", "master-data", endpoint],
    queryFn: load,
    staleTime: 0,
    refetchOnMount: "always",
    retry: false,
  });
  const rows = query.isSuccess && !query.isFetching ? query.data : undefined;
  const term = search.trim().toLocaleLowerCase();
  const visible = (rows ?? []).filter((row) =>
    [row.code, row.name, row.countryCode].some((value) => value?.toLocaleLowerCase().includes(term)),
  );
  return (
    <section aria-label={title} className="rounded-xl border border-slate-200 p-4 dark:border-slate-700">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h3 className="text-sm font-semibold">{title}</h3>
          <p className="mt-1 text-xs text-slate-500">Source: GET /api/v1/master/{endpoint}</p>
        </div>
        <Button size="sm" variant="secondary" onClick={() => void query.refetch()} disabled={query.isFetching}>
          Refresh
        </Button>
      </div>
      {query.isPending || query.isFetching ? (
        <div className="space-y-2" role="status" aria-label={"Loading " + title.toLowerCase()}><Skeleton className="h-12" /><Skeleton className="h-12" /></div>
      ) : query.isError ? (
        <Notice>{title} could not be loaded. {toApiRequestError(query.error).message}</Notice>
      ) : rows ? (
        <>
          <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
            <label className="text-xs font-medium">
              Search {title.toLowerCase()}
              <input className="mt-1 block rounded-lg border border-slate-300 bg-transparent px-3 py-2 text-sm dark:border-slate-600"
                value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Code or name" />
            </label>
            <p className="text-xs text-slate-500">{visible.length} of {rows.length} records</p>
          </div>
          {rows.length === 0 ? (
            <p className="py-4 text-sm text-slate-500">No active records were returned by the API.</p>
          ) : visible.length === 0 ? (
            <p className="py-4 text-sm text-slate-500">No records match your search.</p>
          ) : (
            <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
              {visible.map((row, index) => (
                <li key={row.organizationTypeId ?? row.code ?? index} className="rounded-xl border border-slate-200 p-4 dark:border-slate-800">
                  <p className="text-sm font-semibold">{row.name ?? "Name unavailable"}</p>
                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    {row.code && <StatusBadge value={row.code} />}
                    {row.countryCode && <span className="text-xs text-slate-500">{row.countryCode}</span>}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </>
      ) : <Notice>{title} are unavailable.</Notice>}
    </section>
  );
}

function UnavailableSetupPage({
  title,
  description,
  status,
  detail,
}: {
  title: string;
  description: string;
  status: string;
  detail: string;
}) {
  return (
    <SetupSectionPage title={title} description={description} status={status}>
      <p className="text-sm leading-6 text-slate-600 dark:text-slate-300">{detail}</p>
      <div className="mt-5">
        <Notice kind="info">
          No mutation controls are available. This page does not use a client-side role label as authorization.
        </Notice>
      </div>
    </SetupSectionPage>
  );
}

export function SystemConfigurationPage() {
  return (
    <UnavailableSetupPage
      title="System Configuration"
      description="System-wide runtime, security, and business configuration status."
      status="API unavailable"
      detail="Configuration reads may exist inside backend services, but no frontend-facing configuration API is mapped. Sensitive values are not requested or displayed."
    />
  );
}

export function NotificationsSetupPage() {
  return <NotificationManagementPage />;
}

export function AccessApprovalPage() {
  return <RolePermissionMatrixPage />;
}
