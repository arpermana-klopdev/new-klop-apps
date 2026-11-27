import {
  ArrowUpRight,
  Bell,
  ClipboardList,
  Database,
  FileText,
  Settings2,
  ShieldCheck,
} from "lucide-react";
import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getOrganizationTypes } from "../../api/tenants";
import { getRolePermissionMatrixAccess } from "../../api/rolePermissionMatrix";
import { toApiRequestError } from "../../api/client";
import type { OrganizationType } from "../../api/contracts";
import { Button, Notice, PageHeading, Skeleton, StatusBadge } from "../../components/ui";
import { RolePermissionMatrixPage } from "./RolePermissionMatrixPage";

const setupSections = [
  {
    title: "Registration Setup",
    route: "/platform-setup/registration",
    description: "Review registration and onboarding readiness without changing the existing registration flow.",
    status: "Read API unavailable",
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
    description: "View organization-type reference data exposed by the current API.",
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
    description: "Template and activation state management requires protected backend contracts.",
    status: "API unavailable",
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
  });
  const sections = setupSections.filter(({ route }) =>
    route !== "/platform-setup/access-approval" || matrixAccessQuery.data?.canRead === true,
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
  });
  const sections = setupSections.filter(({ route }) =>
    route !== "/platform-setup/access-approval" || matrixAccessQuery.data?.canRead === true,
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
  const configurationAreas = [
    "Registration type availability",
    "Email verification requirement",
    "Terms consent requirement",
    "Onboarding submission behavior",
  ];

  return (
    <SetupSectionPage
      title="Registration Setup"
      description="Readiness for existing PERSONAL and ORGANIZATION registration behavior; this page does not alter registration or authentication."
      status="Read API unavailable"
    >
      <p className="mb-5 text-sm text-slate-600 dark:text-slate-300">
        The backend registration flow remains authoritative. The current frontend API does not expose these database-backed configuration values, so no value or default is inferred here.
      </p>
      <dl className="divide-y divide-slate-100 dark:divide-slate-800">
        {configurationAreas.map((label) => (
          <div key={label} className="flex flex-wrap items-center justify-between gap-3 py-3 first:pt-0 last:pb-0">
            <dt className="text-sm font-medium">{label}</dt>
            <dd className="text-xs text-slate-500 dark:text-slate-400">Not exposed by the current API</dd>
          </div>
        ))}
      </dl>
      <div className="mt-5">
        <Notice kind="info">
          Existing Register, email-verification, and Terms enforcement APIs are unchanged. No settings are editable from this page.
        </Notice>
      </div>
    </SetupSectionPage>
  );
}

export function MasterDataSetupPage() {
  const organizationTypesQuery = useQuery({
    queryKey: ["platform-setup", "master-data", "organization-types"],
    queryFn: getOrganizationTypes,
  });
  const organizationTypes = organizationTypesQuery.data ?? [];

  return (
    <SetupSectionPage
      title="Master Data"
      description="Read-only view of the existing reference data endpoint. No generic master-data administration API is available."
      status="Partial read only"
    >
      <section aria-labelledby="setup-organization-types-heading">
        <div className="mb-4">
          <h3 id="setup-organization-types-heading" className="text-sm font-semibold">Organization types</h3>
          <p className="mt-1 text-xs text-slate-500">
            Source: GET /api/v1/master/organization-types
          </p>
        </div>
        {organizationTypesQuery.isPending ? (
          <div className="space-y-2" role="status" aria-label="Loading organization types">
            <Skeleton className="h-12" />
            <Skeleton className="h-12" />
          </div>
        ) : organizationTypesQuery.isError ? (
          <div>
            <Notice>{toApiRequestError(organizationTypesQuery.error).message}</Notice>
            <Button
              className="mt-3"
              size="sm"
              variant="secondary"
              onClick={() => void organizationTypesQuery.refetch()}
            >
              Retry
            </Button>
          </div>
        ) : organizationTypes.length === 0 ? (
          <p className="rounded-xl border border-dashed border-slate-300 px-4 py-6 text-center text-sm text-slate-500 dark:border-slate-700">
            No organization types were returned by the existing API.
          </p>
        ) : (
          <OrganizationTypeList organizationTypes={organizationTypes} />
        )}
      </section>
      <div className="mt-5 border-t border-slate-100 pt-4 dark:border-slate-800">
        <p className="text-xs leading-5 text-slate-500 dark:text-slate-400">
          Other master-data catalogs, editing, and approval are not exposed by the current API. No records are changed here.
        </p>
      </div>
    </SetupSectionPage>
  );
}

function OrganizationTypeList({ organizationTypes }: { organizationTypes: OrganizationType[] }) {
  return (
    <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
      {organizationTypes.map((organizationType, index) => (
        <li
          key={organizationType.organizationTypeId ?? organizationType.code ?? `organization-type-${index}`}
          className="rounded-xl border border-slate-200 p-4 dark:border-slate-800"
        >
          <p className="text-sm font-semibold">{organizationType.name ?? "Name unavailable"}</p>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            {organizationType.code && <StatusBadge value={organizationType.code} />}
            {organizationType.countryCode && (
              <span className="text-xs text-slate-500">{organizationType.countryCode}</span>
            )}
          </div>
        </li>
      ))}
    </ul>
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
  return (
    <UnavailableSetupPage
      title="Notifications"
      description="Notification template, channel, and activation readiness."
      status="API unavailable"
      detail="The current API does not expose notification templates, delivery-channel settings, activation state, or approval history."
    />
  );
}

export function AccessApprovalPage() {
  return <RolePermissionMatrixPage />;
}
