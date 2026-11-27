import { FileText } from "lucide-react";

export type DocumentRequirementItem = {
  id: string | number;
  name: string;
  description?: string | null;
  required?: boolean;
};

export function DocumentRequirements({
  requirements = [],
}: {
  requirements?: readonly DocumentRequirementItem[];
}) {
  return (
    <section aria-labelledby="document-requirements-heading" className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
      <div className="flex items-start gap-3">
        <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-blue-50 text-brand-600 dark:bg-blue-950/50 dark:text-blue-300">
          <FileText aria-hidden="true" className="size-5" />
        </span>
        <div>
          <h2 id="document-requirements-heading" className="text-base font-bold">Document requirements</h2>
          <p className="mt-1 text-xs text-slate-500">Requirements are displayed only when supplied by the registration flow.</p>
        </div>
      </div>
      {requirements.length === 0 ? (
        <p className="mt-5 rounded-xl border border-dashed border-slate-300 px-4 py-6 text-center text-sm text-slate-500 dark:border-slate-700">
          No document requirements have been provided.
        </p>
      ) : (
        <ul className="mt-5 divide-y divide-slate-100 dark:divide-slate-800">
          {requirements.map((requirement) => (
            <li key={requirement.id} className="py-4 first:pt-0 last:pb-0">
              <div className="flex flex-wrap items-center gap-2">
                <h3 className="text-sm font-semibold">{requirement.name}</h3>
                {requirement.required && (
                  <span className="rounded-full bg-amber-50 px-2 py-0.5 text-[10px] font-semibold text-amber-700 dark:bg-amber-950/40 dark:text-amber-300">
                    Required
                  </span>
                )}
              </div>
              {requirement.description && <p className="mt-1 text-xs leading-5 text-slate-500">{requirement.description}</p>}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
