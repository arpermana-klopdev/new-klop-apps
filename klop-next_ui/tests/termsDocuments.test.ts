import { beforeEach, describe, expect, it, vi } from "vitest";
import { ApiRequestError } from "../src/api/client";
import { getCurrentTerms } from "../src/api/legal";
import {
  isAvailableTermsDocument,
  isPublishedTermsDocument,
  loadCurrentTermsDocument,
} from "../src/features/auth/termsDocuments";

vi.mock("../src/api/legal", () => ({
  getCurrentTerms: vi.fn(),
}));

describe("Terms document configuration", () => {
  beforeEach(() => {
    vi.mocked(getCurrentTerms).mockReset();
  });

  it.each(["PERSONAL", "ORGANIZATION"] as const)(
    "keeps the existing local PDF visible for %s when no published document exists",
    async (registrationType) => {
      vi.mocked(getCurrentTerms).mockRejectedValue(
        new ApiRequestError("TERMS_UNAVAILABLE", "Terms unavailable.", 404),
      );
      const document = await loadCurrentTermsDocument(registrationType);

      expect(isAvailableTermsDocument(document, registrationType)).toBe(true);
      expect(document?.documentUrl).toContain(
        "/documents/KLOP_Next_Terms_and_Conditions.pdf",
      );
      expect(document?.registrationType).toBe(registrationType);
      expect(document?.sourceFileName).toBe("KLOP_Next_Terms_and_Conditions.pdf");
      expect(document?.publicationStatus).toBe("DRAFT");
      expect(document?.version).toBe("0.1 (draft; not approved)");
      expect(document?.effectiveDate).toBeNull();
      expect(isPublishedTermsDocument(document, registrationType)).toBe(false);
    },
  );

  it.each(["PERSONAL", "ORGANIZATION"] as const)(
    "uses backend metadata and the published file URL for %s",
    async (registrationType) => {
      vi.mocked(getCurrentTerms).mockResolvedValue({
        documentVersionId: "02468ace-1357-4bdf-8024-68ace1357bdf",
        title: `${registrationType} Official Terms`,
        registrationType,
        version: "2.0",
        effectiveAtUtc: "2026-11-01T00:00:00Z",
        documentUrl: "/api/v1/public/legal/terms/02468ace-1357-4bdf-8024-68ace1357bdf/file",
        contentHash: "a".repeat(64),
        publicationStatus: "PUBLISHED",
      });

      const document = await loadCurrentTermsDocument(registrationType);

      expect(document).toMatchObject({
        documentVersionId: "02468ace-1357-4bdf-8024-68ace1357bdf",
        registrationType,
        title: `${registrationType} Official Terms`,
        version: "2.0",
        publicationStatus: "PUBLISHED",
        documentUrl:
          "http://localhost:3000/api/v1/public/legal/terms/02468ace-1357-4bdf-8024-68ace1357bdf/file",
      });
      expect(isPublishedTermsDocument(document, registrationType)).toBe(true);
      expect(getCurrentTerms).toHaveBeenCalledWith(registrationType);
    },
  );

  it("does not substitute the local draft when the Terms API is unavailable", async () => {
    vi.mocked(getCurrentTerms).mockRejectedValue(
      new ApiRequestError("REQUEST_FAILED", "Terms service unavailable.", 503),
    );

    await expect(loadCurrentTermsDocument("PERSONAL")).rejects.toThrow(
      "Terms service unavailable.",
    );
  });
});
