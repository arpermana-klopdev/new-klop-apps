import { describe, expect, it } from "vitest";
import { moduleForRoute, moduleRegistry, modulesForContext } from "../src/app/modules";
import { PLATFORM_REGISTRATIONS_READ } from "../src/app/platformRegistrationPermissions";

describe("portal module registry", () => {
  it("resolves available and coming-soon routes from one registry", () => {
    expect(moduleForRoute("/")).toMatchObject({
      id: "overview",
      availability: "available",
    });
    expect(moduleForRoute("/audit-logs")).toMatchObject({
      id: "audit-logs",
      availability: "coming-soon",
    });
    expect(moduleForRoute("/not-registered")).toBeUndefined();
  });

  it("keeps the platform and tenant context module sets distinct", () => {
    const platformIds = modulesForContext("platform").map((module) => module.id);
    const organizationIds = modulesForContext("organization").map((module) => module.id);
    const personalIds = modulesForContext("personal").map((module) => module.id);

    expect(platformIds).toContain("user-directory");
    expect(platformIds).toContain("registrations");
    expect(platformIds).toContain("platform-setup");
    expect(platformIds).toContain("personal-registrations");
    expect(platformIds).not.toContain("members");
    expect(organizationIds).toContain("members");
    expect(organizationIds).not.toContain("personal-registrations");
    expect(personalIds).toContain("profile");
    expect(personalIds).not.toContain("members");
  });

  it("keeps setup sections nested outside the primary navigation group", () => {
    const setupSections = moduleRegistry.filter((module) => module.group === "Platform Setup");

    expect(setupSections.map((module) => module.route)).toEqual([
      "/platform-setup/registration",
      "/platform-setup/legal-documents",
      "/platform-setup/master-data",
      "/platform-setup/system-configuration",
      "/platform-setup/notifications",
      "/platform-setup/access-approval",
    ]);
    expect(moduleRegistry.filter((module) => module.group === "Platform" && module.sidebar !== false)
      .map((module) => module.id)).toContain("platform-setup");
  });

  it("does not label the preview module definitions as verified capabilities", () => {
    expect(moduleRegistry.find((module) => module.id === "registrations")?.requiredCapability)
      .toBe(PLATFORM_REGISTRATIONS_READ);
    expect(moduleRegistry.filter((module) => module.id !== "registrations")
      .every((module) => module.requiredCapability === undefined)).toBe(true);
    expect(moduleRegistry.some((module) => module.id === "access-approval" && module.availability === "coming-soon"))
      .toBe(true);
  });
});
