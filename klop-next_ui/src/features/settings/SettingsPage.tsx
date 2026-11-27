import { Check, LogOut, Moon, Sun, UserRound } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../../app/AuthContext";
import { useTheme } from "../../app/ThemeContext";
import { Button, Notice, PageHeading, StatusBadge } from "../../components/ui";

export function SettingsPage() {
  const { profile, signOut } = useAuth();
  const { theme, setTheme } = useTheme();
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  async function exitSession() {
    setError(null);
    try {
      await signOut();
      navigate("/login");
    } catch (requestError: unknown) {
      setError(requestError instanceof Error ? requestError.message : "Unable to sign out.");
    }
  }

  return (
    <>
      <PageHeading
        eyebrow="Preferences"
        title="Profile & settings"
        description="Your profile is read-only in the current API. Theme preferences are stored locally on this device."
      />
      {error && <div className="mb-5"><Notice>{error}</Notice></div>}
      <div className="grid gap-5 lg:grid-cols-2">
        <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-soft dark:border-slate-800 dark:bg-slate-900">
          <div className="mb-5 flex items-center gap-3">
            <div className="grid size-10 place-items-center rounded-xl bg-blue-50 text-blue-600 dark:bg-blue-950/50 dark:text-blue-300">
              <UserRound className="size-5" />
            </div>
            <div>
              <h2 className="text-sm font-bold">Profile</h2>
              <p className="mt-1 text-xs text-slate-500">Details returned by your authenticated API session.</p>
            </div>
          </div>
          <dl className="divide-y divide-slate-100 dark:divide-slate-800">
            <ProfileRow label="Display name" value={profile?.displayName ?? "Unavailable"} />
            <ProfileRow label="Email" value={profile?.email ?? "Unavailable"} />
            <div className="flex items-center justify-between gap-4 py-3">
              <dt className="text-xs text-slate-500">Email status</dt>
              <dd><StatusBadge value={profile?.emailVerifiedAtUtc ? "Verified" : "Not verified"} /></dd>
            </div>
            <ProfileRow label="User ID" value={String(profile?.userId ?? "Unavailable")} />
          </dl>
          <p className="mt-4 text-xs text-slate-500">Profile editing and password reset are not available in the current backend contract.</p>
        </section>
        <section id="appearance" className="rounded-2xl border border-slate-200 bg-white p-6 shadow-soft dark:border-slate-800 dark:bg-slate-900">
          <div className="mb-5">
            <h2 className="text-sm font-bold">Appearance</h2>
            <p className="mt-1 text-xs text-slate-500">Choose a display theme for this browser.</p>
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            {(["light", "dark"] as const).map((option) => (
              <button
                key={option}
                aria-pressed={theme === option}
                onClick={() => setTheme(option)}
                className={`flex items-center justify-between rounded-xl border p-4 text-left transition ${
                  theme === option
                    ? "border-brand-500 bg-brand-50/70 ring-1 ring-brand-500 dark:bg-brand-950/30"
                    : "border-slate-200 hover:border-slate-300 dark:border-slate-700 dark:hover:border-slate-600"
                }`}
              >
                <span className="flex items-center gap-3">
                  {option === "light" ? <Sun className="size-4" /> : <Moon className="size-4" />}
                  <span className="text-sm font-semibold capitalize">{option}</span>
                </span>
                {theme === option && <Check className="size-4 text-brand-600" />}
              </button>
            ))}
          </div>
          <div className="mt-8 border-t border-slate-100 pt-5 dark:border-slate-800">
            <h2 className="text-sm font-bold">Session</h2>
            <p className="mt-1 text-xs text-slate-500">Refresh credentials are held only in an HttpOnly backend cookie.</p>
            <Button className="mt-4" variant="secondary" onClick={() => void exitSession()}>
              <LogOut className="size-4" /> Sign out
            </Button>
          </div>
        </section>
      </div>
    </>
  );
}

function ProfileRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-4 py-3">
      <dt className="text-xs text-slate-500">{label}</dt>
      <dd className="max-w-[65%] truncate text-right text-sm font-medium">{value}</dd>
    </div>
  );
}
