import { Link } from "react-router-dom";
import { brand } from "../../app/brand";
import { moduleRegistry } from "../../app/modules";
import { Button, PageHeading } from "../../components/ui";

const missingDependencies: Record<string, string> = {
  "User directory": "User search, listing, and administration are not provided by the current API.",
  "Master data": "Only organization types are exposed; generic master-data discovery is not available.",
  Configuration: "Configuration listing and editing are not provided by the current API.",
  "Audit logs": "Audit event search is not provided by the current API.",
  "Security logs": "Security event history is not provided by the current API.",
  Notifications: "Notification delivery and history are not provided by the current API.",
};

export function UnavailablePage({ module }: { module: string }) {
  const descriptor = moduleRegistry.find((entry) => entry.label === module);
  const Icon = descriptor?.icon;

  return (
    <>
      <PageHeading
        eyebrow={`${brand.displayName} · ${descriptor?.group ?? "Portal"}`}
        title={module}
      />
      <section className="mx-auto max-w-2xl rounded-2xl border border-slate-200 bg-white px-7 py-12 text-center shadow-soft dark:border-slate-800 dark:bg-slate-900">
        <div className="mx-auto grid size-12 place-items-center rounded-2xl bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300">
          {Icon && <Icon aria-hidden="true" className="size-5" />}
        </div>
        <span className="mt-5 inline-flex rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-700 dark:bg-slate-800 dark:text-slate-200">
          Coming soon
        </span>
        <h2 className="mt-3 text-lg font-bold">This module is not available yet</h2>
        <p className="mx-auto mt-2 max-w-lg text-sm leading-6 text-slate-500 dark:text-slate-400">
          {missingDependencies[module] ?? descriptor?.description ?? "This module needs a supporting API contract before it can be implemented."}
        </p>
        <p className="mx-auto mt-4 max-w-lg text-xs leading-5 text-slate-400">
          This status describes feature availability, not your permissions. Access decisions remain with the backend.
        </p>
        <Link to="/" className="mt-6 inline-block">
          <Button variant="secondary">Return to overview</Button>
        </Link>
      </section>
    </>
  );
}
