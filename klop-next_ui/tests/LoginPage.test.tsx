import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useLocation } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as authApi from "../src/api/auth";
import { ApiRequestError } from "../src/api/client";
import * as termsDocuments from "../src/features/auth/termsDocuments";
import { RegistrationFlowProvider } from "../src/features/auth/RegistrationFlowContext";
import { LoginPage } from "../src/features/auth/LoginPage";

const signIn = vi.fn();
const approvedTermsFixture = vi.hoisted(() => ({
  enabled: false,
  version: "TEST-ONLY-V1",
  publicationStatus: "PUBLISHED",
  pdf: false,
  failure: false,
  mismatch: false,
}));
const defaultRegistrationPolicy = {
  termsRequired: true,
  passwordMinLength: 12,
  passwordMaxLength: 128 as const,
  allowedRegistrationTypes: ["PERSONAL", "ORGANIZATION"] as const,
};

vi.mock("../src/app/AuthContext", () => ({
  useAuth: () => ({ signIn }),
}));

vi.mock("../src/api/auth", () => ({
  getRegistrationPolicy: vi.fn(),
  register: vi.fn(),
  registerWithTerms: vi.fn(),
  resendVerification: vi.fn(),
  verifyEmail: vi.fn(),
}));

vi.mock("../src/features/auth/TermsPdfViewer", () => ({
  TermsPdfViewer: ({
    documentTitle,
    onDocumentLoad,
  }: {
    documentTitle: string;
    onDocumentLoad: () => void;
  }) => (
    <div role="region" aria-label={`${documentTitle} PDF pages`}>
      <button type="button" onClick={onDocumentLoad}>
        Simulate all PDF pages rendered
      </button>
    </div>
  ),
}));

vi.mock("../src/features/auth/termsDocuments", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../src/features/auth/termsDocuments")>();
  return {
    ...actual,
    loadCurrentTermsDocument: vi.fn(async (registrationType: "PERSONAL" | "ORGANIZATION") => {
      if (approvedTermsFixture.failure) throw new Error("Test-only document load failure.");
      if (!approvedTermsFixture.enabled) return null;
      return {
        documentVersionId: `TEST-ONLY-${registrationType}`,
        documentType: "TERMS_AND_CONDITIONS",
        registrationType: approvedTermsFixture.mismatch
          ? registrationType === "PERSONAL"
            ? "ORGANIZATION"
            : "PERSONAL"
          : registrationType,
        title: `${registrationType} Terms & Conditions`,
        version: approvedTermsFixture.version,
        effectiveDate: "2026-01-01",
        publicationStatus: approvedTermsFixture.publicationStatus,
        ...(approvedTermsFixture.pdf
          ? { documentUrl: "/docs/test-only-terms.pdf" }
          : { documentContent: "Test-only document content; not an approved legal policy." }),
      };
    }),
  };
});

function renderLogin(path = "/login") {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <CurrentLocation />
      <Routes>
        <Route element={<RegistrationFlowProvider />}>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/register" element={<LoginPage />} />
          <Route path="/verify-email" element={<LoginPage />} />
        </Route>
      </Routes>
    </MemoryRouter>,
  );
}

function CurrentLocation() {
  const location = useLocation();
  return (
    <div data-testid="current-location">
      {location.pathname}{location.search}{location.hash}
    </div>
  );
}

async function selectRegistrationType(type: "PERSONAL" | "ORGANIZATION") {
  await waitFor(() =>
    expect(screen.queryByText("Loading current registration requirements…")).not.toBeInTheDocument(),
  );
  fireEvent.click(screen.getByRole("button", { name: new RegExp(type) }));
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
}

function fillValidRegistration() {
  fireEvent.change(screen.getByLabelText("Full Name"), {
    target: { value: "Ada Lovelace" },
  });
  fireEvent.change(screen.getByLabelText("Email Address"), {
    target: { value: "ada@example.com" },
  });
  fireEvent.change(screen.getByLabelText("Password", { exact: true }), {
    target: { value: "test-password" },
  });
  fireEvent.change(screen.getByLabelText("Confirm Password"), {
    target: { value: "test-password" },
  });
}

