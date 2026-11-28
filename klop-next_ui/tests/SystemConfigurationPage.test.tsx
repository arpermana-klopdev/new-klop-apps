import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, within } from "@testing-library/react";
import type { ReactNode } from "react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ApiRequestError } from "../src/api/client";
import {
  getSystemConfigurationApprovals,
  getSystemConfigurationCatalog,
  getSystemConfigurationHistory,
  getSystemConfigurationPermissions,
  getSystemConfigurationRequests,
} from "../src/api/systemConfiguration";
import { SystemConfigurationPage } from "../src/features/setup/SystemConfigurationPage";

vi.mock("../src/api/systemConfiguration", () => ({
  getSystemConfigurationPermissions: vi.fn(),
  getSystemConfigurationCatalog: vi.fn(),
  getSystemConfigurationRequests: vi.fn(),
  getSystemConfigurationApprovals: vi.fn(),
  getSystemConfigurationHistory: vi.fn(),
  createSystemConfigurationDraft: vi.fn(),
  updateSystemConfigurationDraft: vi.fn(),
  submitSystemConfigurationDraft: vi.fn(),
  decideSystemConfigurationRequest: vi.fn(),
  cancelSystemConfigurationRequest: vi.fn(),
  applySystemConfigurationRequest: vi.fn(),
}));

function renderWithProviders(page: ReactNode) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>{page}</MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("System Configuration page", () => {
  beforeEach(() => {
    vi.mocked(getSystemConfigurationPermissions).mockReset();
    vi.mocked(getSystemConfigurationCatalog).mockReset();
    vi.mocked(getSystemConfigurationRequests).mockReset();
    vi.mocked(getSystemConfigurationApprovals).mockReset();
    vi.mocked(getSystemConfigurationHistory).mockReset();
  });

  it("fails closed when the capability endpoint denies or cannot verify access", async () => {
    vi.mocked(getSystemConfigurationPermissions).mockRejectedValue(
      new ApiRequestError("FORBIDDEN", "denied", 403),
    );
    renderWithProviders(<SystemConfigurationPage />);

    expect(await screen.findByText(/Configuration capability could not be verified/)).toBeInTheDocument();
    expect(getSystemConfigurationCatalog).not.toHaveBeenCalled();
    expect(getSystemConfigurationRequests).not.toHaveBeenCalled();
  });

  it("shows only safe metadata and no edit controls while the candidate is held", async () => {
    vi.mocked(getSystemConfigurationPermissions).mockResolvedValue({
      canRead: true, canCreateRequest: true, canEditRequest: true, canSubmit: true,
      canCancel: true, canApprove: true, canApply: true, canReadHistory: true,
    });
    vi.mocked(getSystemConfigurationCatalog).mockResolvedValue({
      items: [{
        configurationKey: "database.command_timeout_seconds",
        category: "Database",
        valueType: "INTEGER",
        storageType: "PLAIN",
        readiness: "PRESENT",
        managementStatus: "HOLD",
        isEditable: false,
        requiresApproval: true,
        requiresRestart: true,
        versionNumber: 1,
        concurrencyVersion: "AQIDBAUGBwg=",
        createdAtUtc: "2026-01-01T00:00:00Z",
        updatedAtUtc: null,
        minimum: 1,
        maximum: 120,
      }],
      pageNumber: 1,
      pageSize: 25,
      totalCount: 1,
      unclassifiedCount: 3,
    });
    renderWithProviders(<SystemConfigurationPage />);

    const table = await screen.findByRole("table", { name: /allowlisted configuration metadata/i });
    expect(within(table).getByText("database.command_timeout_seconds")).toBeInTheDocument();
    expect(within(table).getByText("PRESENT")).toBeInTheDocument();
    expect(within(table).getByText("HOLD")).toBeInTheDocument();
    expect(within(table).queryByRole("button", { name: "Request change" })).not.toBeInTheDocument();
    expect(screen.getByText("Unclassified keys withheld: 3")).toBeInTheDocument();
    expect(screen.getByText(/Persisted SQL metadata does not represent the process’s startup-loaded runtime value/))
      .toBeInTheDocument();
  });

  it("keeps request, approval, and history views separate and paginated", async () => {
    vi.mocked(getSystemConfigurationPermissions).mockResolvedValue({
      canRead: true, canCreateRequest: false, canEditRequest: false, canSubmit: false,
      canCancel: false, canApprove: true, canApply: false, canReadHistory: true,
    });
    vi.mocked(getSystemConfigurationCatalog).mockResolvedValue({
      items: [], pageNumber: 1, pageSize: 25, totalCount: 0, unclassifiedCount: 0,
    });
    vi.mocked(getSystemConfigurationRequests).mockResolvedValue({
      items: [{
        requestId: "00000000-0000-4000-8000-000000000001",
        configurationKey: "database.command_timeout_seconds",
        status: "SUBMITTED",
        proposedInteger: 45,
        expectedVersionNumber: 1,
        reasonCode: "CAPACITY_ADJUSTMENT",
        createdAtUtc: "2026-01-01T00:00:00Z",
        updatedAtUtc: null,
        requestConcurrencyVersion: "AQIDBAUGBwg=",
      }],
      pageNumber: 1, pageSize: 25, totalCount: 1,
    });
    vi.mocked(getSystemConfigurationApprovals).mockResolvedValue({
      items: [], pageNumber: 1, pageSize: 25, totalCount: 0,
    });
    vi.mocked(getSystemConfigurationHistory).mockResolvedValue({
      items: [], pageNumber: 1, pageSize: 25, totalCount: 0,
    });
    renderWithProviders(<SystemConfigurationPage />);

    expect(await screen.findByRole("tab", { name: "Approvals" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("tab", { name: "Change Requests" }));
    expect(await screen.findByText("CAPACITY_ADJUSTMENT")).toBeInTheDocument();
    expect(screen.getByText("45")).toBeInTheDocument();
    expect(screen.getByRole("navigation", { name: "Configuration results pages" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("tab", { name: "History" }));
    expect(await screen.findByText("No applied configuration history was returned.")).toBeInTheDocument();
  });
});
