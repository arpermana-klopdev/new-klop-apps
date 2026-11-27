import { zodResolver } from "@hookform/resolvers/zod";
import {
  ArrowRight,
  Building2,
  Check,
  CheckCircle2,
  KeyRound,
  LockKeyhole,
  Mail,
  ShieldCheck,
  UserRound,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useForm } from "react-hook-form";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { z } from "zod";
import * as authApi from "../../api/auth";
import { toApiRequestError } from "../../api/client";
import type { RegistrationPolicyResponse, RegistrationRequest } from "../../api/contracts";
import { useAuth } from "../../app/AuthContext";
import { Button, Field, Notice, PasswordInput, TextInput } from "../../components/ui";
import { AuthLayout } from "../../layouts/AuthLayout";
import {
  hasCurrentDisplayedTermsDecision,
  hasCurrentPublishedTermsAcceptance,
  useRegistrationFlow,
} from "./RegistrationFlowContext";
import {
  isPublishedTermsDocument,
  loadCurrentTermsDocument,
  type PublishedTermsDocument,
  type RegistrationType,
  type TermsDocument,
} from "./termsDocuments";
import { TermsModal } from "./TermsModal";
import "./login.css";

const loginSchema = z.object({
  email: z.email("Enter a valid email address."),
  password: z.string().min(1, "Enter your password."),
});
const registerFieldsSchema = z.object({
  email: z.email("Enter a valid email address."),
  displayName: z.string().trim().min(1, "Enter your full name.").max(150),
  password: z.string(),
  confirmPassword: z.string().min(1, "Confirm your password."),
});
function registerSchemaForPolicy(policy: RegistrationPolicyResponse) {
  return registerFieldsSchema
    .extend({
      password: z.string()
        .min(policy.passwordMinLength, `Password must be at least ${policy.passwordMinLength} characters.`)
        .max(policy.passwordMaxLength, `Password must be no more than ${policy.passwordMaxLength} characters.`),
    })
    .refine((values) => values.password === values.confirmPassword, {
      path: ["confirmPassword"],
      message: "Passwords do not match.",
    });
}
const pendingRegisterSchema = registerFieldsSchema.refine(
  (values) => values.password === values.confirmPassword,
  { path: ["confirmPassword"], message: "Passwords do not match." },
);
const resendSchema = z.object({ email: z.email("Enter a valid email address.") });
const verifySchema = z.object({
  userId: z.coerce.number().int().positive("Enter the user ID from the verification email."),
  token: z.string().min(32, "The verification code must be at least 32 characters."),
});

type LoginValues = z.infer<typeof loginSchema>;
type RegisterValues = z.infer<typeof registerFieldsSchema>;
type ResendValues = z.infer<typeof resendSchema>;
type VerifyValues = z.infer<typeof verifySchema>;
type AuthMode = "login" | "type" | "register" | "accepted" | "verify" | "resend";

function modeForPath(
  pathname: string,
  registrationType: RegistrationType | null,
): AuthMode {
  if (pathname === "/register") return registrationType ? "register" : "type";
  if (pathname === "/verify-email") return "verify";
  return "login";
}

