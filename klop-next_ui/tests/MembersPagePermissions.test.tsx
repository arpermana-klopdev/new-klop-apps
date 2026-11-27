import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { getMyTenants, getTenantPermissions } from "../src/api/tenants";
import { MembersPage } from "../src/features/members/MembersPage";
import {
  TENANT_MEMBERS_REMOVE,
  TENANT_ROLES_ASSIGN,
} from "../src/app/tenantPermissions";

vi.mock("../src/api/tenants", () => ({
  acceptMembership: vi.fn(),
  assignRole: vi.fn(),
  getMyTenants: vi.fn(),
  getTenantPermissions: vi.fn(),
  removeMember: vi.fn(),
  revokeRole: vi.fn(),
}));

function renderMembersPage(tenantId: number) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[`/tenants/${tenantId}/members`]}>
        <Routes>
          <Route path="/tenants/:tenantId/members" element={<MembersPage />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("MembersPage permission gating", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(getMyTenants).mockResolvedValue([
      { tenantId: 7, displayName: "Organization workspace", tenantTypeCode: "ORGANIZATION" },
    ]);
  });

  it("shows membership actions only when the selected tenant returns those permissions", async () => {
    vi.mocked(getTenantPermissions).mockResolvedValue({
      permissions: [TENANT_ROLES_ASSIGN, TENANT_MEMBERS_REMOVE],
    });
    renderMembersPage(7);

    expect(await screen.findByRole("button", { name: "Assign role" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Remove member" })).toBeInTheDocument();
    expect(getTenantPermissions).toHaveBeenCalledWith("7");
  });

  it("hides membership actions and explains a denied PERSONAL tenant", async () => {
    vi.mocked(getMyTenants).mockResolvedValue([
      { tenantId: 8, displayName: "Personal workspace", tenantTypeCode: "PERSONAL" },
    ]);
    vi.mocked(getTenantPermissions).mockResolvedValue({ permissions: [] });
    renderMembersPage(8);

    expect(
      await screen.findByText(/Personal workspaces do not support additional members/),
    ).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Assign role" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Remove member" })).not.toBeInTheDocument();
  });

  it("does not offer membership administration in PERSONAL even with an inconsistent permission response", async () => {
    vi.mocked(getMyTenants).mockResolvedValue([
      { tenantId: 8, displayName: "Personal workspace", tenantTypeCode: "PERSONAL" },
    ]);
    vi.mocked(getTenantPermissions).mockResolvedValue({
      permissions: [TENANT_ROLES_ASSIGN, TENANT_MEMBERS_REMOVE],
    });
    renderMembersPage(8);
    expect(await screen.findByText(/Personal workspaces do not support additional members/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Assign role" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Remove member" })).not.toBeInTheDocument();
  });

  it("fails closed when tenant permission discovery fails", async () => {
    vi.mocked(getTenantPermissions).mockRejectedValue(new Error("request failed"));
    renderMembersPage(7);

    expect(await screen.findByText("Tenant permissions could not be verified.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Assign role" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Remove member" })).not.toBeInTheDocument();
  });
});
