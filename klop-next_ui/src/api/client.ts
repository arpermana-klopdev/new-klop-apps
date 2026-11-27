import axios, {
  type AxiosError,
  type AxiosResponse,
  type InternalAxiosRequestConfig,
} from "axios";
import type { AccessResult, ApiEnvelope, ApiErrorBody } from "./contracts";

const baseURL = import.meta.env.VITE_API_BASE_URL || "/api/v1";

let accessToken: string | null = null;
let refreshInFlight: Promise<AccessResult> | null = null;

export function setAccessToken(token: string | null): void {
  accessToken = token;
}

export function hasAccessToken(): boolean {
  return accessToken !== null;
}

const refreshClient = axios.create({
  baseURL,
  withCredentials: true,
  headers: { "Content-Type": "application/json" },
});

export const api = axios.create({
  baseURL,
  withCredentials: true,
  headers: { "Content-Type": "application/json" },
});

export function resolveApiUrl(path: string): string {
  return new URL(path, new URL(baseURL, window.location.origin)).toString();
}

function addCorrelationId(config: InternalAxiosRequestConfig): InternalAxiosRequestConfig {
  config.headers.set("X-Correlation-Id", crypto.randomUUID());
  return config;
}

refreshClient.interceptors.request.use(addCorrelationId);

api.interceptors.request.use((config) => {
  addCorrelationId(config);
  if (accessToken) config.headers.set("Authorization", `Bearer ${accessToken}`);
  return config;
});

function announceUnauthorized(): void {
  window.dispatchEvent(new Event("klop:unauthorized"));
}

async function renewAccessToken(): Promise<AccessResult> {
  if (!refreshInFlight) {
    refreshInFlight = refreshClient
      .post<ApiEnvelope<AccessResult>>("auth/refresh")
      .then(({ data }) => {
        const token = requireData(data);
        setAccessToken(token.accessToken);
        return token;
      })
      .catch((error: unknown) => {
        setAccessToken(null);
        announceUnauthorized();
        throw error;
      })
      .finally(() => {
        refreshInFlight = null;
      });
  }
  return refreshInFlight;
}

export function refreshAccessToken(): Promise<AccessResult> {
  return renewAccessToken();
}

type RetriableRequest = InternalAxiosRequestConfig & { _klopRetried?: boolean };

api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const config = error.config as RetriableRequest | undefined;
    const route = config?.url ?? "";
    const isAuthOperation = /^auth\/(login|register|refresh|verify-email|resend-verification)/.test(route);

    if (error.response?.status === 401 && config?._klopRetried && !isAuthOperation) {
      setAccessToken(null);
      announceUnauthorized();
    }

    if (
      error.response?.status !== 401 ||
      !config ||
      config._klopRetried ||
      isAuthOperation ||
      !config.headers.Authorization
    ) {
      return Promise.reject(error);
    }

    config._klopRetried = true;
    try {
      await renewAccessToken();
      return await api.request(config);
    } catch {
      return Promise.reject(error);
    }
  },
);

export function requireData<T>(envelope: ApiEnvelope<T>): T {
  if (!envelope.success || envelope.data === null) {
    throw new ApiRequestError(
      envelope.error?.code ?? "INVALID_RESPONSE",
      envelope.error?.message ?? "The API returned an incomplete response.",
    );
  }
  return envelope.data;
}

export class ApiRequestError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status?: number,
  ) {
    super(message);
    this.name = "ApiRequestError";
  }
}

export function toApiRequestError(error: unknown): ApiRequestError {
  if (error instanceof ApiRequestError) return error;
  if (axios.isAxiosError(error)) {
    const body = error.response?.data as
      | { error?: ApiErrorBody }
      | undefined;
    const status = error.response?.status;
    const isLoginRequest = /^auth\/login(?:\?|$)/.test(error.config?.url ?? "");
    return new ApiRequestError(
      body?.error?.code ?? error.code ?? "REQUEST_FAILED",
      status === 400
        ? "Please check the submitted information and try again."
        : status === 401
          ? isLoginRequest
            ? "Email or password is incorrect."
            : "Your session has expired. Sign in again."
          : status === 403
            ? "You do not have permission to perform this action."
            : status === 404
              ? "The requested resource was not found."
              : status === 409
                ? "This request conflicts with current data. Refresh and try again."
                : status === 429
                  ? "Too many requests. Wait a moment and try again."
                  : status !== undefined && status >= 500
                    ? "The KLOP PLATFORM API encountered a problem. Try again later."
                    : status !== undefined
                      ? "The request could not be completed."
                      : "The KLOP PLATFORM API is unavailable or unreachable. Check the connection and try again.",
      status,
    );
  }
  return new ApiRequestError("REQUEST_FAILED", "The request could not be completed.");
}

export function responseData<T>(response: AxiosResponse<ApiEnvelope<T>>): T {
  return requireData(response.data);
}
