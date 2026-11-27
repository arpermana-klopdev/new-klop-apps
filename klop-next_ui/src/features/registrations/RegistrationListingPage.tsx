import { useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, RefreshCw, Search } from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useLocation, useSearchParams } from "react-router-dom";
import { toApiRequestError } from "../../api/client";
import { AppEmptyState, Button, Notice, PageHeading, Skeleton, StatusBadge, TextInput } from "../../components/ui";
import { getRegistrations, type RegistrationType } from "./api";

const pageSize = 20;

export function RegistrationListingPage({ type }: { type: RegistrationType }) {
  const location = useLocation();
  const [searchParams, setSearchParams] = useSearchParams();
  const [search, setSearch] = useState(searchParams.get("search") ?? "");
  const [submittedSearch, setSubmittedSearch] = useState(searchParams.get("search") ?? "");
  const [emailVerificationStatus, setEmailVerificationStatus] = useState(searchParams.get("emailVerificationStatus") ?? "");
  const [applicationStatus, setApplicationStatus] = useState(searchParams.get("applicationStatus") ?? "");
  const initialPage = Number(searchParams.get("pageNumber"));
  const [pageNumber, setPageNumber] = useState(Number.isSafeInteger(initialPage) && initialPage > 0 ? initialPage : 1);

  function updateUrl(updates: Record<string, string | undefined>) {
    setSearchParams((current) => {
      const next = new URLSearchParams(current);
      for (const [key, value] of Object.entries(updates)) {
        if (value) next.set(key, value);
        else next.delete(key);
      }
      return next;
    }, { replace: true });
  }

  useEffect(() => {
    const timer = window.setTimeout(() => {
      setSubmittedSearch(search.trim());
      updateUrl({ search: search.trim() || undefined });
    }, 300);
    return () => window.clearTimeout(timer);
  }, [search]);

  const registrationsQuery = useQuery({
    queryKey: ["registrations", "list", type, submittedSearch, emailVerificationStatus, applicationStatus, pageNumber],
    queryFn: () => getRegistrations({
      registrationType: type,
      search: submittedSearch || undefined,
      emailVerificationStatus: emailVerificationStatus || undefined,
      applicationStatus: applicationStatus || undefined,
      pageNumber,
      pageSize,
    }),
  });
  const result = registrationsQuery.data;
  const applicationStatuses = result?.applicationStatuses ?? [];
  const title = `${type} Registrations`;
  const hasFilters = Boolean(search || emailVerificationStatus || applicationStatus);

  function resetPage(setter: () => void) {
    setter();
    setPageNumber(1);
  }

  return (
    <>
      <PageHeading
        eyebrow="Platform administration / registrations"
        title={title}
        description="Search and review registration applications. All filters and pagination are applied by the registration service."
        action={
          <Button
            variant="secondary"
            disabled={registrationsQuery.isFetching}
            onClick={() => void registrationsQuery.refetch()}
          >
            <RefreshCw aria-hidden="true" className={`size-4 ${registrationsQuery.isFetching ? "animate-spin" : ""}`} />
            Refresh
          </Button>
        }
      />
      <section aria-label={`${type} registration listing`} className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-soft dark:border-slate-800 dark:bg-slate-900">
        <div className="flex flex-wrap items-end justify-between gap-4 border-b border-slate-100 px-5 py-4 dark:border-slate-800 sm:px-6">
          <div>
            <h2 className="text-sm font-bold">Registration applications</h2>
          </div>
          <div className="grid w-full gap-2 sm:w-auto sm:grid-cols-[minmax(13rem,1fr)_10rem_12rem]">
            <label className="relative">
              <Search aria-hidden="true" className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-slate-400" />
              <TextInput
                aria-label={`Search ${type.toLowerCase()} registrations`}
                className="pl-9"
                placeholder="Search name or email"
                value={search}
                onChange={(event) => {
                  setSearch(event.target.value);
                  setPageNumber(1);
                  updateUrl({ search: event.target.value.trim() || undefined, pageNumber: undefined });
                }}
              />
            </label>
            <select
              aria-label="Filter by email verification"
              className="field-control"
              value={emailVerificationStatus}
              onChange={(event) => {
                resetPage(() => setEmailVerificationStatus(event.target.value));
                updateUrl({ emailVerificationStatus: event.target.value || undefined, pageNumber: undefined });
              }}
            >
              <option value="">All verification</option>
              <option value="PENDING">Pending verification</option>
              <option value="VERIFIED">Verified</option>
            </select>
            <select
              aria-label="Filter by application status"
              className="field-control"
              value={applicationStatus}
              onChange={(event) => {
                resetPage(() => setApplicationStatus(event.target.value));
                updateUrl({ applicationStatus: event.target.value || undefined, pageNumber: undefined });
              }}
            >
              <option value="">All application statuses</option>
              {applicationStatuses.map((status) => <option key={status} value={status}>{status}</option>)}
            </select>
          </div>
        </div>

        {registrationsQuery.isPending ? (
          <div className="space-y-3 p-5" role="status" aria-label="Loading registrations">
            <Skeleton className="h-12" /><Skeleton className="h-12" /><Skeleton className="h-12" />
          </div>
        ) : registrationsQuery.isError ? (
          <div className="p-5">
            <Notice>{toApiRequestError(registrationsQuery.error).message}</Notice>
            <Button className="mt-4" size="sm" variant="secondary" onClick={() => void registrationsQuery.refetch()}>
              Retry
            </Button>
          </div>
        ) : !result?.items.length ? (
          <div className="px-5 py-12">
            <AppEmptyState
              title={hasFilters ? "No registrations match these filters" : "No registrations found"}
              description={hasFilters ? "Try changing the search term or filters." : "The registration service returned no records."}
            />
          </div>
        ) : (
          <>
            <div className="hidden overflow-x-auto sm:block">
              <table className="w-full min-w-[820px] text-left text-sm">
                <thead className="bg-slate-50 text-[11px] uppercase tracking-wide text-slate-500 dark:bg-slate-950/60">
                  <tr>
                    <th scope="col" className="px-5 py-3 font-semibold">Registration ID</th>
                    <th scope="col" className="px-5 py-3 font-semibold">Full Name</th>
                    <th scope="col" className="px-5 py-3 font-semibold">Email Address</th>
                    <th scope="col" className="px-5 py-3 font-semibold">Email Verification</th>
                    <th scope="col" className="px-5 py-3 font-semibold">Application Status</th>
                    <th scope="col" className="px-5 py-3 font-semibold">Registered At</th>
                    <th scope="col" className="px-5 py-3 font-semibold">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                  {result.items.map((item) => (
                    <tr key={item.registrationApplicationId} className="hover:bg-slate-50/80 dark:hover:bg-slate-800/30">
                      <td className="px-5 py-4 font-mono text-xs">{item.registrationApplicationId}</td>
                      <td className="px-5 py-4 font-semibold">{item.displayName}</td>
                      <td className="px-5 py-4 text-slate-600 dark:text-slate-300">{item.email}</td>
                      <td className="px-5 py-4">
                        <StatusBadge value={item.emailVerifiedAtUtc ? "Verified" : "Pending"} />
                      </td>
                      <td className="px-5 py-4"><StatusBadge value={item.applicationStatus} /></td>
                      <td className="px-5 py-4 text-xs text-slate-500">{formatDate(item.registeredAtUtc)}</td>
                      <td className="px-5 py-4 text-right">
                        <Link className="text-xs font-semibold text-brand-700 hover:underline dark:text-blue-300" to={`/registrations/${type.toLowerCase()}/${item.registrationApplicationId}`} state={{ returnTo: `${location.pathname}${location.search}` }}>
                          View details
                        </Link>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="space-y-3 p-4 sm:hidden">
              {result.items.map((item) => (
                <article key={item.registrationApplicationId} className="rounded-xl border border-slate-200 p-4 dark:border-slate-800">
                <p className="font-mono text-xs text-slate-500">Registration ID: {item.registrationApplicationId}</p>
                  <h3 className="text-sm font-semibold">Full Name: {item.displayName}</h3>
                  <p className="mt-1 break-all text-xs text-slate-500">{item.email}</p>
                  <div className="mt-3 flex flex-wrap gap-2">
                    <StatusBadge value={item.emailVerifiedAtUtc ? "Verified" : "Pending"} />
                    <StatusBadge value={item.applicationStatus} />
                  </div>
                  <div className="mt-3 flex items-center justify-between gap-2">
                    <span className="text-xs text-slate-500">{formatDate(item.registeredAtUtc)}</span>
                    <Link className="text-xs font-semibold text-brand-700 dark:text-blue-300" to={`/registrations/${type.toLowerCase()}/${item.registrationApplicationId}`} state={{ returnTo: `${location.pathname}${location.search}` }}>
                      View details
                    </Link>
                  </div>
                </article>
              ))}
            </div>
            <div className="flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 px-5 py-3 dark:border-slate-800">
              <p className="text-xs text-slate-500">
                Showing {(result.pageNumber - 1) * result.pageSize + 1}–{Math.min(result.pageNumber * result.pageSize, result.totalCount)} of {result.totalCount}
              </p>
              <div className="flex items-center gap-2">
                <Button size="sm" variant="secondary" disabled={result.pageNumber <= 1 || registrationsQuery.isFetching} onClick={() => {
                  const nextPage = Math.max(1, result.pageNumber - 1);
                  setPageNumber(nextPage);
                  updateUrl({ pageNumber: nextPage > 1 ? String(nextPage) : undefined });
                }}>
                  <ChevronLeft aria-hidden="true" className="size-4" /> Previous
                </Button>
                <span className="min-w-20 text-center text-xs text-slate-500">Page {result.pageNumber} of {Math.max(result.totalPages, 1)}</span>
                <Button size="sm" variant="secondary" disabled={result.pageNumber >= result.totalPages || registrationsQuery.isFetching} onClick={() => {
                  const nextPage = result.pageNumber + 1;
                  setPageNumber(nextPage);
                  updateUrl({ pageNumber: String(nextPage) });
                }}>
                  Next <ChevronRight aria-hidden="true" className="size-4" />
                </Button>
              </div>
            </div>
          </>
        )}
      </section>
    </>
  );
}

function formatDate(value: string | null | undefined): string {
  if (!value) return "Date unavailable";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "Date unavailable" : new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(date);
}