export function LoginPage() {
  const { signIn, error: sessionError, restoreSession } = useAuth();
  const {
    registrationType,
    setRegistrationType,
    clearSensitiveDraft,
  } = useRegistrationFlow();
  const location = useLocation();
  const navigate = useNavigate();
  const [mode, setMode] = useState<AuthMode>(() =>
    modeForPath(location.pathname, registrationType),
  );
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [registrationPolicy, setRegistrationPolicy] =
    useState<RegistrationPolicyResponse | null>(null);
  const [registrationPolicyLoading, setRegistrationPolicyLoading] = useState(true);
  const [registrationPolicyError, setRegistrationPolicyError] = useState<string | null>(null);
  const [verifyingEmailLink, setVerifyingEmailLink] = useState(false);
  const previousPath = useRef(location.pathname);
  const verificationAttempted = useRef(false);

  useEffect(() => {
    if (previousPath.current === location.pathname) return;
    previousPath.current = location.pathname;
    setMode(modeForPath(location.pathname, registrationType));
    setMessage(null);
    setError(null);
  }, [location.pathname, registrationType]);

  const loadRegistrationPolicy = useCallback(async () => {
    setRegistrationPolicyLoading(true);
    setRegistrationPolicyError(null);
    try {
      setRegistrationPolicy(await authApi.getRegistrationPolicy());
    } catch (requestError: unknown) {
      setRegistrationPolicy(null);
      setRegistrationPolicyError(toApiRequestError(requestError).message);
    } finally {
      setRegistrationPolicyLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadRegistrationPolicy();
  }, [loadRegistrationPolicy]);

  useEffect(() => {
    const navigationState = location.state as { emailVerified?: boolean } | null;
    if (location.pathname !== "/login" || !navigationState?.emailVerified) return;
    setMessage("Email verified. You can now sign in.");
    navigate("/login", { replace: true, state: null });
  }, [location.pathname, location.state, navigate]);

  useEffect(() => {
    if (
      location.pathname !== "/verify-email" ||
      !location.hash ||
      verificationAttempted.current
    ) return;

    verificationAttempted.current = true;
    const fragment = new URLSearchParams(location.hash.slice(1));
    const userIds = fragment.getAll("userId");
    const tokens = fragment.getAll("token");
    const userId = Number(userIds[0]);
    const token = tokens[0] ?? "";
    const validLink =
      fragment.size === 2 &&
      userIds.length === 1 &&
      tokens.length === 1 &&
      Number.isSafeInteger(userId) &&
      userId > 0 &&
      /^[A-Za-z0-9_-]{43}$/.test(token);

    navigate(
      { pathname: location.pathname, search: location.search, hash: "" },
      { replace: true, state: location.state },
    );
    setMode("verify");
    if (!validLink) {
      setError("This verification link is invalid or incomplete. Request a new email.");
      return;
    }

    setMessage(null);
    setError(null);
    setVerifyingEmailLink(true);
    void authApi.verifyEmail({ userId, token })
      .then(() => {
        navigate("/login", { replace: true, state: { emailVerified: true } });
      })
      .catch((requestError: unknown) => {
        setVerifyingEmailLink(false);
        setError(toApiRequestError(requestError).message);
      });
  }, [
    location.hash,
    location.pathname,
    location.search,
    location.state,
    navigate,
  ]);

  function resetFeedback() {
    setMessage(null);
    setError(null);
  }

  async function submitLogin(values: LoginValues) {
    resetFeedback();
    try {
      await signIn(values.email, values.password);
    } catch (requestError: unknown) {
      setError(toApiRequestError(requestError).message);
    }
  }

  async function submitRegister(
    values: RegisterValues,
    policy: RegistrationPolicyResponse,
    document: PublishedTermsDocument | null,
  ) {
    resetFeedback();
    if (!registrationType) {
      setError("Choose a registration type before continuing.");
      return;
    }
    try {
      const request: RegistrationRequest = {
        email: values.email,
        displayName: values.displayName.trim(),
        password: values.password,
        registrationType,
      };
      if (policy.termsRequired && document) {
        await authApi.registerWithTerms({
          ...request,
          termsDocumentVersionId: document.documentVersionId,
          termsAccepted: true,
        });
      } else {
        await authApi.register(request);
      }
      clearSensitiveDraft();
      setMode("accepted");
    } catch (requestError: unknown) {
      const apiError = toApiRequestError(requestError);
      if (apiError.code === "TERMS_VERSION_OUTDATED") throw apiError;
      setError(apiError.message);
    }
  }

  async function submitResend(values: ResendValues) {
    resetFeedback();
    try {
      await authApi.resendVerification(values);
      setMessage(
        "If an eligible account exists, verification instructions will be sent to the email address.",
      );
    } catch (requestError: unknown) {
      setError(toApiRequestError(requestError).message);
    }
  }

  async function submitVerify(values: VerifyValues) {
    resetFeedback();
    try {
      await authApi.verifyEmail({ userId: values.userId, token: values.token });
      navigate("/login", { replace: true, state: { emailVerified: true } });
    } catch (requestError: unknown) {
      setError(toApiRequestError(requestError).message);
    }
  }

  const title =
    mode === "login"
      ? "Sign in to KLOP Next"
      : mode === "type"
        ? "Create your KLOP account"
        : mode === "register"
          ? "Create your account"
          : mode === "accepted"
            ? "Check your email"
            : mode === "verify"
              ? "Verify your email"
              : "Resend verification";

  return (
    <AuthLayout
      header={
        mode !== "login" && mode !== "type" && mode !== "register" ? (
          <p>
            Already have an account?{" "}
            <Link to="/login">Sign in</Link>
          </p>
        ) : undefined
      }
    >
      <div className="auth-form-heading">
        {mode === "login" ? (
          <p className="auth-form-eyebrow">WELCOME BACK</p>
        ) : mode !== "register" ? (
          <div className="auth-form-icon" aria-hidden="true">
            {mode === "type" ? (
              <UserRound />
            ) : mode === "accepted" ? (
              <Mail />
            ) : mode === "verify" ? (
              <ShieldCheck />
            ) : (
              <KeyRound />
            )}
          </div>
        ) : null}
        <h2 id="auth-heading">{title}</h2>
        <p>
          {mode === "login"
            ? "Access your account securely."
            : mode === "type"
              ? "How would you like to use KLOP Next?"
            : mode === "register"
              ? "Create a secure account to continue."
              : mode === "accepted"
                ? "Email verification is required before you continue to onboarding."
                : mode === "verify"
                  ? "Use the user ID and one-time code from your verification email."
                  : "If an eligible account exists, verification instructions will be sent to the email address."}
        </p>
      </div>
      <div className="auth-form-stack" aria-labelledby="auth-heading">
        {sessionError && (
          <Notice>
            <p>{sessionError}</p>
            <button
              type="button"
              className="mt-2 font-semibold underline underline-offset-2"
              onClick={() => void restoreSession()}
            >
              Retry secure session check
            </button>
          </Notice>
        )}
        {error && <Notice>{error}</Notice>}
        {message && <Notice kind="success">{message}</Notice>}
        {mode === "login" && <LoginForm onSubmit={submitLogin} />}
        {mode === "login" && (
          <div className="auth-login-footer">
            <p>Don&apos;t have a KLOP account?</p>
            <Link to="/register" className="auth-register-link">
              Create an account <ArrowRight aria-hidden="true" />
            </Link>
            <p className="auth-signin-help">
              Need help signing in? Contact your administrator.
            </p>
          </div>
        )}
        {mode === "type" && (
          <RegistrationTypeSelection
            selectedType={registrationType}
            onSelect={setRegistrationType}
            registrationPolicy={registrationPolicy}
            policyLoading={registrationPolicyLoading}
            policyError={registrationPolicyError}
            onRetry={() => void loadRegistrationPolicy()}
            onContinue={() => {
              resetFeedback();
              setMode("register");
            }}
          />
        )}
        {mode === "register" && registrationType && (
          <RegisterForm
            registrationType={registrationType}
            registrationPolicy={registrationPolicy}
            policyLoading={registrationPolicyLoading}
            policyError={registrationPolicyError}
            onRetry={() => void loadRegistrationPolicy()}
            onSubmit={submitRegister}
          />
        )}
        {mode === "accepted" && (
          <RegistrationAccepted
            registrationType={registrationType}
            onResend={() => {
              resetFeedback();
              setMode("resend");
            }}
            onVerify={() => {
              resetFeedback();
              setMode("verify");
            }}
          />
        )}
        {mode === "resend" && <ResendForm onSubmit={submitResend} />}
        {mode === "verify" && (
          <VerifyForm onSubmit={submitVerify} linkVerifying={verifyingEmailLink} />
        )}
      </div>
      {mode === "register" && (
        <div className="auth-inline-footer auth-register-footer">
          <p className="auth-register-signin">
            Already have an account? <Link to="/login">Sign in</Link>
          </p>
          <button
            type="button"
            className="auth-mode-link"
            onClick={() => {
              resetFeedback();
              setMode("type");
            }}
          >
            Change registration type
          </button>
        </div>
      )}
      {mode === "verify" && (
        <div className="auth-inline-footer">
          <button
            type="button"
            className="auth-mode-link"
            onClick={() => {
              resetFeedback();
              setMode("resend");
            }}
          >
            Need another code?
          </button>
          <Link to="/login" className="auth-mode-link">Back to sign in</Link>
        </div>
      )}
      {mode === "resend" && (
        <div className="auth-inline-footer">
          <button
            type="button"
            className="auth-mode-link"
            onClick={() => {
              resetFeedback();
              setMode("verify");
            }}
          >
            Have a verification code?
          </button>
          <Link to="/login" className="auth-mode-link">Back to sign in</Link>
        </div>
      )}
      {(mode === "type" || mode === "accepted") && (
        <div className="auth-inline-footer">
          <Link to="/login" className="auth-mode-link">Back to sign in</Link>
        </div>
      )}
    </AuthLayout>
  );
}

function RegistrationTypeSelection({
  selectedType,
  onSelect,
  onContinue,
  registrationPolicy,
  policyLoading,
  policyError,
  onRetry,
}: {
  selectedType: RegistrationType | null;
  onSelect: (type: RegistrationType) => void;
  onContinue: () => void;
  registrationPolicy: RegistrationPolicyResponse | null;
  policyLoading: boolean;
  policyError: string | null;
  onRetry: () => void;
}) {
  const isAllowed = (type: RegistrationType) =>
    !registrationPolicy || registrationPolicy.allowedRegistrationTypes.includes(type);

  return (
    <div className="auth-form-stack">
      {policyLoading && (
        <p role="status">Loading current registration requirements…</p>
      )}
      {policyError && (
        <Notice>
          <p>{policyError}</p>
          <button type="button" className="mt-2 font-semibold underline" onClick={onRetry}>
            Retry loading registration requirements
          </button>
        </Notice>
      )}
      <div className="auth-registration-types" role="group" aria-label="Registration type">
        <button
          type="button"
          className="auth-registration-type-card"
          aria-pressed={selectedType === "PERSONAL"}
          disabled={!isAllowed("PERSONAL")}
          onClick={() => onSelect("PERSONAL")}
        >
          <UserRound aria-hidden="true" />
          <span>
            <strong>PERSONAL</strong>
            <small>For individuals who want to use KLOP Next personally.</small>
          </span>
          {selectedType === "PERSONAL" && <Check className="auth-registration-selected" aria-hidden="true" />}
        </button>
        <button
          type="button"
          className="auth-registration-type-card"
          aria-pressed={selectedType === "ORGANIZATION"}
          disabled={!isAllowed("ORGANIZATION")}
          onClick={() => onSelect("ORGANIZATION")}
        >
          <Building2 aria-hidden="true" />
          <span>
            <strong>ORGANIZATION</strong>
            <small>For companies and organizations using KLOP Next.</small>
          </span>
          {selectedType === "ORGANIZATION" && <Check className="auth-registration-selected" aria-hidden="true" />}
        </button>
      </div>
      <p className="auth-accepted-note">
        This choice only guides the next onboarding step. It is not saved by registration, does not grant access, and does not create a Tenant.
      </p>
      <Button
        type="button"
        className="auth-submit w-full"
        disabled={!selectedType || !isAllowed(selectedType)}
        onClick={onContinue}
      >
        Continue <ArrowRight aria-hidden="true" className="size-4" />
      </Button>
    </div>
  );
}

function RegistrationAccepted({
  registrationType,
  onResend,
  onVerify,
}: {
  registrationType: RegistrationType | null;
  onResend: () => void;
  onVerify: () => void;
}) {
  return (
    <div className="auth-form-stack">
      <Notice kind="info">
        If your registration is accepted, verification instructions will be sent to your email address.
      </Notice>
      <p className="auth-accepted-note">
        Your account is not signed in, no Tenant has been created, and email verification is required before onboarding.
      </p>
      {registrationType && <OnboardingPreview registrationType={registrationType} />}
      <div className="auth-accepted-actions">
        <button type="button" className="auth-mode-link" onClick={onResend}>
          Resend verification instructions
        </button>
        <button type="button" className="auth-mode-link" onClick={onVerify}>
          I have a verification code
        </button>
      </div>
    </div>
  );
}

function OnboardingPreview({ registrationType }: { registrationType: RegistrationType }) {
  const steps =
    registrationType === "PERSONAL"
      ? [
          "Personal identity and contact information",
          "Address and any additional verification requirements",
          "Review before a future PERSONAL Tenant can be created",
        ]
      : [
          "Registered organization name, country, contact, and address",
          "Organization Type and document requirements from master data",
          "Owner details and review before a future ORGANIZATION Tenant can be created",
        ];

  return (
    <section className="auth-onboarding-preview" aria-label="Future onboarding preview">
      <p className="auth-onboarding-eyebrow">FUTURE ONBOARDING PREVIEW — NOT SAVED</p>
      <h3>{registrationType} onboarding</h3>
      <ul>
        {steps.map((step) => <li key={step}>{step}</li>)}
      </ul>
      <p>
        Your selection is temporary navigation state and is not included in the account registration request.
      </p>
    </section>
  );
}

function LoginForm({ onSubmit }: { onSubmit: (values: LoginValues) => Promise<void> }) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<LoginValues>({
    resolver: zodResolver(loginSchema),
  });
  return (
    <form className="auth-form-stack" onSubmit={handleSubmit(onSubmit)} noValidate>
      <Field label="Email address" htmlFor="login-email" error={errors.email?.message}>
        <div className="auth-input-wrap">
          <Mail className="auth-input-icon" aria-hidden="true" />
          <TextInput
            id="login-email"
            type="email"
            autoComplete="email"
            placeholder="name@company.com"
            aria-invalid={Boolean(errors.email)}
            aria-describedby={errors.email ? "login-email-error" : undefined}
            {...register("email")}
          />
        </div>
      </Field>
      <Field label="Password" htmlFor="login-password" error={errors.password?.message}>
        <div className="auth-input-wrap">
          <LockKeyhole className="auth-input-icon" aria-hidden="true" />
          <PasswordInput
            id="login-password"
            autoComplete="current-password"
            placeholder="Enter your password"
            aria-invalid={Boolean(errors.password)}
            aria-describedby={errors.password ? "login-password-error" : undefined}
            {...register("password")}
          />
        </div>
      </Field>
      <Button type="submit" className="auth-submit w-full" disabled={isSubmitting}>
        {isSubmitting ? "Signing in…" : "Sign in"}
        {!isSubmitting && <ArrowRight aria-hidden="true" className="size-4" />}
      </Button>
    </form>
  );
}

