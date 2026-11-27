import { AxiosHeaders } from "axios";
import { describe, expect, it } from "vitest";
import { register, registerWithTerms } from "../src/api/auth";
import { ApiRequestError, api, requireData, toApiRequestError } from "../src/api/client";
import { getCurrentTerms } from "../src/api/legal";
import { createTenant } from "../src/api/tenants";

describe("API contract handling", () => {
  it("rejects unsuccessful or empty envelopes instead of treating them as successful", () => {
    expect(() =>
      requireData({
        success: false,
        data: null,
        error: { code: "FORBIDDEN", message: "Operation is not permitted." },
        meta: { requestId: "request-id" },
      }),
    ).toThrowError(new ApiRequestError("FORBIDDEN", "Operation is not permitted."));
  });

  it("returns a safe connection error when the API is unreachable", () => {
    const error = toApiRequestError({ name: "unexpected" });
    expect(error.message).toBe("The request could not be completed.");
  });

  it("reports Axios network failures without exposing transport details", () => {
    const error = toApiRequestError({ isAxiosError: true, code: "ERR_NETWORK" });
    expect(error.message).toBe(
      "The KLOP PLATFORM API is unavailable or unreachable. Check the connection and try again.",
    );
  });

  it.each([
    [400, "Please check the submitted information and try again."],
    [401, "Your session has expired. Sign in again."],
    [403, "You do not have permission to perform this action."],
    [404, "The requested resource was not found."],
    [409, "This request conflicts with current data. Refresh and try again."],
    [429, "Too many requests. Wait a moment and try again."],
    [500, "The KLOP PLATFORM API encountered a problem. Try again later."],
  ])("maps HTTP %s to a safe user message", (status, message) => {
    const error = toApiRequestError({
      isAxiosError: true,
      config: { url: "tenants/mine" },
      response: {
        status,
        data: { detail: "SQL login failed at internal.server.local" },
      },
    });

    expect(error.status).toBe(status);
    expect(error.message).toBe(message);
    expect(error.message).not.toContain("SQL");
  });

  it("uses a specific credential message for login rejection", () => {
    const error = toApiRequestError({
      isAxiosError: true,
      config: { url: "auth/login" },
      response: { status: 401, data: {} },
    });

    expect(error.message).toBe("Email or password is incorrect.");
  });

  it("preserves the TERMS_VERSION_OUTDATED backend code for registration recovery", () => {
    const error = toApiRequestError({
      isAxiosError: true,
      config: { url: "auth/register" },
      response: {
        status: 409,
        data: {
          error: {
            code: "TERMS_VERSION_OUTDATED",
            message: "Current Terms changed; retrieve and accept the current version.",
          },
        },
      },
    });

    expect(error.code).toBe("TERMS_VERSION_OUTDATED");
    expect(error.status).toBe(409);
  });

  it("uses the slashless tenant collection path from the backend OpenAPI document", async () => {
    const originalAdapter = api.defaults.adapter;
    let requestUrl: string | undefined;
    let correlationId: string | undefined;
    api.defaults.adapter = async (config) => {
      requestUrl = config.url;
      const requestCorrelationId = config.headers.get("X-Correlation-Id");
      correlationId = typeof requestCorrelationId === "string" ? requestCorrelationId : undefined;
      return {
        data: {
          success: true,
          data: { tenantId: 7, membershipId: 11 },
          error: null,
          meta: { requestId: "test-request" },
        },
        status: 201,
        statusText: "Created",
        headers: new AxiosHeaders(),
        config,
      };
    };

    try {
      await createTenant({
        tenantCode: "DEV-001",
        tenantTypeCode: "PERSONAL",
        displayName: "Development",
        organizationTypeId: null,
        registeredName: null,
      });
      expect(requestUrl).toBe("tenants");
      expect(correlationId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
    } finally {
      api.defaults.adapter = originalAdapter;
    }
  });

  it.each(["PERSONAL", "ORGANIZATION"] as const)(
    "posts the exact %s register payload and accepts the generic 202 envelope",
    async (registrationType) => {
      const originalAdapter = api.defaults.adapter;
      let requestUrl: string | undefined;
      let requestBody: unknown;
      api.defaults.adapter = async (config) => {
        requestUrl = config.url;
        requestBody = JSON.parse(config.data as string);
        return {
          data: {
            success: true,
            data: { message: "If accepted, verification instructions will be emailed." },
            error: null,
            meta: { requestId: "register-request" },
          },
          status: 202,
          statusText: "Accepted",
          headers: new AxiosHeaders(),
          config,
        };
      };

      const payload = {
        displayName: "Ada Lovelace",
        email: "ada@example.com",
        password: "a-valid-password",
        registrationType,
      };

      try {
        const response = await register(payload);
        expect(requestUrl).toBe("auth/register");
        expect(requestBody).toEqual(payload);
        expect(Object.keys(requestBody as object).sort()).toEqual([
          "displayName",
          "email",
          "password",
          "registrationType",
        ]);
        expect(response.message).toMatch(/If accepted/);
        expect(requestBody).not.toHaveProperty("confirmPassword");
      } finally {
        api.defaults.adapter = originalAdapter;
      }
    },
  );

  it("uses the separate Terms-required registration contract", async () => {
    const originalAdapter = api.defaults.adapter;
    let requestBody: unknown;
    api.defaults.adapter = async (config) => {
      requestBody = JSON.parse(config.data as string);
      return {
        data: {
          success: true,
          data: { message: "If accepted, verification instructions will be emailed." },
          error: null,
          meta: { requestId: "terms-register-request" },
        },
        status: 202,
        statusText: "Accepted",
        headers: new AxiosHeaders(),
        config,
      };
    };

    const payload = {
      displayName: "Ada Lovelace",
      email: "ada@example.com",
      password: "a-valid-password",
      registrationType: "PERSONAL" as const,
      termsDocumentVersionId: "02468ace-1357-4bdf-8024-68ace1357bdf",
      termsAccepted: true as const,
    };

    try {
      await registerWithTerms(payload);
      expect(requestBody).toEqual(payload);
    } finally {
      api.defaults.adapter = originalAdapter;
    }
  });

  it("loads published Terms metadata from the backend using the registration type", async () => {
    const originalAdapter = api.defaults.adapter;
    let requestUrl: string | undefined;
    let requestParams: unknown;
    let cacheControl: unknown;
    api.defaults.adapter = async (config) => {
      requestUrl = config.url;
      requestParams = config.params;
      cacheControl = config.headers.get("Cache-Control");
      return {
        data: {
          success: true,
          data: {
            documentVersionId: "02468ace-1357-4bdf-8024-68ace1357bdf",
            title: "Personal Terms",
            registrationType: "PERSONAL",
            version: "2.0",
            effectiveAtUtc: "2026-11-01T00:00:00Z",
            documentUrl: "/api/v1/public/legal/terms/02468ace-1357-4bdf-8024-68ace1357bdf/file",
            contentHash: "a".repeat(64),
            publicationStatus: "PUBLISHED",
          },
          error: null,
          meta: { requestId: "terms-request" },
        },
        status: 200,
        statusText: "OK",
        headers: new AxiosHeaders(),
        config,
      };
    };

    try {
      const terms = await getCurrentTerms("PERSONAL");
      expect(requestUrl).toBe("public/legal/terms/current");
      expect(requestParams).toEqual({ registrationType: "PERSONAL" });
      expect(cacheControl).toBe("no-cache");
      expect(terms.documentVersionId).toBe("02468ace-1357-4bdf-8024-68ace1357bdf");
    } finally {
      api.defaults.adapter = originalAdapter;
    }
  });
});
