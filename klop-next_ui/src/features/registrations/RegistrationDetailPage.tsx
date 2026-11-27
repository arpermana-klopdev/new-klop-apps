import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, RefreshCw } from "lucide-react";
import { Link, useLocation, useNavigate, useParams } from "react-router-dom";
import { toApiRequestError } from "../../api/client";
import { Button, Notice, PageHeading, Skeleton, StatusBadge } from "../../components/ui";
import { getRegistrationDetail, getRegistrationTimeline, type RegistrationType } from "./api";

export function RegistrationDetailPage() {
  const { type: routeType, id: routeId } = useParams();
  const type = routeType?.toUpperCase() as RegistrationType;
  const id = Number(routeId);
  const validRoute = (type === "PERSONAL" || type === "ORGANIZATION") && Number.isSafeInteger(id) && id > 0;
  const location = useLocation();
  const navigate = useNavigate();
  const listPath = `/registrations/${type === "ORGANIZATION" ? "organization" : "personal"}`;
  const returnTo = (location.state as { returnTo?: string } | null)?.returnTo;

  const detailQuery = useQuery({
    queryKey: ["registrations", "detail", id],
    queryFn: () => getRegistrationDetail(id),
    enabled: validRoute,
  });
  const timelineQuery = useQuery({
    queryKey: ["registrations", "timeline", id],
    queryFn: () => getRegistrationTimeline(id),
    enabled: validRoute,
  });

  if (!validRoute) {
    return (
      <>
        <PageHeading eyebrow="Platform administration / registrations" title="Registration not found" />
        <Notice kind="info">The registration link is invalid.</Notice>
        <Link className="mt-4 inline-block text-sm font-semibold text-brand-700 dark:text-blue-300" to="/registrations">
          Return to Registration Center
        </Link>
      </>
    );
  }

  const detail = detailQuery.data;
  return (
    <>
      <PageHeading
        eyebrow="Platform administration / registrations / read-only detail"
        title={detail?.user.displayName || "Registration detail"}
        description="Read-only registration, account, profile, and tenant information."
        action={
          <div className="flex items-center gap-2">
            <Button
              variant="secondary"
              onClick={() => {
                if (returnTo?.startsWith("/registrations/")) navigate(returnTo);
                else navigate(listPath);
              }}
            >
              <ArrowLeft aria-hidden="true" className="size-4" /> Back
            </Button>
            <Button
              variant="secondary"
              disabled={detailQuery.isFetching || timelineQuery.isFetching}
              onClick={() => {
                void detailQuery.refetch();
                void timelineQuery.refetch();
              }}
            >
              <RefreshCw aria-hidden="true" className={`size-4 ${detailQuery.isFetching || timelineQuery.isFetching ? "animate-spin" : ""}`} />
              Refresh
            </Button>
          </div>
        }
      />

      {detailQuery.isPending ? (
        <div className="space-y-4" role="status" aria-label="Loading registration detail">
          <Skeleton className="h-52" /><Skeleton className="h-56" />
        </div>
      ) : detailQuery.isError ? (
        <div className="mb-5">
          <Notice>{toApiRequestError(detailQuery.error).message}</Notice>
          <Button className="mt-3" size="sm" variant="secondary" onClick={() => void detailQuery.refetch()}>Retry detail</Button>
        </div>
      ) : detail ? (
        <div className="space-y-5">
          <section aria-labelledby="registration-account-heading" className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h2 id="registration-account-heading" className="text-base font-bold">Account and application</h2>
                <p className="mt-1 text-xs text-slate-500">Registration application ID: {detail.registrationApplicationId}</p>
              </div>
              <div className="flex flex-wrap gap-2">
                <StatusBadge value={detail.application.registrationType} />
                <StatusBadge value={detail.application.applicationStatus} />
                <StatusBadge value={detail.user.accountStatus} />
              </div>
            </div>
            <dl className="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
              <DetailField label="Full Name" value={detail.user.displayName} />
              <DetailField label="Email" value={detail.user.email} />
              <DetailField label="Email verification" value={detail.user.emailVerifiedAtUtc ? `Verified · ${formatDateTime(detail.user.emailVerifiedAtUtc)}` : "Pending verification"} />
              <DetailField label="Registered" value={formatDateTime(detail.user.registeredAtUtc)} />
              <DetailField label="Application created" value={formatDateTime(detail.application.createdAtUtc)} />
              <DetailField label="Application updated" value={formatDateTime(detail.application.updatedAtUtc)} />
            </dl>
          </section>

          <section aria-labelledby="registration-profile-heading" className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
            <div>
              <h2 id="registration-profile-heading" className="text-base font-bold">Profile</h2>
            </div>
            <dl className="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
              <DetailField label="Completion status" value={detail.profile.completionStatus ?? "Not provided"} />
              {detail.profile.personal && (
                <>
                  <DetailField label="Phone number" value={detail.profile.personal.phoneNumber} />
                  <DetailField label="Country code" value={detail.profile.personal.countryCode} />
                  <DetailField label="Region" value={detail.profile.personal.region} />
                  <DetailField label="City" value={detail.profile.personal.city} />
                  <DetailField label="Postal code" value={detail.profile.personal.postalCode} />
                  <DetailField label="Address" value={detail.profile.personal.addressLine} />
                </>
              )}
              {detail.profile.organization && (
                <>
                  <DetailField label="Organization type" value={detail.profile.organization.organizationType} />
                  <DetailField label="Registered name" value={detail.profile.organization.registeredName} />
                  <DetailField label="Contact email" value={detail.profile.organization.contactEmail} />
                  <DetailField label="Contact phone" value={detail.profile.organization.contactPhone} />
                  <DetailField label="Country code" value={detail.profile.organization.countryCode} />
                  <DetailField label="Region" value={detail.profile.organization.region} />
                  <DetailField label="City" value={detail.profile.organization.city} />
                  <DetailField label="Postal code" value={detail.profile.organization.postalCode} />
                  <DetailField label="Address" value={detail.profile.organization.addressLine} />
                </>
              )}
            </dl>
          </section>

          <section aria-labelledby="registration-tenant-heading" className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
            <h2 id="registration-tenant-heading" className="text-base font-bold">Linked tenant</h2>
            {detail.tenant ? (
              <dl className="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                <DetailField label="Tenant name" value={detail.tenant.displayName} />
                <DetailField label="Tenant code" value={detail.tenant.tenantCode} />
                <DetailField label="Tenant type" value={detail.tenant.tenantType} />
                <DetailField label="Tenant status" value={detail.tenant.status} />
                <DetailField label="Tenant ID" value={String(detail.tenant.tenantId)} />
              </dl>
            ) : (
              <p className="mt-3 text-sm text-slate-500">No linked tenant was returned for this registration.</p>
            )}
          </section>

          {detail.latestVerificationChallenge && (
            <section aria-labelledby="verification-challenge-heading" className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
              <h2 id="verification-challenge-heading" className="text-base font-bold">Latest verification challenge</h2>
              <dl className="mt-5 grid gap-4 sm:grid-cols-2">
                <DetailField label="Issued" value={formatDateTime(detail.latestVerificationChallenge.issuedAtUtc)} />
                <DetailField label="Expires" value={formatDateTime(detail.latestVerificationChallenge.expiresAtUtc)} />
              </dl>
            </section>
          )}

          <section aria-labelledby="registration-timeline-heading" className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
            <h2 id="registration-timeline-heading" className="text-base font-bold">Registration timeline</h2>
            {timelineQuery.isPending ? (
              <div className="mt-5 space-y-3" role="status" aria-label="Loading registration timeline">
                <Skeleton className="h-12" /><Skeleton className="h-12" />
              </div>
            ) : timelineQuery.isError ? (
              <div className="mt-5">
                <Notice>{toApiRequestError(timelineQuery.error).message}</Notice>
                <Button className="mt-3" size="sm" variant="secondary" onClick={() => void timelineQuery.refetch()}>Retry timeline</Button>
              </div>
            ) : timelineQuery.data?.length ? (
              <ol className="mt-5 space-y-0">
                {timelineQuery.data.map((event, index) => (
                  <li key={`${event.occurredAtUtc}-${event.eventCode}-${index}`} className="relative flex gap-4 pb-6 last:pb-0">
                    <span aria-hidden="true" className="relative mt-1 flex size-3 shrink-0 items-center justify-center rounded-full bg-brand-600 after:absolute after:top-3 after:h-[calc(100%+1.5rem)] after:w-px after:bg-slate-200 last:after:hidden dark:after:bg-slate-700" />
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-start justify-between gap-2">
                        <div>
                          <p className="text-sm font-semibold">{event.eventCode}</p>
                          <p className="mt-1 text-xs text-slate-500">
                            {event.fromStatus ?? "—"} <span aria-hidden="true">→</span> {event.toStatus ?? "—"}
                          </p>
                        </div>
                        <time className="text-xs text-slate-500" dateTime={event.occurredAtUtc}>{formatDateTime(event.occurredAtUtc)}</time>
                      </div>
                      <p className="mt-1 text-xs text-slate-500">Actor: {event.actorDisplayName ?? "Not available"}</p>
                    </div>
                  </li>
                ))}
              </ol>
            ) : (
              <p className="mt-3 text-sm text-slate-500">No timeline events were returned.</p>
            )}
          </section>
        </div>
      ) : null}
    </>
  );
}

function DetailField({ label, value }: { label: string; value: string | null | undefined }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs text-slate-500">{label}</dt>
      <dd className="mt-1 break-words text-sm font-medium">{value || "Not provided"}</dd>
    </div>
  );
}

function formatDateTime(value: string | null | undefined): string {
  if (!value) return "Not available";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "Not available" : new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date);
}
