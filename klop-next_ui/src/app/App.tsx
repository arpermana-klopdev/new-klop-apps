import { Suspense, lazy, useEffect } from "react";
import { Navigate, Outlet, Route, Routes, useLocation } from "react-router-dom";
import { useAuth } from "./AuthContext";
import { brand } from "./brand";
import { moduleForRoute } from "./modules";
import { RegistrationPermissionGuard } from "./RegistrationPermissionGuard";
import { AppShell, MissingRoute } from "../components/AppShell";
import { AppPageLoader, LoadingState, Notice, Button } from "../components/ui";
import { RegistrationFlowProvider } from "../features/auth/RegistrationFlowContext";

const LoginPage = lazy(() =>
  import("../features/auth/LoginPage").then((module) => ({ default: module.LoginPage })),
);
const DashboardPage = lazy(() =>
  import("../features/dashboard/DashboardPage").then((module) => ({ default: module.DashboardPage })),
);
const TenantsPage = lazy(() =>
  import("../features/tenants/TenantsPage").then((module) => ({ default: module.TenantsPage })),
);
const MembersPage = lazy(() =>
  import("../features/members/MembersPage").then((module) => ({ default: module.MembersPage })),
);
const SettingsPage = lazy(() =>
  import("../features/settings/SettingsPage").then((module) => ({ default: module.SettingsPage })),
);
const UnavailablePage = lazy(() =>
  import("../features/unavailable/UnavailablePage").then((module) => ({ default: module.UnavailablePage })),
);
const RegistrationCenterPage = lazy(() =>
  import("../features/registrations/RegistrationCenterPage").then((module) => ({ default: module.RegistrationCenterPage })),
);
const PersonalRegistrationsPage = lazy(() =>
  import("../features/registrations/PersonalRegistrationsPage").then((module) => ({ default: module.PersonalRegistrationsPage })),
);
const OrganizationRegistrationsPage = lazy(() =>
  import("../features/registrations/OrganizationRegistrationsPage").then((module) => ({ default: module.OrganizationRegistrationsPage })),
);
const RegistrationDetailPage = lazy(() =>
  import("../features/registrations/RegistrationDetailPage").then((module) => ({ default: module.RegistrationDetailPage })),
);
const PlatformSetupPage = lazy(() =>
  import("../features/setup/PlatformSetupPages").then((module) => ({ default: module.PlatformSetupPage })),
);
const RegistrationSetupPage = lazy(() =>
  import("../features/setup/PlatformSetupPages").then((module) => ({ default: module.RegistrationSetupPage })),
);
const LegalDocumentsPage = lazy(() =>
  import("../features/setup/LegalDocumentsPage").then((module) => ({ default: module.LegalDocumentsPage })),
);
const MasterDataSetupPage = lazy(() =>
  import("../features/setup/PlatformSetupPages").then((module) => ({ default: module.MasterDataSetupPage })),
);
const SystemConfigurationPage = lazy(() =>
  import("../features/setup/PlatformSetupPages").then((module) => ({ default: module.SystemConfigurationPage })),
);
const NotificationsSetupPage = lazy(() =>
  import("../features/setup/PlatformSetupPages").then((module) => ({ default: module.NotificationsSetupPage })),
);
const AccessApprovalPage = lazy(() =>
  import("../features/setup/PlatformSetupPages").then((module) => ({ default: module.AccessApprovalPage })),
);

function RequireAuthentication() {
  const { status, error, restoreSession } = useAuth();
  if (status === "loading") {
    return (
      <div className="grid min-h-screen place-items-center">
        <LoadingState label="Restoring secure session" />
      </div>
    );
  }
  if (status === "error") {
    return (
      <div className="mx-auto grid min-h-screen max-w-lg content-center gap-4 px-5">
        <Notice>{error ?? "The session could not be restored."}</Notice>
        <Button className="w-full" onClick={() => void restoreSession()}>
          Retry connection
        </Button>
      </div>
    );
  }
  return status === "signedIn" ? <Outlet /> : <Navigate to="/login" replace />;
}

function PublicAuthentication() {
  const { status } = useAuth();
  return status === "signedIn" ? <Navigate to="/" replace /> : <LoginPage />;
}

function PublicAuthenticationWithRegistrationFlow() {
  return (
    <RegistrationFlowProvider>
      <PublicAuthentication />
    </RegistrationFlowProvider>
  );
}

export function App() {
  const location = useLocation();

  useEffect(() => {
    const page = moduleForRoute(location.pathname);
    document.title = page
      ? `${page.label} | ${brand.displayName}`
      : brand.browserTitle;
  }, [location.pathname]);

  return (
    <Suspense fallback={<AppPageLoader />}>
      <Routes>
        <Route path="/login" element={<PublicAuthenticationWithRegistrationFlow />} />
        <Route path="/verify-email" element={<PublicAuthenticationWithRegistrationFlow />} />
        <Route element={<RegistrationFlowProvider />}>
          <Route path="/register" element={<PublicAuthentication />} />
        </Route>
        <Route element={<RequireAuthentication />}>
          <Route element={<AppShell />}>
            <Route index element={<DashboardPage />} />
            <Route path="tenants" element={<TenantsPage />} />
            <Route path="tenants/:tenantId/members" element={<MembersPage />} />
            <Route path="members" element={<MembersPage />} />
            <Route path="settings" element={<SettingsPage />} />
            <Route element={<RegistrationPermissionGuard />}>
              <Route path="registrations" element={<RegistrationCenterPage />} />
              <Route path="registrations/personal" element={<PersonalRegistrationsPage />} />
              <Route path="registrations/organization" element={<OrganizationRegistrationsPage />} />
              <Route path="registrations/:type/:id" element={<RegistrationDetailPage />} />
            </Route>
            <Route path="platform-setup" element={<PlatformSetupPage />} />
            <Route path="platform-setup/registration" element={<RegistrationSetupPage />} />
            <Route path="platform-setup/legal-documents" element={<LegalDocumentsPage />} />
            <Route path="platform-setup/master-data" element={<MasterDataSetupPage />} />
            <Route path="platform-setup/system-configuration" element={<SystemConfigurationPage />} />
            <Route path="platform-setup/notifications" element={<NotificationsSetupPage />} />
            <Route path="platform-setup/access-approval" element={<AccessApprovalPage />} />
            <Route path="users" element={<UnavailablePage module="User directory" />} />
            <Route path="master-data" element={<Navigate to="/platform-setup/master-data" replace />} />
            <Route path="configuration" element={<Navigate to="/platform-setup/system-configuration" replace />} />
            <Route path="audit-logs" element={<UnavailablePage module="Audit logs" />} />
            <Route path="security-logs" element={<UnavailablePage module="Security logs" />} />
            <Route path="notifications" element={<Navigate to="/platform-setup/notifications" replace />} />
          </Route>
        </Route>
        <Route path="*" element={<MissingRoute />} />
      </Routes>
    </Suspense>
  );
}