function RegisterForm({
  registrationType,
  registrationPolicy,
  policyLoading,
  policyError,
  onRetry,
  onSubmit,
}: {
  registrationType: RegistrationType;
  registrationPolicy: RegistrationPolicyResponse | null;
  policyLoading: boolean;
  policyError: string | null;
  onRetry: () => void;
  onSubmit: (
    values: RegisterValues,
    policy: RegistrationPolicyResponse,
    document: PublishedTermsDocument | null,
  ) => Promise<void>;
}) {
  const {
    registrationDraft,
    setRegistrationDraft,
    termsAcceptance,
    resetTermsAcceptance,
  } = useRegistrationFlow();
  const [termsDialogOpen, setTermsDialogOpen] = useState(false);
  const [termsDocument, setTermsDocument] = useState<TermsDocument | null>(null);
  const [termsFeedback, setTermsFeedback] = useState<string | null>(null);
  const termsLinkRef = useRef<HTMLButtonElement>(null);
  const submitLockRef = useRef(false);
  const activeSchema = useMemo(
    () => registrationPolicy
      ? registerSchemaForPolicy(registrationPolicy)
      : pendingRegisterSchema,
    [registrationPolicy],
  );
  const hasTermsDecision = hasCurrentDisplayedTermsDecision(
    registrationType,
    termsDocument,
    termsAcceptance,
  );
  const termsAccepted = hasCurrentPublishedTermsAcceptance(
    registrationType,
    termsDocument,
    termsAcceptance,
  );
  const draftAcknowledged =
    hasTermsDecision && termsAcceptance.decision === "DRAFT_ACKNOWLEDGED";
  const canRegisterWithPolicy =
    registrationPolicy !== null &&
    registrationPolicy.allowedRegistrationTypes.includes(registrationType);
  const canRegisterWithTerms =
    canRegisterWithPolicy &&
    (!registrationPolicy?.termsRequired || termsAccepted);
  const handleTermsDocumentChange = useCallback((document: TermsDocument | null) => {
    setTermsDocument(document);
    setTermsFeedback(null);
  }, []);
  const {
    register,
    handleSubmit,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<RegisterValues>({
    resolver: zodResolver(activeSchema),
    mode: "onChange",
    defaultValues: registrationDraft,
  });

  useEffect(() => {
    if (!registrationPolicy || registrationPolicy.termsRequired) return;
    setTermsDocument(null);
    setTermsFeedback(null);
    resetTermsAcceptance();
  }, [registrationPolicy, resetTermsAcceptance]);

  useEffect(() => {
    const subscription = watch((values) => {
      setRegistrationDraft({
        displayName: values.displayName ?? "",
        email: values.email ?? "",
        password: values.password ?? "",
        confirmPassword: values.confirmPassword ?? "",
      });
    });
    return () => subscription.unsubscribe();
  }, [setRegistrationDraft, watch]);

  const isRegistrationValid = activeSchema.safeParse(watch()).success;
  const readinessMessages: string[] = [];
  if (policyLoading) {
    readinessMessages.push("Loading current registration requirements.");
  } else if (policyError) {
    readinessMessages.push(policyError);
  } else if (!registrationPolicy) {
    readinessMessages.push("Registration requirements are unavailable. Retry before continuing.");
  } else if (!canRegisterWithPolicy) {
    readinessMessages.push("This registration type is currently unavailable.");
  }
  if (!isRegistrationValid) {
    readinessMessages.push("Complete the required fields with valid values.");
  }
  if (registrationPolicy?.termsRequired && !termsAccepted) {
    readinessMessages.push(
      termsFeedback ??
        (!termsDocument || isPublishedTermsDocument(termsDocument, registrationType)
          ? "Review and accept the current published Terms to continue."
          : draftAcknowledged
            ? "Draft preview acknowledged. Published Terms are required to register."
            : "Published Terms unavailable; registration is blocked."),
    );
  }
  const readinessMessage = readinessMessages.join(" ");

  const submitValidForm = handleSubmit(async (values) => {
    if (submitLockRef.current) return;
    submitLockRef.current = true;
    try {
      setTermsFeedback(null);
      if (!registrationPolicy || !canRegisterWithPolicy) return;
      if (!registrationPolicy.termsRequired) {
        await onSubmit(values, registrationPolicy, null);
        return;
      }

      let currentDocument: TermsDocument | null;
      try {
        currentDocument = await loadCurrentTermsDocument(registrationType);
      } catch {
        setTermsDocument(null);
        resetTermsAcceptance();
        setTermsFeedback("Current Terms could not be verified. Registration is blocked.");
        return;
      }

      if (!isPublishedTermsDocument(currentDocument, registrationType)) {
        setTermsDocument(currentDocument);
        if (!hasCurrentDisplayedTermsDecision(registrationType, currentDocument, termsAcceptance)) {
          resetTermsAcceptance();
        }
        if (!currentDocument) {
          setTermsFeedback("Current published Terms are unavailable. Registration is blocked.");
        }
        return;
      }

      setTermsDocument(currentDocument);
      if (!hasCurrentPublishedTermsAcceptance(registrationType, currentDocument, termsAcceptance)) {
        resetTermsAcceptance();
        setTermsDialogOpen(true);
        return;
      }

      try {
        await onSubmit(values, registrationPolicy, currentDocument);
      } catch (requestError: unknown) {
        const apiError = toApiRequestError(requestError);
        if (apiError.code !== "TERMS_VERSION_OUTDATED") throw apiError;
        resetTermsAcceptance();
        setTermsFeedback(null);
        setTermsDialogOpen(true);
      }
    } finally {
      submitLockRef.current = false;
    }
  });

  return (
    <form className="auth-form-stack" onSubmit={submitValidForm} noValidate>
      {policyError && (
        <Notice>
          <p>{policyError}</p>
          <button type="button" className="mt-2 font-semibold underline" onClick={onRetry}>
            Retry loading registration requirements
          </button>
        </Notice>
      )}
      <p className="auth-registration-intent">
        Registering as <strong>{registrationType}</strong>
      </p>
      {registrationPolicy && (
        <p className="auth-accepted-note">
          Passwords must be {registrationPolicy.passwordMinLength}–{registrationPolicy.passwordMaxLength} characters.
        </p>
      )}
      <Field label="Full Name" htmlFor="register-name" error={errors.displayName?.message}>
        <div className="auth-input-wrap">
          <UserRound className="auth-input-icon" aria-hidden="true" />
          <TextInput
            id="register-name"
            autoComplete="name"
            aria-invalid={Boolean(errors.displayName)}
            aria-describedby={errors.displayName ? "register-name-error" : undefined}
            {...register("displayName")}
          />
        </div>
      </Field>
      <Field label="Email Address" htmlFor="register-email" error={errors.email?.message}>
        <div className="auth-input-wrap">
          <Mail className="auth-input-icon" aria-hidden="true" />
          <TextInput
            id="register-email"
            type="email"
            autoComplete="email"
            aria-invalid={Boolean(errors.email)}
            aria-describedby={errors.email ? "register-email-error" : undefined}
            {...register("email")}
          />
        </div>
      </Field>
      <Field label="Password" htmlFor="register-password" error={errors.password?.message}>
        <div className="auth-input-wrap">
          <LockKeyhole className="auth-input-icon" aria-hidden="true" />
          <PasswordInput
            id="register-password"
            autoComplete="new-password"
            aria-invalid={Boolean(errors.password)}
            aria-describedby={errors.password ? "register-password-error" : undefined}
            {...register("password")}
          />
        </div>
      </Field>
      <Field
        label="Confirm Password"
        htmlFor="register-confirm-password"
        error={errors.confirmPassword?.message}
      >
        <div className="auth-input-wrap">
          <LockKeyhole className="auth-input-icon" aria-hidden="true" />
          <PasswordInput
            id="register-confirm-password"
            autoComplete="new-password"
            aria-invalid={Boolean(errors.confirmPassword)}
            aria-describedby={
              errors.confirmPassword ? "register-confirm-password-error" : undefined
            }
            {...register("confirmPassword")}
          />
        </div>
      </Field>
      {registrationPolicy?.termsRequired && (
      <section className="auth-terms-section" aria-labelledby="registration-terms-heading">
        <h3 id="registration-terms-heading">Terms &amp; Conditions</h3>
        <div className="auth-terms-link-row">
          <button
            ref={termsLinkRef}
            type="button"
            className="auth-terms-link"
            onClick={() => {
              setTermsFeedback(null);
              setTermsDialogOpen(true);
            }}
          >
            Read the {registrationType} Terms &amp; Conditions
          </button>
          <span
            id="registration-terms-status"
            className={`auth-terms-status-icon${termsAccepted ? " is-accepted" : ""}${
              draftAcknowledged ? " is-draft-acknowledged" : ""
            }`}
            role="status"
            aria-label={`${registrationType} Terms ${
              termsAccepted ? "accepted" : draftAcknowledged ? "draft preview acknowledged" : "not accepted"
            }`}
            title={
              termsAccepted
                ? "Terms accepted"
                : draftAcknowledged
                  ? "Draft preview acknowledged; this is not registration consent"
                  : "Terms not accepted"
            }
          >
            <CheckCircle2 aria-hidden="true" />
            <span>
              {termsAccepted ? "Accepted" : draftAcknowledged ? "Draft acknowledged" : "Not accepted"}
            </span>
          </span>
        </div>
      </section>
      )}
      <Button
        type="submit"
        className="auth-submit w-full"
        disabled={
          !registrationPolicy ||
          !isRegistrationValid ||
          !canRegisterWithTerms ||
          isSubmitting
        }
      >
        {isSubmitting ? "Creating account…" : "Create account"}
      </Button>
      {readinessMessage && (
        <p
          className="auth-terms-registration-blocker"
          role={termsFeedback ? "alert" : "status"}
        >
          {readinessMessage}
        </p>
      )}
      {registrationPolicy?.termsRequired && (
        <TermsModal
          open={termsDialogOpen}
          onOpenChange={setTermsDialogOpen}
          registrationType={registrationType}
          triggerRef={termsLinkRef}
          onDocumentChange={handleTermsDocumentChange}
        />
      )}
    </form>
  );
}

function ResendForm({ onSubmit }: { onSubmit: (values: ResendValues) => Promise<void> }) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<ResendValues>({
    resolver: zodResolver(resendSchema),
  });
  return (
    <form className="auth-form-stack" onSubmit={handleSubmit(onSubmit)} noValidate>
      <Field label="Email address" htmlFor="resend-email" error={errors.email?.message}>
        <TextInput
          id="resend-email"
          type="email"
          autoComplete="email"
          aria-invalid={Boolean(errors.email)}
          aria-describedby={errors.email ? "resend-email-error" : undefined}
          {...register("email")}
        />
      </Field>
      <Button type="submit" className="auth-submit w-full" disabled={isSubmitting}>
        {isSubmitting ? "Submitting…" : "Resend instructions"}
      </Button>
    </form>
  );
}

