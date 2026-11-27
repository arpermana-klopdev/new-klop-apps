import {
  ChevronDown,
  CircleHelp,
  Menu,
  Moon,
  Sun,
  X,
} from "lucide-react";
import { useEffect, useState } from "react";
import { Link, NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../app/AuthContext";
import { brand } from "../app/brand";
import { moduleForRoute, moduleRegistry } from "../app/modules";
import {
  PLATFORM_REGISTRATIONS_READ,
  usePlatformRegistrationPermissions,
} from "../app/platformRegistrationPermissions";
import { useTheme } from "../app/ThemeContext";
import { AppLogo } from "./AppLogo";
import { Button, Notice } from "./ui";

const pageNames: Record<string, string> = {
  "/": "Overview",
  "/registrations": "Registrations",
  "/registrations/personal": "PERSONAL Registrations",
  "/registrations/organization": "ORGANIZATION Registrations",
  "/platform-setup": "Platform Setup",
  "/platform-setup/registration": "Registration Setup",
  "/platform-setup/legal-documents": "Legal Documents",
  "/platform-setup/master-data": "Master Data",
  "/platform-setup/system-configuration": "System Configuration",
  "/platform-setup/notifications": "Notifications",
  "/platform-setup/access-approval": "Role & Permission Matrix",
  "/tenants": "Tenants",
  "/members": "Members & roles",
  "/settings": "Profile & settings",
  "/users": "User directory",
  "/audit-logs": "Audit logs",
  "/security-logs": "Security logs",
};

const navigationModules = moduleRegistry
  .filter((module) => module.group === "Platform" && module.route !== null && module.sidebar !== false)
  .sort((left, right) => left.order - right.order);

function Sidebar({
  close,
  canReadRegistrations,
  registrationPermissionError,
}: {
  close?: () => void;
  canReadRegistrations: boolean;
  registrationPermissionError: boolean;
}) {
  const visibleNavigationModules = navigationModules.filter((module) =>
    !module.requiredCapability ||
    (module.requiredCapability === PLATFORM_REGISTRATIONS_READ && canReadRegistrations),
  );
  const navClass = ({ isActive }: { isActive: boolean }) =>
    `group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition ${
      isActive
        ? "bg-brand-50 text-brand-700 dark:bg-brand-950/60 dark:text-blue-300"
        : "text-slate-600 hover:bg-slate-100 hover:text-slate-950 dark:text-slate-300 dark:hover:bg-slate-800 dark:hover:text-white"
    }`;

  return (
    <div className="flex h-full flex-col">
      <Link
        to="/"
        className="flex h-[76px] items-center px-5"
        aria-label={`${brand.displayName} home`}
        onClick={close}
      >
        <AppLogo size="compact" className="!w-[148px]" />
      </Link>
      <div className="mx-4 border-t border-slate-100 dark:border-slate-800" />
      <nav aria-label="Platform administration" className="flex-1 overflow-y-auto px-3 py-6">
        <p className="mb-2 px-3 text-[10px] font-bold uppercase tracking-[0.15em] text-slate-400">
          Platform administration
        </p>
        <div className="space-y-1">
          {visibleNavigationModules.map(({ id, label, route, icon: Icon, availability }) => (
            <NavLink
              key={id}
              to={route!}
              end={route === "/"}
              className={navClass}
              onClick={close}
            >
              <Icon aria-hidden="true" className="size-[18px] shrink-0" />
              <span className="min-w-0 flex-1 truncate">{label}</span>
              {availability === "coming-soon" && (
                <span className="shrink-0 rounded-full bg-slate-100 px-1.5 py-0.5 text-[9px] font-semibold text-slate-500 dark:bg-slate-800 dark:text-slate-400">
                  Soon
                </span>
              )}
            </NavLink>
          ))}
          {registrationPermissionError && (
            <p role="alert" className="px-3 py-2 text-xs text-rose-700 dark:text-rose-300">
              Registration access could not be verified. Reload the page to retry.
            </p>
          )}
        </div>
      </nav>
    </div>
  );
}

export function AppShell() {
  const { profile, signOut } = useAuth();
  const registrationPermissionsQuery = usePlatformRegistrationPermissions(profile?.userId);
  const canReadRegistrations =
    !registrationPermissionsQuery.isFetching &&
    registrationPermissionsQuery.data?.permissions.includes(PLATFORM_REGISTRATIONS_READ) === true;
  const { theme, setTheme } = useTheme();
  const [menuOpen, setMenuOpen] = useState(false);
  const [mobileSidebar, setMobileSidebar] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const location = useLocation();
  const navigate = useNavigate();
  const pageName = location.pathname.startsWith("/registrations/personal/") ||
    location.pathname.startsWith("/registrations/organization/")
    ? "Registration detail"
    : location.pathname.endsWith("/members")
    ? "Members & roles"
    : pageNames[location.pathname] ?? moduleForRoute(location.pathname)?.label ?? "Portal";
  const profileName = profile?.displayName || profile?.email || "KLOP user";
  const profileEmail = profile?.email ?? "Email unavailable";
  const emailVerified = Boolean(profile?.emailVerifiedAtUtc);

  useEffect(() => {
    setMenuOpen(false);
    setMobileSidebar(false);
  }, [location.pathname]);

  useEffect(() => {
    if (!menuOpen && !mobileSidebar) return;
    function closeTransientNavigation(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setMenuOpen(false);
        setMobileSidebar(false);
      }
    }
    window.addEventListener("keydown", closeTransientNavigation);
    return () => window.removeEventListener("keydown", closeTransientNavigation);
  }, [menuOpen, mobileSidebar]);

  async function handleSignOut() {
    setActionError(null);
    try {
      await signOut();
      navigate("/login");
    } catch (error: unknown) {
      setActionError(error instanceof Error ? error.message : "Unable to sign out.");
    }
  }

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900 dark:bg-slate-950 dark:text-slate-100">
      <aside className="fixed inset-y-0 left-0 z-20 hidden w-[252px] border-r border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-950 lg:block">
        <Sidebar
          canReadRegistrations={canReadRegistrations}
          registrationPermissionError={registrationPermissionsQuery.isError}
        />
      </aside>
      {mobileSidebar && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <button
            type="button"
            className="absolute inset-0 bg-slate-950/45"
            aria-label="Close navigation"
            onClick={() => setMobileSidebar(false)}
          />
          <aside
            role="dialog"
            aria-modal="true"
            aria-label="Main navigation"
            className="relative h-full w-[min(84vw,300px)] bg-white shadow-xl dark:bg-slate-950"
          >
            <button
              type="button"
              className="absolute right-3 top-5 z-10 rounded-lg p-2 text-slate-500 hover:bg-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:hover:bg-slate-800"
              aria-label="Close navigation"
              onClick={() => setMobileSidebar(false)}
            >
              <X aria-hidden="true" className="size-5" />
            </button>
            <Sidebar
              close={() => setMobileSidebar(false)}
              canReadRegistrations={canReadRegistrations}
              registrationPermissionError={registrationPermissionsQuery.isError}
            />
          </aside>
        </div>
      )}
      <div className="lg:pl-[252px]">
        <header className="sticky top-0 z-10 flex min-h-[72px] items-center justify-between gap-3 border-b border-slate-200 bg-white/95 px-3 backdrop-blur-md dark:border-slate-800 dark:bg-slate-950/95 sm:px-7">
          <div className="flex min-w-0 items-center gap-3">
            <button
              type="button"
              className="rounded-lg p-2 text-slate-500 hover:bg-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:hover:bg-slate-800 lg:hidden"
              aria-label="Open navigation"
              aria-expanded={mobileSidebar}
              onClick={() => setMobileSidebar(true)}
            >
              <Menu aria-hidden="true" className="size-5" />
            </button>
            <div className="hidden min-w-0 items-center gap-2 text-sm sm:flex">
              <span className="shrink-0 rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-semibold text-slate-600 dark:bg-slate-800 dark:text-slate-300">
                Platform
              </span>
              <span aria-hidden="true" className="text-slate-300">/</span>
              <span className="truncate font-semibold text-slate-800 dark:text-slate-200">
                {pageName}
              </span>
            </div>
            <span className="truncate text-sm font-semibold text-slate-800 dark:text-slate-200 sm:hidden">
              {pageName}
            </span>
          </div>
          <div className="flex shrink-0 items-center gap-1 sm:gap-2">
            <Button
              variant="ghost"
              size="sm"
              aria-label={`Switch to ${theme === "light" ? "dark" : "light"} theme`}
              onClick={() => setTheme(theme === "light" ? "dark" : "light")}
              className="size-9 min-h-9 px-0"
            >
              {theme === "light" ? <Moon aria-hidden="true" className="size-4" /> : <Sun aria-hidden="true" className="size-4" />}
            </Button>
            <div className="relative">
              <button
                type="button"
                className="flex max-w-[min(48vw,240px)] items-center gap-2 rounded-xl p-1.5 hover:bg-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:hover:bg-slate-800"
                aria-expanded={menuOpen}
                aria-haspopup="true"
                aria-controls="profile-actions"
                onClick={() => setMenuOpen((open) => !open)}
              >
                <span
                  aria-hidden="true"
                  className="grid size-8 shrink-0 place-items-center rounded-full bg-brand-100 text-xs font-bold text-brand-700 dark:bg-brand-950 dark:text-blue-300"
                >
                  {profileName.slice(0, 1).toUpperCase()}
                </span>
                <span className="hidden truncate text-sm font-semibold sm:block">{profileName}</span>
                <ChevronDown aria-hidden="true" className="hidden size-4 shrink-0 text-slate-400 sm:block" />
              </button>
              {menuOpen && (
                <div
                  id="profile-actions"
                  className="absolute right-0 mt-2 w-[min(19rem,calc(100vw-1.5rem))] rounded-2xl border border-slate-200 bg-white p-2 shadow-xl dark:border-slate-800 dark:bg-slate-900"
                >
                  <div className="border-b border-slate-100 px-3 py-2.5 dark:border-slate-800">
                    <p className="truncate text-sm font-semibold">{profileName}</p>
                    <p className="mt-0.5 truncate text-xs text-slate-500">{profileEmail}</p>
                    <p className={`mt-2 text-[11px] font-medium ${emailVerified ? "text-emerald-700 dark:text-emerald-300" : "text-amber-700 dark:text-amber-300"}`}>
                      {emailVerified ? "Email verified" : "Email not verified"}
                    </p>
                  </div>
                  <Link
                    to="/settings"
                    className="mt-1 block rounded-lg px-3 py-2.5 text-sm font-medium hover:bg-slate-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:hover:bg-slate-800"
                    onClick={() => setMenuOpen(false)}
                  >
                    My Profile
                  </Link>
                  <Link
                    to="/settings#appearance"
                    className="block rounded-lg px-3 py-2.5 text-sm font-medium hover:bg-slate-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600 dark:hover:bg-slate-800"
                    onClick={() => setMenuOpen(false)}
                  >
                    Account Settings
                  </Link>
                  <button
                    type="button"
                    className="w-full rounded-lg px-3 py-2.5 text-left text-sm font-medium text-rose-700 hover:bg-rose-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-rose-500 dark:text-rose-300 dark:hover:bg-rose-950/30"
                    onClick={() => {
                      setMenuOpen(false);
                      void handleSignOut();
                    }}
                  >
                    Sign out
                  </button>
                </div>
              )}
            </div>
          </div>
        </header>
        <main className="mx-auto min-h-[calc(100vh-72px)] max-w-[1440px] px-4 py-6 sm:px-7 sm:py-8 lg:px-9 lg:py-9">
          {actionError && (
            <div className="mb-5">
              <Notice>{actionError}</Notice>
            </div>
          )}
          <Outlet />
          <footer className="mt-14 border-t border-slate-200 py-5 text-xs text-slate-500 dark:border-slate-800 dark:text-slate-400">
            <span>{brand.displayName}</span>
            <span aria-hidden="true"> · </span>
            <span>Data and authorization provided by {brand.backendName} API</span>
          </footer>
        </main>
      </div>
    </div>
  );
}

export function MissingRoute() {
  return (
    <div className="mx-auto max-w-lg py-16 text-center">
      <div className="mx-auto mb-4 grid size-12 place-items-center rounded-full bg-slate-100 text-slate-500 dark:bg-slate-900">
        <CircleHelp aria-hidden="true" className="size-6" />
      </div>
      <h1 className="text-xl font-bold">Page not found</h1>
      <p className="mt-2 text-sm text-slate-500">The requested portal page does not exist.</p>
      <Link to="/" className="mt-5 inline-block text-sm font-semibold text-brand-600">
        Return to overview
      </Link>
    </div>
  );
}
