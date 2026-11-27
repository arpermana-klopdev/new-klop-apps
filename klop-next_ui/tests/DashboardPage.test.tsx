import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { getMyTenants } from "../src/api/tenants";
import { DashboardPage } from "../src/features/dashboard/DashboardPage";

vi.mock("../src/api/tenants", () => ({
  getMyTenants: vi.fn(),
}));

vi.mock("../src/app/AuthContext", () => ({
  useAuth: () => ({
    profile: {
      userId: 7,
      displayName: "Ada Lovelace",
      email: "ada@example.com",
      emailVerifiedAtUtc: null,
    },
  }),
}));

function renderDashboard() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <DashboardPage />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("DashboardPage", () => {
  beforeEach(() => {
    vi.mocked(getMyTenants).mockReset();
  });

  it("shows a valid zero-membership account without implying a platform tenant count", async () => {
    vi.mocked(getMyTenants).mockResolvedValue([]);
    renderDashboard();

    expect(await screen.findByText("No tenant memberships for this account")).toBeInTheDocument();
    expect(screen.getByText("0")).toBeInTheDocument();
    expect(screen.getByText(/not a count of all tenants on the platform/i)).toBeInTheDocument();
    expect(screen.getByText(/No platform role or tenant membership is inferred/i)).toBeInTheDocument();
    expect(screen.queryByText("Secure session")).not.toBeInTheDocument();
  });

  it("groups only API-returned PERSONAL and ORGANIZATION tenant data", async () => {
    vi.mocked(getMyTenants).mockResolvedValue([
      {
        tenantId: 1,
        tenantCode: "P-001",
        displayName: "Personal workspace",
        tenantTypeCode: "PERSONAL",
        tenantStatusCode: "Active",
        membershipStatusCode: "Accepted",
      },
      {
        tenantId: 2,
        tenantCode: "O-001",
        displayName: "Example organization",
        tenantTypeCode: "ORGANIZATION",
        tenantStatusCode: "Active",
        membershipStatusCode: "Accepted",
      },
    ]);
    renderDashboard();

    expect(await screen.findByRole("heading", { name: "Personal overview" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Organization overview" })).toBeInTheDocument();
    expect(screen.getByText("Personal workspace")).toBeInTheDocument();
    expect(screen.getByText("Example organization")).toBeInTheDocument();
    expect(screen.getByText("Platform-wide totals and effective role information are not included in the current API response.")).toBeInTheDocument();
  });

  it("does not render a successful empty state when tenant loading fails", async () => {
    vi.mocked(getMyTenants).mockRejectedValue(new Error("Service unavailable."));
    renderDashboard();

    expect(await screen.findByRole("alert")).toHaveTextContent("Service unavailable.");
    expect(screen.queryByText("No tenant memberships for this account")).not.toBeInTheDocument();
  });
});
