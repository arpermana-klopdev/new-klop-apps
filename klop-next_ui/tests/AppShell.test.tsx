import { fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AppShell } from "../src/components/AppShell";
import { getRegistrationPermissions } from "../src/features/registrations/api";
import { PLATFORM_REGISTRATIONS_READ } from "../src/app/platformRegistrationPermissions";

const { signOut, setTheme } = vi.hoisted(() => ({
  signOut: vi.fn(),
  setTheme: vi.fn(),
}));

vi.mock("../src/app/AuthContext", () => ({
  useAuth: () => ({
    profile: {
      userId: 7,
      displayName: "Ada Lovelace",
      email: "ada@example.com",
      emailVerifiedAtUtc: "2026-01-01T00:00:00Z",
    },
    signOut,
  }),
}));

vi.mock("../src/features/registrations/api", () => ({
  getRegistrationPermissions: vi.fn(),
}));

vi.mock("../src/app/ThemeContext", () => ({
  useTheme: () => ({ theme: "light", setTheme }),
}));

function renderShell() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/"]}>
        <Routes>
          <Route element={<AppShell />}>
            <Route index element={<p>Overview content</p>} />
            <Route path="login" element={<p>Signed out</p>} />
          </Route>
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("AppShell", () => {
  beforeEach(() => {
    signOut.mockReset().mockResolvedValue(undefined);
    setTheme.mockReset();
    vi.mocked(getRegistrationPermissions).mockReset().mockResolvedValue({
      permissions: [PLATFORM_REGISTRATIONS_READ],
    });
  });

  it("uses the shared brand, permission-aware navigation, theme control, and authenticated profile", async () => {
    renderShell();

    expect(screen.getByAltText("KLOP Next – One Portal")).toBeInTheDocument();
    const navigation = screen.getByRole("navigation", { name: "Platform administration" });
    expect(navigation).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Overview" })).toBeInTheDocument();
    expect(await screen.findByRole("link", { name: "Registrations" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Tenants" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /User directory/ })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Platform Setup/ })).toHaveAttribute("href", "/platform-setup");
    expect(screen.queryByRole("link", { name: /Master data/ })).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /^Configuration/ })).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Audit logs/ })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Security logs/ })).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Members & roles" })).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "My Profile" })).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /Notifications/ })).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Switch to dark theme" })).toBeInTheDocument();
    expect(screen.getByText("Data and authorization provided by KLOP PLATFORM API")).toBeInTheDocument();
  });

  it("hides registration navigation when the effective permission is absent", async () => {
    vi.mocked(getRegistrationPermissions).mockResolvedValue({ permissions: [] });
    renderShell();

    await vi.waitFor(() => expect(getRegistrationPermissions).toHaveBeenCalledOnce());
    expect(screen.queryByRole("link", { name: "Registrations" })).not.toBeInTheDocument();
  });

  it("preserves logout through the authenticated identity menu", async () => {
    renderShell();

    fireEvent.click(screen.getByRole("button", { name: /Ada Lovelace/ }));
    expect(screen.getByRole("link", { name: "My Profile" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Account Settings" })).toHaveAttribute("href", "/settings#appearance");
    expect(screen.queryByRole("link", { name: /Notifications/ })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Sign out" }));

    expect(signOut).toHaveBeenCalledOnce();
    expect(await screen.findByText("Signed out")).toBeInTheDocument();
  });
});