function VerifyForm({
  onSubmit,
  linkVerifying,
}: {
  onSubmit: (values: VerifyValues) => Promise<void>;
  linkVerifying: boolean;
}) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<z.input<typeof verifySchema>, unknown, VerifyValues>({
    resolver: zodResolver(verifySchema),
  });
  if (linkVerifying) {
    return (
      <div className="auth-form-stack">
        <Notice kind="info">Verifying your email address…</Notice>
      </div>
    );
  }
  return (
    <form className="auth-form-stack" onSubmit={handleSubmit(onSubmit)} noValidate>
      <Field label="User ID" htmlFor="verify-user-id" error={errors.userId?.message}>
        <TextInput
          id="verify-user-id"
          type="number"
          min="1"
          aria-invalid={Boolean(errors.userId)}
          aria-describedby={errors.userId ? "verify-user-id-error" : undefined}
          {...register("userId")}
        />
      </Field>
      <Field label="Verification code" htmlFor="verify-token" error={errors.token?.message}>
        <TextInput
          id="verify-token"
          type="password"
          autoComplete="one-time-code"
          aria-invalid={Boolean(errors.token)}
          aria-describedby={errors.token ? "verify-token-error" : undefined}
          {...register("token")}
        />
      </Field>
      <Button type="submit" className="auth-submit w-full" disabled={isSubmitting}>
        {isSubmitting ? "Verifying…" : "Verify email"}
      </Button>
    </form>
  );
}