async function acceptTerms(type: "PERSONAL" | "ORGANIZATION") {
  fireEvent.click(screen.getByRole("button", { name: `Read the ${type} Terms & Conditions` }));
  const dialog = await screen.findByRole("dialog");
  expect(dialog).toHaveAccessibleName("Terms & Conditions");
  if (!approvedTermsFixture.enabled || approvedTermsFixture.pdf || approvedTermsFixture.failure) {
    fireEvent.click(await screen.findByRole("button", { name: "Simulate all PDF pages rendered" }));
  } else {
    await screen.findByText("Test-only document content; not an approved legal policy.");
  }
  const agreement = await screen.findByRole("checkbox", {
    name: "I have read and agree to the Terms & Conditions.",
  });
  fireEvent.click(agreement);
  fireEvent.click(screen.getByRole("button", { name: "I Agree" }));
  const consentStatus = await screen.findByRole("status", { name: `${type} Terms accepted` });
  expect(consentStatus).toHaveClass("is-accepted");
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
}

describe("LoginPage", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  beforeEach(() => {
    signIn.mockReset();
    approvedTermsFixture.enabled = false;
    approvedTermsFixture.version = "TEST-ONLY-V1";
    approvedTermsFixture.publicationStatus = "PUBLISHED";
    approvedTermsFixture.pdf = false;
    approvedTermsFixture.failure = false;
    approvedTermsFixture.mismatch = false;
    vi.mocked(authApi.register).mockReset();
    vi.mocked(authApi.registerWithTerms).mockReset();
    vi.mocked(authApi.getRegistrationPolicy).mockReset().mockResolvedValue({
      ...defaultRegistrationPolicy,
      allowedRegistrationTypes: [...defaultRegistrationPolicy.allowedRegistrationTypes],
    });
    vi.mocked(authApi.resendVerification).mockReset();
    vi.mocked(authApi.verifyEmail).mockReset();
    vi.mocked(termsDocuments.loadCurrentTermsDocument).mockClear();
  });

  it("blocks malformed credentials before making an authentication request", async () => {
    renderLogin();
    fireEvent.change(screen.getByLabelText("Email address"), {
      target: { value: "not-an-email" },
    });
    fireEvent.change(screen.getByLabelText("Password"), {
      target: { value: "password" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Sign in" }));

    expect(await screen.findByText("Enter a valid email address.")).toBeInTheDocument();
    expect(signIn).not.toHaveBeenCalled();
  });

  it("keeps the existing login layout while removing provider options", () => {
    renderLogin();

    expect(screen.getByRole("heading", { name: "Sign in to KLOP Next" })).toBeInTheDocument();
    expect(screen.getByText("Access your account securely.")).toBeInTheDocument();
    expect(screen.getByText("WELCOME BACK")).toBeInTheDocument();
    expect(screen.getByText("Secure & Reliable")).toBeInTheDocument();
    expect(screen.queryByText(/continue with google/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/continue with sso/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/or continue with/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/coming soon/i)).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Create an account" })).toHaveAttribute(
      "href",
      "/register",
    );
    expect(screen.getByText("Need help signing in? Contact your administrator.")).toBeInTheDocument();
    expect(screen.getByText("Developed by PT Solusi Manufaktur Teknologi")).toBeInTheDocument();
  });

  it("allows choosing and changing the PERSONAL or ORGANIZATION registration intent", () => {
    renderLogin("/register");

    expect(screen.getByRole("heading", { name: "Create your KLOP account" })).toBeInTheDocument();
    expect(screen.getByText("How would you like to use KLOP Next?")).toBeInTheDocument();
    const personal = screen.getByRole("button", { name: /PERSONAL/ });
    const organization = screen.getByRole("button", { name: /ORGANIZATION/ });
    expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();

    fireEvent.click(personal);
    expect(personal).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(organization);
    expect(personal).toHaveAttribute("aria-pressed", "false");
    expect(organization).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(screen.getByRole("button", { name: "Continue" }));

    expect(screen.getByText("Registering as")).toHaveTextContent("ORGANIZATION");
    fireEvent.click(screen.getByRole("button", { name: "Change registration type" }));
    fireEvent.click(screen.getByRole("button", { name: /PERSONAL/ }));
    fireEvent.click(screen.getByRole("button", { name: "Continue" }));
    expect(screen.getByText("Registering as")).toHaveTextContent("PERSONAL");
  });

  it("uses contextual registration icons and places Sign in below Create account", async () => {
    const { container } = renderLogin("/register");
    await selectRegistrationType("PERSONAL");

    expect(container.querySelector(".auth-form-icon")).toBeNull();
    expect(container.querySelector(".auth-input-icon.lucide-mail")).not.toBeNull();
    expect(container.querySelectorAll(".auth-input-icon")).toHaveLength(4);

    const createAccount = screen.getByRole("button", { name: "Create account" });
    const existingAccountPrompt = screen.getByText("Already have an account?");
    expect(
      createAccount.compareDocumentPosition(existingAccountPrompt) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(screen.getByRole("link", { name: "Sign in" })).toBeInTheDocument();

    const changeRegistrationType = screen.getByRole("button", {
      name: "Change registration type",
    });
    expect(
      existingAccountPrompt.compareDocumentPosition(changeRegistrationType) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it("opens the PERSONAL Terms modal and blocks registration when the official document is unavailable", async () => {
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");

    expect(screen.queryByText("Enter your full name.")).not.toBeInTheDocument();
    expect(screen.queryByText("Enter a valid email address.")).not.toBeInTheDocument();
    expect(screen.queryByText("Enter a password.")).not.toBeInTheDocument();
    expect(screen.queryByText("Confirm your password.")).not.toBeInTheDocument();

    fillValidRegistration();

    expect(screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" })).toBeInTheDocument();
    expect(screen.getByRole("status", { name: "PERSONAL Terms not accepted" })).toBeInTheDocument();
    expect(screen.queryAllByRole("checkbox")).toHaveLength(0);
    expect(screen.getByRole("button", { name: "Create account" })).toBeDisabled();

    fireEvent.click(screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" }));
    const dialog = await screen.findByRole("dialog");
    expect(dialog).toHaveAccessibleName("Terms & Conditions");
    expect(await screen.findByRole("region", { name: /Terms.*PDF pages/ })).toBeInTheDocument();
    expect(screen.getByRole("checkbox")).toBeDisabled();
    expect(screen.getByRole("button", { name: "I Agree" })).toBeDisabled();
    fireEvent.click(screen.getByRole("button", { name: "Simulate all PDF pages rendered" }));
    expect(
      screen.getByText("I acknowledge this draft preview; it is not registration consent."),
    ).toBeInTheDocument();

    const agreement = screen.getByRole("checkbox", {
      name: "I acknowledge this draft preview; it is not registration consent.",
    });
    expect(agreement).toBeEnabled();
    fireEvent.click(agreement);
    fireEvent.click(screen.getByRole("button", { name: "I Agree" }));
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(
      screen.getByRole("status", { name: "PERSONAL Terms draft preview acknowledged" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Draft acknowledged")).toBeInTheDocument();
    expect(
      screen.getByText("Draft preview acknowledged. Published Terms are required to register."),
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create account" })).toBeDisabled();
  });

  it("opens the ORGANIZATION document without exposing PERSONAL terms", async () => {
    renderLogin("/register");
    await selectRegistrationType("ORGANIZATION");
    fireEvent.click(screen.getByRole("button", { name: "Read the ORGANIZATION Terms & Conditions" }));

    expect(await screen.findByRole("dialog")).toHaveAccessibleName("Terms & Conditions");
    expect(screen.getByText("KLOP Next – One Portal")).toBeInTheDocument();
    expect(screen.queryByText(/PERSONAL registration/)).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "I Agree" })).toBeDisabled();
  });

  it("keeps the only acceptance checkbox inside the modal and requires explicit agreement", async () => {
    approvedTermsFixture.enabled = true;
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fillValidRegistration();
    expect(screen.queryAllByRole("checkbox")).toHaveLength(0);
    fireEvent.click(screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" }));
    const checkbox = await screen.findByRole("checkbox", { name: /I have read and agree/ });
    await screen.findByText("Test-only document content; not an approved legal policy.");
    expect(checkbox).not.toBeChecked();
    expect(screen.getByRole("button", { name: "I Agree" })).toBeDisabled();
    expect(screen.getByText("Test-only document content; not an approved legal policy.")).toBeInTheDocument();

    fireEvent.click(checkbox);
    expect(screen.getByRole("button", { name: "I Agree" })).toBeEnabled();
  });

  it("keeps I Agree disabled until a PDF viewer reports successful loading", async () => {
    approvedTermsFixture.enabled = true;
    approvedTermsFixture.pdf = true;
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fireEvent.click(screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" }));
    const viewer = await screen.findByRole("region", {
      name: "PERSONAL Terms & Conditions PDF pages",
    });
    const agreement = await screen.findByRole("checkbox", { name: /I have read and agree/ });
    expect(agreement).toBeDisabled();
    expect(screen.getByRole("button", { name: "I Agree" })).toBeDisabled();

    expect(viewer).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Simulate all PDF pages rendered" }));
    fireEvent.click(agreement);
    expect(screen.getByRole("button", { name: "I Agree" })).toBeEnabled();
  });

  it("does not show a metadata error over a successfully rendered draft PDF", async () => {
    approvedTermsFixture.failure = true;
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fireEvent.click(screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" }));
    expect(await screen.findByRole("region", { name: /Terms.*PDF pages/ })).toBeInTheDocument();
    fireEvent.click(await screen.findByRole("button", { name: "Simulate all PDF pages rendered" }));
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    expect(
      screen.getByText("I acknowledge this draft preview; it is not registration consent."),
    ).toBeInTheDocument();
    expect(screen.getByRole("checkbox")).toBeEnabled();
    expect(screen.getByRole("button", { name: "I Agree" })).toBeDisabled();
  });

  it("allows explicit temporary acceptance of a draft but blocks account creation", async () => {
    approvedTermsFixture.enabled = true;
    approvedTermsFixture.publicationStatus = "DRAFT";
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fillValidRegistration();
    fireEvent.click(screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" }));
    await screen.findByText("Test-only document content; not an approved legal policy.");
    const agreement = screen.getByRole("checkbox", {
      name: "I acknowledge this draft preview; it is not registration consent.",
    });
    expect(agreement).toBeEnabled();
    expect(agreement).not.toBeChecked();
    fireEvent.click(agreement);
    expect(screen.getByRole("button", { name: "I Agree" })).toBeEnabled();
    fireEvent.click(screen.getByRole("button", { name: "I Agree" }));
    expect(screen.getByText("Draft acknowledged")).toBeInTheDocument();
    expect(screen.getByText("Draft preview acknowledged. Published Terms are required to register."))
      .toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create account" })).toBeDisabled();
  });

  it("rejects a Terms document for the wrong registration type", async () => {
    approvedTermsFixture.enabled = true;
    approvedTermsFixture.mismatch = true;
    renderLogin("/register");
    await selectRegistrationType("ORGANIZATION");
    fireEvent.click(screen.getByRole("button", { name: "Read the ORGANIZATION Terms & Conditions" }));
    await screen.findByRole("region", { name: /Terms.*PDF pages/ });

    expect(screen.getByRole("checkbox")).toBeDisabled();
    expect(screen.getByRole("button", { name: "I Agree" })).toBeDisabled();
  });

  it("does not enable account creation from Terms consent while required form fields are invalid", async () => {
    approvedTermsFixture.enabled = true;
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    await acceptTerms("PERSONAL");
    expect(screen.getByRole("status", { name: "PERSONAL Terms accepted" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create account" })).toBeDisabled();

    fillValidRegistration();
    expect(screen.getByRole("button", { name: "Create account" })).toBeEnabled();
  });

  it("resets acceptance when registration type changes", async () => {
    approvedTermsFixture.enabled = true;
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fillValidRegistration();
    await acceptTerms("PERSONAL");
    expect(screen.getByRole("status", { name: "PERSONAL Terms accepted" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Change registration type" }));
    fireEvent.click(screen.getByRole("button", { name: /ORGANIZATION/ }));
    fireEvent.click(screen.getByRole("button", { name: "Continue" }));

    expect(screen.getByRole("status", { name: "ORGANIZATION Terms not accepted" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create account" })).toBeDisabled();
    expect(screen.getByLabelText("Full Name")).toHaveValue("Ada Lovelace");
  });

  it("resets acceptance when the approved Terms version changes", async () => {
    approvedTermsFixture.enabled = true;
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fillValidRegistration();
    await acceptTerms("PERSONAL");
    expect(screen.getByRole("status", { name: "PERSONAL Terms accepted" })).toBeInTheDocument();

    approvedTermsFixture.version = "TEST-ONLY-V2";
    fireEvent.click(screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" }));
    await screen.findByRole("dialog");
    await screen.findByText("Test-only document content; not an approved legal policy.");

    expect(screen.getByRole("checkbox", { name: /I have read and agree/ })).not.toBeChecked();
    expect(screen.getByRole("button", { name: "I Agree" })).toBeDisabled();
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.getByRole("status", { name: "PERSONAL Terms not accepted" })).toBeInTheDocument();
  });

  it("keeps the accepted published version after reopening and canceling the modal", async () => {
    approvedTermsFixture.enabled = true;
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fillValidRegistration();
    await acceptTerms("PERSONAL");
    expect(screen.getByRole("button", { name: "Create account" })).toBeEnabled();

    fireEvent.click(screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" }));
    await screen.findByText("Test-only document content; not an approved legal policy.");
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));

    expect(screen.getByRole("status", { name: "PERSONAL Terms accepted" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create account" })).toBeEnabled();
  });

  it("canceling the modal does not accept Terms or clear the registration draft", async () => {
    approvedTermsFixture.enabled = true;
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fillValidRegistration();
    fireEvent.click(screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" }));
    await screen.findByRole("dialog");
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));

    expect(screen.getByRole("status", { name: "PERSONAL Terms not accepted" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create account" })).toBeDisabled();
    expect(screen.getByLabelText("Full Name")).toHaveValue("Ada Lovelace");
    expect(screen.getByLabelText("Password", { exact: true })).toHaveValue("test-password");
  });

  it("closes with Escape without accepting and restores focus to the Terms control", async () => {
    const user = userEvent.setup();
    approvedTermsFixture.enabled = true;
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    const termsButton = screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" });
    await user.click(termsButton);
    await screen.findByRole("dialog");

    await user.keyboard("{Escape}");
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(termsButton).toHaveFocus();
    expect(screen.getByRole("status", { name: "PERSONAL Terms not accepted" })).toBeInTheDocument();
  });

  it("supports keyboard selection and does not persist sensitive registration data", async () => {
    const user = userEvent.setup();
    const localStorageSet = vi.fn();
    const sessionStorageSet = vi.fn();
    vi.stubGlobal("localStorage", { length: 0, setItem: localStorageSet });
    vi.stubGlobal("sessionStorage", { length: 0, setItem: sessionStorageSet });
    renderLogin("/register");

    const personal = screen.getByRole("button", { name: /PERSONAL/ });
    await user.tab();
    expect(personal).toHaveFocus();
    await user.keyboard("{Enter}");
    expect(personal).toHaveAttribute("aria-pressed", "true");
    await user.tab();
    await user.tab();
    await user.keyboard("{Enter}");
    expect(screen.getByText("Registering as")).toHaveTextContent("PERSONAL");
    await screen.findByText("Passwords must be 12–128 characters.");
    fillValidRegistration();
    fireEvent.click(screen.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" }));
    await screen.findByRole("dialog");

    expect(localStorageSet).not.toHaveBeenCalled();
    expect(sessionStorageSet).not.toHaveBeenCalled();
    expect(localStorage.length).toBe(0);
    expect(sessionStorage.length).toBe(0);
    expect(screen.getByLabelText("Password", { exact: true })).toHaveValue("test-password");
  });

  it("validates registration identity and matching passwords before calling the API", async () => {
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");

    fireEvent.change(screen.getByLabelText("Full Name"), { target: { value: " " } });
    fireEvent.change(screen.getByLabelText("Email Address"), {
      target: { value: "not-an-email" },
    });
    fireEvent.change(screen.getByLabelText("Password", { exact: true }), {
      target: { value: "secret" },
    });
    fireEvent.change(screen.getByLabelText("Confirm Password"), {
      target: { value: "different" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Create account" }));

    expect(await screen.findByText("Enter your full name.")).toBeInTheDocument();
    expect(screen.getByText("Enter a valid email address.")).toBeInTheDocument();
    expect(screen.getByText("Passwords do not match.")).toBeInTheDocument();
    expect(authApi.register).not.toHaveBeenCalled();
  });

  it.each(["PERSONAL", "ORGANIZATION"] as const)(
    "sends the %s registration contract and treats the accepted response generically",
    async (registrationType) => {
      approvedTermsFixture.enabled = true;
      vi.mocked(authApi.registerWithTerms).mockResolvedValue({ message: "private response text" });
      renderLogin("/register");
      await selectRegistrationType(registrationType);

      fireEvent.change(screen.getByLabelText("Full Name"), {
        target: { value: "  Ada Lovelace  " },
      });
      fireEvent.change(screen.getByLabelText("Email Address"), {
        target: { value: "ada@example.com" },
      });
      fireEvent.change(screen.getByLabelText("Password", { exact: true }), {
        target: { value: "existing-password-policy" },
      });
      fireEvent.change(screen.getByLabelText("Confirm Password"), {
        target: { value: "existing-password-policy" },
      });
      expect(screen.getByRole("button", { name: "Create account" })).toBeDisabled();
      await acceptTerms(registrationType);
      expect(screen.getByRole("button", { name: "Create account" })).toBeEnabled();
      fireEvent.click(screen.getByRole("button", { name: "Create account" }));

      expect(await screen.findByRole("heading", { name: "Check your email" })).toBeInTheDocument();
      expect(authApi.registerWithTerms).toHaveBeenCalledWith({
        displayName: "Ada Lovelace",
        email: "ada@example.com",
        password: "existing-password-policy",
        registrationType,
        termsDocumentVersionId: `TEST-ONLY-${registrationType}`,
        termsAccepted: true,
      });
      expect(screen.getByText(/If your registration is accepted/)).toBeInTheDocument();
      expect(screen.queryByText("private response text")).not.toBeInTheDocument();
      expect(screen.getByText(new RegExp(`${registrationType} onboarding`))).toBeInTheDocument();
      expect(screen.getByText(/not included in the account registration request/)).toBeInTheDocument();
    },
  );

  it("submits a direct registration without Terms only when the server policy allows it", async () => {
    vi.mocked(authApi.getRegistrationPolicy).mockResolvedValue({
      termsRequired: false,
      passwordMinLength: 16,
      passwordMaxLength: 128,
      allowedRegistrationTypes: ["PERSONAL", "ORGANIZATION"],
    });
    vi.mocked(authApi.register).mockResolvedValue({ message: "accepted" });
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fillValidRegistration();

    expect(screen.queryByText("Terms & Conditions")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create account" })).toBeDisabled();
    expect(await screen.findByText("Password must be at least 16 characters.")).toBeInTheDocument();
    expect(termsDocuments.loadCurrentTermsDocument).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Password", { exact: true }), {
      target: { value: "registration-password" },
    });
    fireEvent.change(screen.getByLabelText("Confirm Password"), {
      target: { value: "registration-password" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Create account" }));

    expect(await screen.findByRole("heading", { name: "Check your email" })).toBeInTheDocument();
    expect(authApi.register).toHaveBeenCalledWith({
      displayName: "Ada Lovelace",
      email: "ada@example.com",
      password: "registration-password",
      registrationType: "PERSONAL",
    });
    expect(termsDocuments.loadCurrentTermsDocument).not.toHaveBeenCalled();
  });

  it("fails closed when the public registration policy cannot be loaded", async () => {
    vi.mocked(authApi.getRegistrationPolicy).mockRejectedValue(
      new ApiRequestError("SERVICE_UNAVAILABLE", "Registration policy is unavailable.", 503),
    );
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fillValidRegistration();

    expect(await screen.findAllByText("Registration policy is unavailable.")).toHaveLength(2);
    expect(screen.getByRole("button", { name: "Create account" })).toBeDisabled();
    fireEvent.click(screen.getByRole("button", { name: "Create account" }));
    expect(authApi.register).not.toHaveBeenCalled();
    expect(termsDocuments.loadCurrentTermsDocument).not.toHaveBeenCalled();
  });

  it("surfaces rate limits and preserves non-sensitive registration fields", async () => {
    approvedTermsFixture.enabled = true;
    vi.mocked(authApi.registerWithTerms).mockRejectedValue(
      new ApiRequestError("RATE_LIMITED", "Too many requests. Wait a moment and try again.", 429),
    );
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fireEvent.change(screen.getByLabelText("Full Name"), { target: { value: "Ada Lovelace" } });
    fireEvent.change(screen.getByLabelText("Email Address"), {
      target: { value: "ada@example.com" },
    });
    fireEvent.change(screen.getByLabelText("Password", { exact: true }), {
      target: { value: "test-password" },
    });
    fireEvent.change(screen.getByLabelText("Confirm Password"), {
      target: { value: "test-password" },
    });
    await acceptTerms("PERSONAL");
    fireEvent.click(screen.getByRole("button", { name: "Create account" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Too many requests. Wait a moment and try again.",
    );
    expect(screen.getByLabelText("Full Name")).toHaveValue("Ada Lovelace");
    expect(screen.getByLabelText("Email Address")).toHaveValue("ada@example.com");
    expect(screen.getByLabelText("Password", { exact: true })).toHaveValue("test-password");
    expect(screen.getByLabelText("Confirm Password")).toHaveValue("test-password");
  });

  it("resets acceptance and opens the updated Terms after TERMS_VERSION_OUTDATED", async () => {
    approvedTermsFixture.enabled = true;
    vi.mocked(authApi.registerWithTerms).mockImplementation(async () => {
      approvedTermsFixture.version = "TEST-ONLY-V2";
      throw new ApiRequestError(
        "TERMS_VERSION_OUTDATED",
        "Current Terms changed; retrieve and accept the current version.",
        409,
      );
    });
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fillValidRegistration();
    await acceptTerms("PERSONAL");
    expect(screen.getByText("Accepted")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Create account" }));

    expect(await screen.findByRole("dialog")).toBeInTheDocument();
    expect(await screen.findByText("Test-only document content; not an approved legal policy."))
      .toBeInTheDocument();
    expect(screen.getByRole("checkbox", { name: /I have read and agree/ })).not.toBeChecked();
    expect(screen.getByLabelText("Full Name")).toHaveValue("Ada Lovelace");
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.getByRole("status", { name: "PERSONAL Terms not accepted" })).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("prevents duplicate registration submissions while the request is pending", async () => {
    approvedTermsFixture.enabled = true;
    let resolveRegistration: (() => void) | undefined;
    vi.mocked(authApi.registerWithTerms).mockReturnValue(
      new Promise((resolve) => {
        resolveRegistration = () => resolve({ message: "generic" });
      }),
    );
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fillValidRegistration();
    await acceptTerms("PERSONAL");

    const createAccount = screen.getByRole("button", { name: "Create account" });
    fireEvent.click(createAccount);
    fireEvent.click(createAccount);

    await waitFor(() => expect(authApi.registerWithTerms).toHaveBeenCalledOnce());
    expect(authApi.registerWithTerms).toHaveBeenCalledOnce();
    expect(createAccount).toBeDisabled();
    resolveRegistration?.();
    expect(await screen.findByRole("heading", { name: "Check your email" })).toBeInTheDocument();
  });

  it("uses generic resend acceptance feedback without exposing account existence", async () => {
    approvedTermsFixture.enabled = true;
    vi.mocked(authApi.resendVerification).mockResolvedValue({ message: "private response text" });
    renderLogin("/register");
    await selectRegistrationType("PERSONAL");
    fireEvent.change(screen.getByLabelText("Full Name"), { target: { value: "Ada Lovelace" } });
    fireEvent.change(screen.getByLabelText("Email Address"), {
      target: { value: "ada@example.com" },
    });
    fireEvent.change(screen.getByLabelText("Password", { exact: true }), {
      target: { value: "test-password" },
    });
    fireEvent.change(screen.getByLabelText("Confirm Password"), {
      target: { value: "test-password" },
    });
    await acceptTerms("PERSONAL");
    fireEvent.click(screen.getByRole("button", { name: "Create account" }));
    await screen.findByRole("heading", { name: "Check your email" });
    fireEvent.click(screen.getByRole("button", { name: "Resend verification instructions" }));

    fireEvent.change(screen.getByLabelText("Email address"), {
      target: { value: "ada@example.com" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Resend instructions" }));

    expect(await screen.findByRole("status")).toHaveTextContent(
      "If an eligible account exists, verification instructions will be sent to the email address.",
    );
    expect(screen.queryByText("private response text")).not.toBeInTheDocument();
    expect(authApi.resendVerification).toHaveBeenCalledWith({ email: "ada@example.com" });
  });

  it("verifies the existing user ID and code, then returns to the sign-in form", async () => {
    vi.mocked(authApi.verifyEmail).mockResolvedValue(undefined);
    renderLogin("/verify-email");

    expect(screen.getByLabelText("Verification code")).toHaveAttribute("type", "password");
    fireEvent.change(screen.getByLabelText("User ID"), { target: { value: "42" } });
    fireEvent.change(screen.getByLabelText("Verification code"), {
      target: { value: "a".repeat(32) },
    });
    fireEvent.click(screen.getByRole("button", { name: "Verify email" }));

    expect(await screen.findByText("Email verified. You can now sign in.")).toBeInTheDocument();
    expect(authApi.verifyEmail).toHaveBeenCalledWith({
      userId: 42,
      token: "a".repeat(32),
    });
    expect(screen.getByRole("heading", { name: "Sign in to KLOP Next" })).toBeInTheDocument();
  });

  it("automatically verifies a valid link after removing its fragment from the URL", async () => {
    const token = "A".repeat(43);
    let finishVerification: (() => void) | undefined;
    vi.mocked(authApi.verifyEmail).mockReturnValue(
      new Promise((resolve) => {
        finishVerification = () => resolve(undefined);
      }),
    );
    renderLogin(`/verify-email#userId=42&token=${token}`);

    expect(await screen.findByText("Verifying your email address…")).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.getByTestId("current-location")).toHaveTextContent("/verify-email");
      expect(screen.getByTestId("current-location")).not.toHaveTextContent(token);
      expect(authApi.verifyEmail).toHaveBeenCalledWith({ userId: 42, token });
    });
    expect(authApi.verifyEmail).toHaveBeenCalledOnce();
    finishVerification?.();

    expect(await screen.findByRole("heading", { name: "Sign in to KLOP Next" })).toBeInTheDocument();
    expect(await screen.findByText("Email verified. You can now sign in.")).toBeInTheDocument();
  });

  it("rejects malformed verification links without submitting the token", async () => {
    renderLogin("/verify-email#userId=42&token=short");

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "This verification link is invalid or incomplete.",
    );
    expect(screen.getByLabelText("Verification code")).toBeInTheDocument();
    expect(authApi.verifyEmail).not.toHaveBeenCalled();
    expect(screen.getByTestId("current-location")).toHaveTextContent("/verify-email");
    expect(screen.getByTestId("current-location")).not.toHaveTextContent("short");
    expect(signIn).not.toHaveBeenCalled();
  });

  it("keeps the password masked until the visibility control is activated", () => {
    renderLogin();
    const password = screen.getByLabelText("Password", { exact: true });

    expect(password).toHaveAttribute("type", "password");
    fireEvent.click(screen.getByRole("button", { name: "Show password" }));
    expect(password).toHaveAttribute("type", "text");
    fireEvent.click(screen.getByRole("button", { name: "Hide password" }));
    expect(password).toHaveAttribute("type", "password");
  });

  it("surfaces authentication failures using the safe API message", async () => {
    signIn.mockRejectedValue(
      new ApiRequestError("INVALID_CREDENTIALS", "Email or password is incorrect.", 401),
    );
    renderLogin();
    fireEvent.change(screen.getByLabelText("Email address"), {
      target: { value: "person@example.com" },
    });
    fireEvent.change(screen.getByLabelText("Password"), {
      target: { value: "password" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Sign in" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Email or password is incorrect.",
    );
    expect(signIn).toHaveBeenCalledWith("person@example.com", "password");
  });
});
