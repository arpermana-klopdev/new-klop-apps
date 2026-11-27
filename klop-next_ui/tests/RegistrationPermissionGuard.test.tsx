import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { RegistrationPermissionGuard } from "../src/app/RegistrationPermissionGuard";
import { PLATFORM_REGISTRATIONS_READ } from "../src/app/platformRegistrationPermissions";
import { getRegistrationPermissions } from "../src/features/registrations/api";

vi.mock("../src/app/AuthContext", () => ({
  useAuth: () => ({ profile: { userId: 7 } }),
}));

vi.mock("../src/features/registrations/api", () => ({
  getRegistrationPermissions: vi.fn(),
}));

function renderGuard() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/registrations"]}>
        <Routes>
          <Route path="/" element={<p>Overview</p>} />
          <Route element={<RegistrationPermissionGuard />}>
            <Route path="/registrations" element={<p>Protected registrations</p>} />
          </Route>
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("RegistrationPermissionGuard", () => {
  beforeEach(() => {
    vi.mocked(getRegistrationPermissions).mockReset();
  });

  it("shows an access-denied state without the effective read permission", async () => {
    vi.mocked(getRegistrationPermissions).mockResolvedValue({ permissions: [] });
    renderGuard();

    expect(await screen.findByText(/Access denied/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Return to overview" })).toHaveAttribute("href", "/");
    expect(screen.queryByText("Protected registrations")).not.toBeInTheDocument();
  });

  it("renders registration routes when the effective read permission is present", async () => {
    vi.mocked(getRegistrationPermissions).mockResolvedValue({
      permissions: [PLATFORM_REGISTRATIONS_READ],
    });
    renderGuard();

    expect(await screen.findByText("Protected registrations")).toBeInTheDocument();
  });
});
