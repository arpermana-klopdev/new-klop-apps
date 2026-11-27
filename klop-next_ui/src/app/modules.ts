import {
  Activity,
  Bell,
  Building2,
  ClipboardList,
  Database,
  FileText,
  LayoutDashboard,
  LogOut,
  Settings2,
  ShieldCheck,
  UserRound,
  UsersRound,
  type LucideIcon,
} from "lucide-react";
import { PLATFORM_REGISTRATIONS_READ } from "./platformRegistrationPermissions";

export type PortalContext = "platform" | "personal" | "organization";
export type ModuleAvailability = "available" | "coming-soon";
export type NavigationGroup = "Platform" | "Platform Setup" | "Account" | "Tenant management";

export type ModuleDescriptor = {
  id: string;
  label: string;
  route: string | null;
  icon: LucideIcon;
  contexts: readonly PortalContext[];
  requiredCapability?: string;
  availability: ModuleAvailability;
  group: NavigationGroup;
  order: number;
  description: string;
  sidebar?: boolean;
};

const allContexts: readonly PortalContext[] = ["platform", "personal", "organization"];

export const moduleRegistry: readonly ModuleDescriptor[] = [
  {
    id: "overview",
    label: "Overview",
    route: "/",
    icon: LayoutDashboard,
    contexts: ["platform"],
    availability: "available",
    group: "Platform",
    order: 10,
    description: "Platform overview and available administration modules.",
  },
  {
    id: "registrations",
    label: "Registrations",
    route: "/registrations",
    icon: ClipboardList,
    contexts: ["platform"],
    requiredCapability: PLATFORM_REGISTRATIONS_READ,
    availability: "available",
    group: "Platform",
    order: 20,
    description: "Registration center for PERSONAL and ORGANIZATION workflows.",
  },
  {
    id: "personal-registrations",
    label: "PERSONAL Registrations",
    route: "/registrations/personal",
    icon: UserRound,
    contexts: ["platform"],
    availability: "coming-soon",
    group: "Platform",
    order: 21,
    description: "Personal registration queue and identity review.",
    sidebar: false,
  },
  {
    id: "organization-registrations",
    label: "ORGANIZATION Registrations",
    route: "/registrations/organization",
    icon: Building2,
    contexts: ["platform"],
    availability: "coming-soon",
    group: "Platform",
    order: 22,
    description: "Organization registration queue and review.",
    sidebar: false,
  },
  {
    id: "tenants",
    label: "Tenants",
    route: "/tenants",
    icon: Building2,
    contexts: ["platform"],
    availability: "available",
    group: "Platform",
    order: 30,
    description: "Tenant records available to the authenticated account.",
  },
  {
    id: "platform-setup",
    label: "Platform Setup",
    route: "/platform-setup",
    icon: Settings2,
    contexts: ["platform"],
    availability: "available",
    group: "Platform",
    order: 50,
    description: "Platform-wide business settings and operational requirements.",
  },
  {
    id: "registration-setup",
    label: "Registration Setup",
    route: "/platform-setup/registration",
    icon: ClipboardList,
    contexts: ["platform"],
    availability: "coming-soon",
    group: "Platform Setup",
    order: 10,
    description: "Read registration and onboarding policy status when safe configuration APIs are available.",
    sidebar: false,
  },
  {
    id: "legal-documents",
    label: "Legal Documents",
    route: "/platform-setup/legal-documents",
    icon: FileText,
    contexts: ["platform"],
    availability: "available",
    group: "Platform Setup",
    order: 20,
    description: "View published Terms and preview the existing draft; administrative actions require protected APIs.",
    sidebar: false,
  },
  {
    id: "master-data",
    label: "Master Data",
    route: "/platform-setup/master-data",
    icon: Database,
    contexts: ["platform"],
    availability: "available",
    group: "Platform Setup",
    order: 30,
    description: "View organization-type reference data from the existing endpoint.",
    sidebar: false,
  },
  {
    id: "system-configuration",
    label: "System Configuration",
    route: "/platform-setup/system-configuration",
    icon: Settings2,
    contexts: ["platform"],
    availability: "coming-soon",
    group: "Platform Setup",
    order: 40,
    description: "Configuration administration requires a protected API and approval workflow.",
    sidebar: false,
  },
  {
    id: "setup-notifications",
    label: "Notifications",
    route: "/platform-setup/notifications",
    icon: Bell,
    contexts: ["platform"],
    availability: "coming-soon",
    group: "Platform Setup",
    order: 50,
    description: "Notification templates and activation rules are not exposed by the current API.",
    sidebar: false,
  },
  {
    id: "access-approval",
    label: "Role & Permission Matrix",
    route: "/platform-setup/access-approval",
    icon: ShieldCheck,
    contexts: ["platform"],
    availability: "coming-soon",
    group: "Platform Setup",
    order: 60,
    description: "Database-backed role and permission administration across authorization contexts.",
    sidebar: false,
  },
  {
    id: "members",
    label: "Members & roles",
    route: "/members",
    icon: UsersRound,
    contexts: ["organization"],
    availability: "available",
    group: "Tenant management",
    order: 10,
    description: "Use supported membership actions; the API enforces access.",
  },
  {
    id: "profile",
    label: "My Profile",
    route: "/settings",
    icon: UserRound,
    contexts: allContexts,
    availability: "available",
    group: "Account",
    order: 10,
    description: "View the authenticated profile and theme preferences.",
  },
  {
    id: "user-directory",
    label: "User directory",
    route: "/users",
    icon: UsersRound,
    contexts: ["platform"],
    availability: "coming-soon",
    group: "Platform",
    order: 40,
    description: "User search and administration are not provided by the current API.",
  },
  {
    id: "audit-logs",
    label: "Audit logs",
    route: "/audit-logs",
    icon: Activity,
    contexts: ["platform"],
    availability: "coming-soon",
    group: "Platform",
    order: 70,
    description: "Audit event search is not provided by the current API.",
  },
  {
    id: "security-logs",
    label: "Security logs",
    route: "/security-logs",
    icon: ShieldCheck,
    contexts: ["platform"],
    availability: "coming-soon",
    group: "Platform",
    order: 80,
    description: "Security event history is not provided by the current API.",
  },
  {
    id: "logout",
    label: "Logout",
    route: null,
    icon: LogOut,
    contexts: allContexts,
    availability: "available",
    group: "Account",
    order: 40,
    description: "End the authenticated session using the existing API.",
  },
];

export function modulesForContext(context: PortalContext): ModuleDescriptor[] {
  return moduleRegistry
    .filter((module) => module.contexts.includes(context))
    .sort((left, right) => left.order - right.order);
}

export function moduleForRoute(route: string): ModuleDescriptor | undefined {
  return moduleRegistry.find((module) => module.route === route);
}
