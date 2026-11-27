import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  getRegistrationDetail,
  getRegistrations,
  getRegistrationSummary,
  getRegistrationTimeline,
} from "../src/features/registrations/api";
import { RegistrationCenterPage } from "../src/features/registrations/RegistrationCenterPage";
import { RegistrationDetailPage } from "../src/features/registrations/RegistrationDetailPage";
import { PersonalRegistrationsPage } from "../src/features/registrations/PersonalRegistrationsPage";
import { DocumentRequirements } from "../src/features/registrations/DocumentRequirements";
import { PersonalIdentityForm } from "../src/features/registrations/PersonalIdentityForm";

vi.mock("../src/features/registrations/api", () => ({
  getRegistrationDetail: vi.fn(),
  getRegistrations: vi.fn(),
  getRegistrationSummary: vi.fn(),
  getRegistrationTimeline: vi.fn(),
}));

function renderWithRouter(children: ReactNode, initialEntries?: string[]) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={initialEntries}>{children}</MemoryRouter>
    </QueryClientProvider>,
  );
}

function renderDetail() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/registrations/organization/73"]}>
        <Routes>
          <Route path="/registrations/:type/:id" element={<RegistrationDetailPage />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("Registration Center", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("loads both live summaries and offers refresh/retry", async () => {
    vi.mocked(getRegistrationSummary).mockImplementation(async (type) => ({
      registrationType: type,
      totalRegistrations: type === "PERSONAL" ? 11 : 4,
      pendingEmailVerification: 2,
      emailVerified: type === "PERSONAL" ? 9 : 2,
      pendingReview: type === "PERSONAL" ? 0 : 1,
    }));
    renderWithRouter(<RegistrationCenterPage />);

    expect(await screen.findByText("11")).toBeInTheDocument();
    expect(screen.getByText("4")).toBeInTheDocument();
    expect(screen.getAllByText("Pending review")).toHaveLength(2);
    expect(getRegistrationSummary).toHaveBeenCalledWith("PERSONAL");
    expect(getRegistrationSummary).toHaveBeenCalledWith("ORGANIZATION");
    expect(screen.getByText("Monitor and manage personal and organization account registrations.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "PERSONAL Registration" })).toHaveAttribute("href", "/registrations/personal");
  });

  it("sends search, status filters, and pagination to the listing API", async () => {
    vi.mocked(getRegistrations).mockImplementation(async (params) => ({
      items: [{
        registrationApplicationId: 73,
        displayName: "Example User",
        email: "example@example.test",
        emailVerifiedAtUtc: null,
        applicationStatus: "IN_REVIEW",
        registrationType: "PERSONAL",
        registeredAtUtc: "2026-02-02T00:00:00Z",
      }],
      pageNumber: params.pageNumber,
      pageSize: params.pageSize,
      totalCount: 21,
      totalPages: 2,
      applicationStatuses: ["DRAFT", "IN_REVIEW", "APPROVED"],
    }));
    renderWithRouter(<PersonalRegistrationsPage />);

    expect(await screen.findByText("Example User")).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "APPROVED" })).toBeInTheDocument();
    expect(screen.getByText("Full Name")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Personal identity details" })).not.toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Document requirements" })).not.toBeInTheDocument();
    const user = userEvent.setup();
    await user.type(screen.getByRole("textbox", { name: "Search personal registrations" }), "example");
    await user.selectOptions(screen.getByRole("combobox", { name: "Filter by email verification" }), "PENDING");
    await waitFor(() => {
      expect(getRegistrations).toHaveBeenLastCalledWith({
        registrationType: "PERSONAL",
        search: "example",
        emailVerificationStatus: "PENDING",
        applicationStatus: undefined,
        pageNumber: 1,
        pageSize: 20,
      });
    });
    await user.click(screen.getByRole("button", { name: /Next/ }));

    await waitFor(() => {
      expect(getRegistrations).toHaveBeenLastCalledWith({
        registrationType: "PERSONAL",
        search: "example",
        emailVerificationStatus: "PENDING",
        applicationStatus: undefined,
        pageNumber: 2,
        pageSize: 20,
      });
    });
    expect(screen.getAllByRole("link", { name: "View details" })[0]).toHaveAttribute(
      "href",
      "/registrations/personal/73",
    );
  });

  it("shows actual tenant data, read-only profile status, and timeline in detail", async () => {
    vi.mocked(getRegistrationDetail).mockResolvedValue({
      registrationApplicationId: 73,
      user: {
        displayName: "Example User",
        email: "example@example.test",
        accountStatus: "ACTIVE",
        registeredAtUtc: "2026-02-02T00:00:00Z",
        emailVerifiedAtUtc: "2026-02-03T00:00:00Z",
      },
      application: {
        registrationType: "ORGANIZATION",
        applicationStatus: "APPROVED",
        createdAtUtc: "2026-02-02T00:00:00Z",
        updatedAtUtc: "2026-02-04T00:00:00Z",
        tenantId: 21,
      },
      tenant: {
        tenantId: 21,
        tenantCode: "EXAMPLE",
        tenantType: "ORGANIZATION",
        displayName: "Example Workspace",
        status: "ACTIVE",
      },
      profile: { completionStatus: null, personal: null, organization: null },
      latestVerificationChallenge: null,
    });

    vi.mocked(getRegistrationTimeline).mockResolvedValue([{
      occurredAtUtc: "2026-02-04T00:00:00Z",
      eventCode: "APPLICATION_APPROVED",
      fromStatus: "PENDING",
      toStatus: "APPROVED",
      actorDisplayName: "Reviewer",
    }]);
    renderDetail();

    expect(await screen.findByText("Example Workspace")).toBeInTheDocument();
    expect(screen.getByText("EXAMPLE")).toBeInTheDocument();
    expect(screen.getByText("Not provided")).toBeInTheDocument();
    expect(await screen.findByText("APPLICATION_APPROVED")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Back/ })).toBeInTheDocument();
  });

  it("retains identity and document components for explicit future onboarding use", async () => {
    const onSubmit = vi.fn();
    renderWithRouter(
      <>
        <PersonalIdentityForm onSubmit={onSubmit} />
        <DocumentRequirements requirements={[
          { id: "identity-document", name: "Identity document", required: true },
        ]} />
      </>,
    );

    expect(screen.getByText("Identity document")).toBeInTheDocument();
    const user = userEvent.setup();
    await user.type(screen.getByRole("textbox", { name: "City" }), "Sample City");
    await user.click(screen.getByRole("button", { name: "Save personal details" }));
    expect(onSubmit).toHaveBeenCalledWith(expect.objectContaining({ city: "Sample City" }));
  });

  it("shows explicit list loading and recoverable error states", async () => {
    vi.mocked(getRegistrations).mockRejectedValue(new Error("network unavailable"));
    renderWithRouter(<PersonalRegistrationsPage />);
    expect(await screen.findByRole("alert")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Retry" })).toBeInTheDocument();
  });
});
