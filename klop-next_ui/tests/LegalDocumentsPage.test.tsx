import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ApiRequestError } from "../src/api/client";
import {
  getCurrentTerms,
  getPlatformLegalDocumentPermissions,
  getPlatformLegalDocuments,
  uploadPlatformLegalDocument,
} from "../src/api/legal";
import { LegalDocumentsPage } from "../src/features/setup/LegalDocumentsPage";

vi.mock("../src/api/legal", () => ({
  getCurrentTerms: vi.fn(),
  getPlatformLegalDocumentPermissions: vi.fn().mockResolvedValue({ permissions: [] }),
  getPlatformLegalDocuments: vi.fn().mockResolvedValue([]),
  uploadPlatformLegalDocument: vi.fn(),
  updatePlatformLegalDocumentDraft: vi.fn(),
  getPlatformLegalDocumentPreview: vi.fn(),
  submitPlatformLegalDocument: vi.fn(),
  decidePlatformLegalDocument: vi.fn(),
  publishPlatformLegalDocument: vi.fn(),
  archivePlatformLegalDocument: vi.fn(),
}));

vi.mock("../src/features/auth/TermsPdfViewer", () => ({
  TermsPdfViewer: ({ documentTitle }: { documentTitle: string }) => (
    <div data-testid="pdf-preview">{documentTitle}</div>
  ),
}));

const publishedTerms = {
  documentVersionId: "4af995e8-f2f6-4e31-b950-15543e6aef11",
  title: "KLOP Terms",
  registrationType: "PERSONAL" as const,
  version: "2.0",
  effectiveAtUtc: "2026-01-01T00:00:00Z",
  documentUrl: "/api/v1/public/legal/terms/file",
  contentHash: "sha256-value",
  publicationStatus: "PUBLISHED" as const,
};

function renderLegalDocumentsPage() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <LegalDocumentsPage />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("LegalDocumentsPage", () => {
  beforeEach(() => {
    vi.mocked(getCurrentTerms).mockReset();
    vi.mocked(getPlatformLegalDocumentPermissions).mockReset()
      .mockResolvedValue({ permissions: [] });
    vi.mocked(getPlatformLegalDocuments).mockReset().mockResolvedValue([]);
  });

  it("groups the same published backend version across both registration scopes", async () => {
    vi.mocked(getCurrentTerms).mockImplementation(async (registrationType) => ({
      ...publishedTerms,
      registrationType,
    }));
    renderLegalDocumentsPage();

    expect(await screen.findByText("PERSONAL, ORGANIZATION")).toBeInTheDocument();
    expect(screen.getByText("Version 2.0")).toBeInTheDocument();
    expect(screen.getByText(publishedTerms.documentVersionId)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Preview published PDF" })).toBeInTheDocument();
    expect(getCurrentTerms).toHaveBeenCalledWith("PERSONAL");
    expect(getCurrentTerms).toHaveBeenCalledWith("ORGANIZATION");

    fireEvent.click(screen.getByRole("button", { name: "Preview published PDF" }));
    expect(await screen.findByTestId("pdf-preview")).toHaveTextContent("KLOP Terms");
  });

  it("reports unavailable published Terms while allowing only a local draft preview", async () => {
    vi.mocked(getCurrentTerms).mockRejectedValue(
      new ApiRequestError("TERMS_UNAVAILABLE", "Terms are not available.", 404),
    );
    renderLegalDocumentsPage();

    expect(await screen.findAllByText("No published version")).toHaveLength(2);
    expect(screen.getByText(/No published Terms version was returned/)).toBeInTheDocument();
    expect(screen.getByText(/not shown as a registered, approved, published, or consent-eligible/))
      .toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Preview local draft PDF" }));
    expect(await screen.findByTestId("pdf-preview"))
      .toHaveTextContent("Terms & Conditions draft preview");
    expect(screen.getByText(/No consent is recorded/)).toBeInTheDocument();
    expect(screen.queryByText(publishedTerms.documentVersionId)).not.toBeInTheDocument();
  });

  it("does not mistake an API failure for missing published Terms", async () => {
    vi.mocked(getCurrentTerms)
      .mockRejectedValueOnce(new ApiRequestError("NOT_FOUND", "Route was not found.", 404))
      .mockRejectedValueOnce(new ApiRequestError("TERMS_UNAVAILABLE", "No terms.", 404));
    renderLegalDocumentsPage();

    expect(await screen.findByText("Could not load")).toBeInTheDocument();
    expect(screen.getByText(/Current Terms metadata could not be fully loaded/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Retry PERSONAL" })).toBeInTheDocument();
  });

  it("does not infer a registration scope from a mismatched Terms response", async () => {
    vi.mocked(getCurrentTerms).mockImplementation(async (registrationType) => {
      if (registrationType === "PERSONAL") {
        return { ...publishedTerms, registrationType: "ORGANIZATION" };
      }
      throw new ApiRequestError("TERMS_UNAVAILABLE", "No terms.", 404);
    });
    renderLegalDocumentsPage();

    expect(await screen.findByText("Scope mismatch")).toBeInTheDocument();
    expect(screen.getByText(/returned for a different registration scope/)).toBeInTheDocument();
    expect(screen.queryByText(publishedTerms.documentVersionId)).not.toBeInTheDocument();
  });

  it("uploads a draft with both registration scopes and the selected PDF", async () => {
    const user = userEvent.setup();
    vi.mocked(getCurrentTerms).mockRejectedValue(
      new ApiRequestError("TERMS_UNAVAILABLE", "Terms are not available.", 404),
    );
    vi.mocked(getPlatformLegalDocumentPermissions).mockResolvedValue({
      permissions: ["platform.legal_documents.read", "platform.legal_documents.draft.create"],
    });
    vi.mocked(uploadPlatformLegalDocument).mockResolvedValue({
      legalDocumentId: "e885c713-8865-44bc-9d6c-0194a9e3b4fe",
      documentTypeCode: "TERMS_AND_CONDITIONS",
      versions: [],
    });
    renderLegalDocumentsPage();

    fireEvent.click(await screen.findByRole("button", { name: "Create draft" }));
    fireEvent.change(screen.getByLabelText("Title"), { target: { value: "KLOP Terms" } });
    fireEvent.change(screen.getByLabelText("Version"), { target: { value: "1.0" } });
    fireEvent.change(screen.getByLabelText("Effective date and time"), {
      target: { value: "2026-01-01T00:00" },
    });
    const pdf = new File(["%PDF-1.7"], "terms.pdf", { type: "application/pdf" });
    await user.upload(screen.getByLabelText("PDF document"), pdf);
    const uploadButton = screen.getByRole("button", { name: "Upload draft" });
    expect(uploadButton).toBeEnabled();
    await user.click(uploadButton);

    expect(await screen.findByText("Legal document update completed.")).toBeInTheDocument();
    expect(uploadPlatformLegalDocument).toHaveBeenCalledWith(
      {
        title: "KLOP Terms",
        versionIdentifier: "1.0",
        effectiveAtUtc: expect.any(String),
        registrationTypes: ["PERSONAL", "ORGANIZATION"],
      },
      pdf,
      undefined,
    );
  });
});
