import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import type { ReactNode } from "react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  getNotificationChannels,
  getNotificationHistory,
  getNotificationPermissions,
  getNotificationReadiness,
  getNotificationTemplate,
  getNotificationTemplates,
  previewNotificationDraft,
} from "../src/api/notifications";
import { NotificationManagementPage } from "../src/features/setup/NotificationManagementPage";

vi.mock("../src/api/notifications", () => ({
  createNotificationDraft: vi.fn(),
  getNotificationChannels: vi.fn(),
  getNotificationHistory: vi.fn(),
  getNotificationPermissions: vi.fn(),
  getNotificationReadiness: vi.fn(),
  getNotificationTemplate: vi.fn(),
  getNotificationTemplates: vi.fn(),
  previewNotificationDraft: vi.fn(),
  transitionNotificationVersion: vi.fn(),
  updateNotificationDraft: vi.fn(),
}));

function renderPage(page: ReactNode = <NotificationManagementPage />) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>{page}</MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("Notification management setup", () => {
  beforeEach(() => {
    vi.mocked(getNotificationPermissions).mockReset().mockResolvedValue({
      permissions: [
        "platform.notifications.read",
        "platform.notifications.history",
        "platform.notifications.settings.read",
        "platform.notifications.draft.preview",
      ],
    });
    vi.mocked(getNotificationTemplates).mockReset().mockResolvedValue([]);
    vi.mocked(getNotificationChannels).mockReset().mockResolvedValue([]);
    vi.mocked(getNotificationHistory).mockReset().mockResolvedValue({
      items: [], pageNumber: 1, pageSize: 20, totalCount: 0,
    });
    vi.mocked(getNotificationReadiness).mockReset().mockResolvedValue({
      smtpHostConfigured: true, smtpPortConfigured: true, senderConfigured: true, tlsRequired: true,
      credentialsConfigured: false, templateRolloutEnabled: false, deliveryAuditEnabled: false,
      verificationLifetimeStatus: "VALID",
    });
    vi.mocked(getNotificationTemplate).mockReset();
    vi.mocked(previewNotificationDraft).mockReset();
  });

  it("shows all tabs and actual channel, delivery, and safe settings data", async () => {
    vi.mocked(getNotificationChannels).mockResolvedValue([{
      channelCode: "EMAIL", displayName: "Email", status: "READY", isEnabled: true, readiness: "Configured",
    }]);
    renderPage();

    const tablist = screen.getByRole("tablist", { name: "Notification management sections" });
    for (const label of ["Templates", "Channels", "History", "Settings"]) {
      expect(within(tablist).getByRole("tab", { name: label })).toBeInTheDocument();
    }

    fireEvent.click(screen.getByRole("tab", { name: "Channels" }));
    expect(await screen.findByText("Email")).toBeInTheDocument();
    expect(screen.getByText(/Planned, not enabled: SMS, WhatsApp, and in-app/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("tab", { name: "History" }));
    expect(await screen.findByText("No delivery attempts are recorded.")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("tab", { name: "Settings" }));
    expect(await screen.findByText("SMTP host configured")).toBeInTheDocument();
    expect(screen.getByText(/No test-send or network probe/)).toBeInTheDocument();
    expect(screen.queryByText(/smtp\.example|password_ref|secret-value/i)).not.toBeInTheDocument();
  });

  it("does not fetch or expose notification data when permissions cannot be verified", async () => {
    vi.mocked(getNotificationPermissions).mockRejectedValue(new Error("offline"));
    renderPage();

    expect(await screen.findByText("Notification permissions could not be verified.")).toBeInTheDocument();
    await waitFor(() => expect(getNotificationTemplates).not.toHaveBeenCalled());
    fireEvent.click(screen.getByRole("tab", { name: "Channels" }));
    expect(getNotificationChannels).not.toHaveBeenCalled();
  });

  it("uses stable history pages and exposes previous and next controls", async () => {
    const firstPage = Array.from({ length: 20 }, (_, index) => ({
      attemptId: index + 1,
      deliveryId: `delivery-${index + 1}`,
      templateCode: "EMAIL_VERIFICATION",
      templateVersion: "1",
      channelCode: "EMAIL",
      outcome: "PROVIDER_ACCEPTED",
      safeErrorCategory: null,
      occurredAtUtc: "2026-01-01T00:00:00Z",
      correlationId: `correlation-${index + 1}`,
    }));
    const secondPage = [{
      attemptId: 21,
      deliveryId: "delivery-21",
      templateCode: "ROW_21",
      templateVersion: "1",
      channelCode: "EMAIL",
      outcome: "PROVIDER_ACCEPTED",
      safeErrorCategory: null,
      occurredAtUtc: "2026-01-01T00:00:00Z",
      correlationId: "correlation-21",
    }];
    vi.mocked(getNotificationHistory).mockImplementation(async (pageNumber = 1, pageSize = 20) => ({
      items: pageNumber === 1 ? firstPage : secondPage,
      pageNumber,
      pageSize,
      totalCount: 21,
    }));
    renderPage();
    fireEvent.click(screen.getByRole("tab", { name: "History" }));

    expect(await screen.findByText("Page 1 · 21 attempts")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    expect(await screen.findByText("ROW_21 · 1")).toBeInTheDocument();
    expect(screen.getByText("Page 2 · 21 attempts")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Previous" }));
    expect(await screen.findByText("Page 1 · 21 attempts")).toBeInTheDocument();
  });

  it("previews selected versions only with synthetic values", async () => {
    const template = {
      templateId: "template-1", templateCode: "EMAIL_VERIFICATION", displayName: "Verification",
      channelCode: "EMAIL", localeCode: "en", activeVersionId: null, activeVersionNumber: null,
      activeVersionStatus: null, concurrencyVersion: "AQIDBAUGBwg=",
    };
    vi.mocked(getNotificationTemplates).mockResolvedValue([template]);
    vi.mocked(getNotificationTemplate).mockResolvedValue({
      templateId: template.templateId,
      templateCode: template.templateCode,
      displayName: template.displayName,
      versions: [{
        versionId: "version-1", templateCode: template.templateCode, displayName: template.displayName,
        versionNumber: 1, status: "DRAFT", subject: "Verify", body: "{{verification_link}} {{expiry_hours}}",
        channelCode: "EMAIL", localeCode: "en", createdAtUtc: "2026-01-01T00:00:00Z",
        concurrencyVersion: "AQIDBAUGBwg=",
      }],
    });
    vi.mocked(previewNotificationDraft).mockResolvedValue({
      subject: "Verify", body: "https://preview.invalid/verify-email#token=PREVIEW_ONLY 24",
    });
    renderPage();

    fireEvent.click(await screen.findByRole("button", { name: /Verification.*EMAIL/ }));
    fireEvent.click(await screen.findByRole("button", { name: "v1 · DRAFT" }));
    fireEvent.click(screen.getByRole("button", { name: "Preview with synthetic values" }));

    expect(await screen.findByText(/PREVIEW_ONLY/)).toBeInTheDocument();
    expect(screen.getByText("Preview values are synthetic and nonfunctional. No message was sent.")).toBeInTheDocument();
    expect(previewNotificationDraft).toHaveBeenCalledWith("version-1");
  });
});
