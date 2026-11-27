import { useAuth } from "./AuthContext";
import {
  PLATFORM_REGISTRATIONS_READ,
  usePlatformRegistrationPermissions,
} from "./platformRegistrationPermissions";
import { Link, Outlet } from "react-router-dom";
import { Button, LoadingState, Notice } from "../components/ui";

export function RegistrationPermissionGuard() {
  const { profile } = useAuth();
  const permissionsQuery = usePlatformRegistrationPermissions(profile?.userId);

  if (!profile?.userId || permissionsQuery.isPending || permissionsQuery.isFetching) {
    return (
      <div className="grid min-h-[40vh] place-items-center">
        <LoadingState label="Checking registration access" />
      </div>
    );
  }
  if (permissionsQuery.isError) {
    return (
      <div className="mx-auto grid min-h-[40vh] max-w-lg content-center gap-4 px-5">
        <Notice>Registration access could not be verified.</Notice>
        <Button className="w-full" onClick={() => void permissionsQuery.refetch()}>
          Retry
        </Button>
      </div>
    );
  }
  if (!permissionsQuery.data?.permissions.includes(PLATFORM_REGISTRATIONS_READ)) {
    return (
      <div className="mx-auto max-w-lg py-16">
        <Notice>Access denied. Your account does not have permission to view registrations.</Notice>
        <Link to="/" className="mt-5 inline-block text-sm font-semibold text-brand-600">
          Return to overview
        </Link>
      </div>
    );
  }
  return <Outlet />;
}
