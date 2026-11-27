import type { AxiosResponse } from "axios";
import { api, refreshAccessToken, responseData, setAccessToken } from "./client";
import type {
  AccessResult,
  ApiEnvelope,
  LoginRequest,
  MessageResponse,
  Profile,
  RegistrationPolicyResponse,
  RegistrationRequest,
  ResendVerificationRequest,
  TermsRequiredRegistrationRequest,
  VerifyEmailRequest,
} from "./contracts";

export async function getRegistrationPolicy(): Promise<RegistrationPolicyResponse> {
  const response = await api.get<ApiEnvelope<RegistrationPolicyResponse>>(
    "auth/registration-policy",
  );
  return responseData(response);
}

export async function login(request: LoginRequest): Promise<Profile> {
  const access = responseData(
    await api.post<ApiEnvelope<AccessResult>>("auth/login", request),
  );
  setAccessToken(access.accessToken);
  return getProfile();
}

export async function register(request: RegistrationRequest): Promise<MessageResponse> {
  const response = await api.post<ApiEnvelope<MessageResponse>>("auth/register", request);
  return responseData(response);
}

export async function registerWithTerms(
  request: TermsRequiredRegistrationRequest,
): Promise<MessageResponse> {
  const response = await api.post<ApiEnvelope<MessageResponse>>("auth/register", request);
  return responseData(response);
}

export async function resendVerification(
  request: ResendVerificationRequest,
): Promise<MessageResponse> {
  const response = await api.post<ApiEnvelope<MessageResponse>>(
    "auth/resend-verification",
    request,
  );
  return responseData(response);
}

export async function verifyEmail(request: VerifyEmailRequest): Promise<void> {
  const response = await api.post<ApiEnvelope<{ verified: boolean }>>(
    "auth/verify-email",
    request,
  );
  responseData(response);
}

export async function refresh(): Promise<AccessResult> {
  return refreshAccessToken();
}

export async function getProfile(): Promise<Profile> {
  const response = await api.get<ApiEnvelope<Profile>>("auth/me");
  return responseData(response);
}

export async function logout(): Promise<void> {
  const response: AxiosResponse<ApiEnvelope<{ loggedOut: boolean }>> =
    await api.post("auth/logout");
  responseData(response);
  setAccessToken(null);
}
