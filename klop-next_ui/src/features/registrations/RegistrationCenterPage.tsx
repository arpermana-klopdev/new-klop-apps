import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Building2, RefreshCw, UserRound } from "lucide-react";
import { Link } from "react-router-dom";
import { toApiRequestError } from "../../api/client";
import { Button, Notice, PageHeading, Skeleton } from "../../components/ui";
import { getRegistrationSummary, type RegistrationType } from "./api";

const registrationTypes: Array<{
  type: RegistrationType;
  title: string;
  route: string;
  icon: typeof UserRound;
}> = [
  { type: "PERSONAL", title: "PERSONAL Registration", route: "/registrations/personal", icon: UserRound },
  { type: "ORGANIZATION", title: "ORGANIZATION Registration", route: "/registrations/organization", icon: Building2 },
];

export function RegistrationCenterPage() {
  const personalSummary = useQuery({
    queryKey: ["registrations", "summary", "PERSONAL"],
    queryFn: () => getRegistrationSummary("PERSONAL"),
  });
  const organizationSummary = useQuery({
    queryKey: ["registrations", "summary", "ORGANIZATION"],
    queryFn: () => getRegistrationSummary("ORGANIZATION"),
  });
  const summaryQueries = [personalSummary, organizationSummary];

  return (
    <>
      <PageHeading
        eyebrow="Platform administration"
        title="Registration Center"
        description="Monitor and manage personal and organization account registrations."
        action={
          <Button
            variant="secondary"
            disabled={summaryQueries.some((query) => query.isFetching)}
            onClick={() => summaryQueries.forEach((query) => void query.refetch())}
          >
            <RefreshCw aria-hidden="true" className={`size-4 ${summaryQueries.some((query) => query.isFetching) ? "animate-spin" : ""}`} />
            Refresh
          </Button>
        }
      />
      {summaryQueries.some((query) => query.isError) && (
        <div className="mb-5">
          <Notice>{toApiRequestError(summaryQueries.find((query) => query.isError)?.error).message}</Notice>
          <Button
            className="mt-3"
            size="sm"
            variant="secondary"
            onClick={() => summaryQueries.filter((query) => query.isError).forEach((query) => void query.refetch())}
          >
            Retry failed summaries
          </Button>
        </div>
      )}
      <section aria-label="Registration summary" className="grid gap-4 xl:grid-cols-2">
        {registrationTypes.map(({ type, title, route, icon: Icon }) => {
          const query = type === "PERSONAL" ? personalSummary : organizationSummary;
          const summary = query.data;
          return (
            <Link
              key={type}
              to={route}
              aria-label={title}
              className="group flex min-h-52 flex-col rounded-2xl border border-slate-200 bg-white p-6 shadow-soft transition hover:border-brand-200 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:border-slate-800 dark:bg-slate-900 dark:hover:border-brand-700"
            >
              <div className="flex items-start justify-between gap-4">
                <div className="flex items-center gap-3">
                  <span className="grid size-11 place-items-center rounded-xl bg-blue-50 text-brand-600 dark:bg-blue-950/50 dark:text-blue-300">
                    <Icon aria-hidden="true" className="size-5" />
                  </span>
                  <div>
                    <h2 className="text-base font-bold">{title}</h2>
                    <p className="mt-1 text-xs text-slate-500">Registration activity summary</p>
                  </div>
                </div>
                <ArrowRight aria-hidden="true" className="size-5 shrink-0 text-brand-600 transition group-hover:translate-x-1" />
              </div>
              {query.isPending ? (
                <div className="mt-6 grid grid-cols-2 gap-3" role="status" aria-label={`Loading ${type} summary`}>
                  <Skeleton className="h-20" /><Skeleton className="h-20" />
                  <Skeleton className="h-20" /><Skeleton className="h-20" />
                </div>
              ) : summary ? (
                <dl className="mt-6 grid grid-cols-2 gap-3">
                  <SummaryMetric label="Total registrations" value={summary.totalRegistrations} />
                  <SummaryMetric label="Pending email verification" value={summary.pendingEmailVerification} />
                  <SummaryMetric label="Email verified" value={summary.emailVerified} />
                  <SummaryMetric label="Pending review" value={summary.pendingReview} />
                </dl>
              ) : (
                <p className="mt-6 rounded-xl border border-dashed border-slate-300 px-4 py-6 text-center text-sm text-slate-500 dark:border-slate-700">
                  Summary unavailable. Retry to load current totals.
                </p>
              )}
            </Link>
          );
        })}
      </section>
    </>
  );
}

function SummaryMetric({ label, value }: { label: string; value: number | null }) {
  return (
    <div className="rounded-xl bg-slate-50 p-4 dark:bg-slate-950/60">
      <dt className="text-xs text-slate-500">{label}</dt>
      <dd className="mt-2 text-2xl font-bold tracking-tight text-slate-950 dark:text-white">
        {value === null ? "—" : value.toLocaleString()}
      </dd>
    </div>
  );
}
