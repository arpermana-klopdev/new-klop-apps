import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { getMyTenants } from "../src/api/tenants";
import { TenantsPage } from "../src/features/tenants/TenantsPage";

vi.mock("../src/api/tenants", () => ({
  createTenant: vi.fn(),
  getMyTenants: vi.fn(),
  getOrganizationTypes: vi.fn(),
  inviteMember: vi.fn(),
}));

describe("TenantsPage management context", () => {
  beforeEach(() => {
    vi.mocked(getMyTenants).mockReset();
  });

  it("links tenant member actions into the tenant-scoped management route", async () => {
    vi.mocked(getMyTenants).mockResolvedValue([
      {
        tenantId: 42,
        tenantCode: "ORG-42",
        displayName: "Example organization",
        tenantTypeCode: "ORGANIZATION",
        tenantStatusCode: "Active",
        membershipStatusCode: "Accepted",
      },
    ]);
    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });

    render(
      <QueryClientProvider client={queryClient}>
        <MemoryRouter>
          <TenantsPage />
        </MemoryRouter>
      </QueryClientProvider>,
    );

    const managementLinks = await screen.findAllByRole("link", {
      name: "Manage members & roles for Example organization",
    });
    expect(managementLinks.length).toBeGreaterThan(0);
    for (const link of managementLinks) {
      expect(link).toHaveAttribute("href", "/tenants/42/members");
    }
    expect(screen.getByText(/not a platform-wide tenant directory/i)).toBeInTheDocument();
  });
});
