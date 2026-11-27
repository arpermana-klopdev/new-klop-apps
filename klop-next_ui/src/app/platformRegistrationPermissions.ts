import { useQuery } from "@tanstack/react-query";
import type { Profile } from "../api/contracts";
import { getRegistrationPermissions } from "../features/registrations/api";

export const PLATFORM_REGISTRATIONS_READ = "platform.registrations.read";

export function usePlatformRegistrationPermissions(userId: Profile["userId"] | undefined) {
  return useQuery({
    queryKey: ["platform-registration-permissions", userId],
    queryFn: getRegistrationPermissions,
    enabled: userId !== undefined,
    staleTime: 0,
    refetchOnMount: "always",
    refetchOnWindowFocus: true,
    retry: false,
  });
}
