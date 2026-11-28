import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import type { ReactNode } from "react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { getRolePermissionMatrixAccess } from "../src/api/rolePermissionMatrix";
import { getRegistrationPolicy } from "../src/api/auth";
import { getCurrentTerms } from "../src/api/legal";
import { ApiRequestError } from "../src/api/client";
import { getOrganizationTypes, getTenantTypes } from "../src/api/tenants";
import {
  MasterDataSetupPage,
  PlatformSetupPage,
  RegistrationSetupPage,
} from "../src/features/setup/PlatformSetupPages";

vi.mock("../src/api/auth", () => ({ getRegistrationPolicy: vi.fn() }));
vi.mock("../src/api/legal", () => ({ getCurrentTerms: vi.fn() }));

vi.mock("../src/api/tenants", () => ({
  getOrganizationTypes: vi.fn(),
  getTenantTypes: vi.fn(),
}));

vi.mock("../src/api/rolePermissionMatrix", () => ({
  getRolePermissionMatrixAccess: vi.fn(),
}));

function renderWithProviders(page: ReactNode) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>{page}</MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("Platform Setup foundation", () => {
  beforeEach(() => {
    vi.mocked(getRegistrationPolicy).mockReset();
    vi.mocked(getCurrentTerms).mockReset();
    vi.mocked(getOrganizationTypes).mockReset();
    vi.mocked(getTenantTypes).mockReset().mockResolvedValue([]);
    vi.mocked(getRolePermissionMatrixAccess).mockReset().mockResolvedValue({ canRead: false, canUpdate: false });
  });

  it("shows all six sections under one Platform Setup entry", async () => {
    vi.mocked(getRolePermissionMatrixAccess).mockResolvedValue({ canRead: true, canUpdate: true });
    renderWithProviders(<PlatformSetupPage />);

    expect(screen.getByRole("heading", { name: "Platform Setup" })).toBeInTheDocument();
    const section = screen.getByRole("region", { name: "Platform Setup sections" });
    for (const name of [
      "Registration Setup",
      "Legal Documents",
      "Master Data",
      "System Configuration",
      "Notifications",
      "Role & Permission Matrix",
    ]) {
      expect(await screen.findByRole("link", { name: new RegExp(name) })).toHaveAttribute(
        "href",
        expect.stringMatching(/^\/platform-setup\//),
      );
    }
    expect(section.querySelectorAll("a")).toHaveLength(6);
    expect(screen.getByText(/System Configuration exposes only a protected metadata allowlist/))
      .toBeInTheDocument();
  });

  it("hides the matrix entry when the caller has no read capability", async () => {
    vi.mocked(getRolePermissionMatrixAccess).mockResolvedValue({ canRead: false, canUpdate: false });
    renderWithProviders(<PlatformSetupPage />);

    await waitFor(() => expect(getRolePermissionMatrixAccess).toHaveBeenCalledOnce());
    expect(screen.queryByRole("link", { name: /Role & Permission Matrix/ })).not.toBeInTheDocument();
  });

  it("shows effective policy and the actual published Terms for each registration scope", async () => {
    vi.mocked(getRolePermissionMatrixAccess).mockResolvedValue({ canRead: false, canUpdate: false });
    vi.mocked(getRegistrationPolicy).mockResolvedValue({
      termsRequired: true, passwordMinLength: 14, passwordMaxLength: 128,
      allowedRegistrationTypes: ["PERSONAL"],
    });
    vi.mocked(getCurrentTerms).mockImplementation(async (scope) => {
      if (scope === "ORGANIZATION") throw new ApiRequestError("TERMS_UNAVAILABLE", "Not available", 404);
      return {
        documentVersionId: "00000000-0000-4000-8000-000000000001", title: "Personal Terms",
        registrationType: scope, version: "1.2", effectiveAtUtc: "2026-01-01T00:00:00Z",
        documentUrl: "/terms", contentHash: "hash", publicationStatus: "PUBLISHED",
      };
    });
    renderWithProviders(<RegistrationSetupPage />);
    expect(await screen.findByText("14–128 characters")).toBeInTheDocument();
    const personal = await screen.findByRole("region", { name: "PERSONAL registration" });
    const organization = screen.getByRole("region", { name: "ORGANIZATION registration" });
    expect(within(personal).getByText("Registration enabled")).toBeInTheDocument();
    expect(await within(personal).findByText("Personal Terms")).toBeInTheDocument();
    expect(within(organization).getByText("Registration disabled")).toBeInTheDocument();
    expect(await within(organization).findByText("No published Terms for this scope.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /save/i })).not.toBeInTheDocument();
  });

  it("does not infer policy or request Terms when the policy API fails; supports retry", async () => {
    vi.mocked(getRolePermissionMatrixAccess).mockResolvedValue({ canRead: false, canUpdate: false });
    vi.mocked(getRegistrationPolicy).mockRejectedValueOnce(new Error("offline")).mockResolvedValueOnce({
      termsRequired: false, passwordMinLength: 12, passwordMaxLength: 128, allowedRegistrationTypes: [],
    });
    vi.mocked(getCurrentTerms).mockRejectedValue(new Error("offline"));
    renderWithProviders(<RegistrationSetupPage />);
    expect(await screen.findByText(/Registration policy could not be verified/)).toBeInTheDocument();
    expect(getCurrentTerms).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Refresh policy" }));
    expect(await screen.findByText("Not required by effective policy")).toBeInTheDocument();
    await waitFor(() => expect(screen.getAllByText("Terms readiness could not be verified.")).toHaveLength(2));
    expect(screen.queryByText("No published Terms for this scope.")).not.toBeInTheDocument();
  });

  it("flags required missing Terms instead of treating registration as ready", async () => {
    vi.mocked(getRolePermissionMatrixAccess).mockResolvedValue({ canRead: false, canUpdate: false });
    vi.mocked(getRegistrationPolicy).mockResolvedValue({
      termsRequired: true, passwordMinLength: 12, passwordMaxLength: 128,
      allowedRegistrationTypes: ["PERSONAL", "ORGANIZATION"],
    });
    vi.mocked(getCurrentTerms).mockRejectedValue(new ApiRequestError("TERMS_UNAVAILABLE", "Not available", 404));
    renderWithProviders(<RegistrationSetupPage />);
    await waitFor(() => expect(screen.getAllByText("Required Terms are not verified; registration readiness is incomplete.")).toHaveLength(2));
  });

  it("loads tenant types from the API and filters only that catalog", async () => {
    vi.mocked(getTenantTypes).mockResolvedValue([
      { code: "PERSONAL", name: "Personal workspace" },
      { code: "ORGANIZATION", name: "Organization workspace" },
    ]);
    vi.mocked(getOrganizationTypes).mockResolvedValue([{ code: "COMPANY", name: "Company", countryCode: "ID" }]);
    renderWithProviders(<MasterDataSetupPage />);
    const tenants = screen.getByRole("region", { name: "Tenant types" });
    const organizations = screen.getByRole("region", { name: "Organization types" });
    expect(await within(tenants).findByText("Personal workspace")).toBeInTheDocument();
    expect(await within(organizations).findByText("Company")).toBeInTheDocument();
    fireEvent.change(within(tenants).getByRole("textbox", { name: "Search tenant types" }), { target: { value: "organization" } });
    expect(within(tenants).queryByText("Personal workspace")).not.toBeInTheDocument();
    expect(within(tenants).getByText("Organization workspace")).toBeInTheDocument();
    expect(within(organizations).getByText("Company")).toBeInTheDocument();
  });

  it("distinguishes a catalog error from an empty result and retries independently", async () => {
    vi.mocked(getTenantTypes).mockRejectedValueOnce(new Error("offline")).mockResolvedValueOnce([{ code: "PERSONAL", name: "Personal workspace" }]);
    vi.mocked(getOrganizationTypes).mockResolvedValue([]);
    renderWithProviders(<MasterDataSetupPage />);
    const tenants = screen.getByRole("region", { name: "Tenant types" });
    const organizations = screen.getByRole("region", { name: "Organization types" });
    expect(await within(tenants).findByText(/Tenant types could not be loaded/)).toBeInTheDocument();
    expect(await within(organizations).findByText("No active records were returned by the API.")).toBeInTheDocument();
    fireEvent.click(within(tenants).getByRole("button", { name: "Refresh" }));
    expect(await within(tenants).findByText("Personal workspace")).toBeInTheDocument();
    expect(getOrganizationTypes).toHaveBeenCalledOnce();
  });

  it("shows only organization types returned by the existing master-data API", async () => {
    vi.mocked(getOrganizationTypes).mockResolvedValue([
      {
        organizationTypeId: 3,
        code: "COMPANY",
        name: "Company",
        countryCode: "ID",
      },
    ]);
    renderWithProviders(<MasterDataSetupPage />);

    expect(await screen.findByText("Company")).toBeInTheDocument();
    expect(screen.getByText("COMPANY")).toBeInTheDocument();
    expect(screen.getByText("ID")).toBeInTheDocument();
    expect(getOrganizationTypes).toHaveBeenCalledOnce();
    expect(screen.getByText(/Other master-data catalogs, editing, and approval are not exposed/))
      .toBeInTheDocument();
  });
});
