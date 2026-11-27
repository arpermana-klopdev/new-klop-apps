import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { getRolePermissionMatrixAccess } from "../src/api/rolePermissionMatrix";
import { getOrganizationTypes } from "../src/api/tenants";
import {
  MasterDataSetupPage,
  PlatformSetupPage,
} from "../src/features/setup/PlatformSetupPages";

vi.mock("../src/api/tenants", () => ({
  getOrganizationTypes: vi.fn(),
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
    vi.mocked(getOrganizationTypes).mockReset();
    vi.mocked(getRolePermissionMatrixAccess).mockReset();
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
    expect(screen.getByText(/Other Platform Setup Center enhancements remain read-only or on HOLD/))
      .toBeInTheDocument();
  });

  it("hides the matrix entry when the caller has no read capability", async () => {
    vi.mocked(getRolePermissionMatrixAccess).mockResolvedValue({ canRead: false, canUpdate: false });
    renderWithProviders(<PlatformSetupPage />);

    await waitFor(() => expect(getRolePermissionMatrixAccess).toHaveBeenCalledOnce());
    expect(screen.queryByRole("link", { name: /Role & Permission Matrix/ })).not.toBeInTheDocument();
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
