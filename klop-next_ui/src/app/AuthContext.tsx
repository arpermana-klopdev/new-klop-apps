import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import * as authApi from "../api/auth";
import { ApiRequestError, setAccessToken, toApiRequestError } from "../api/client";
import type { Profile } from "../api/contracts";

type AuthStatus = "loading" | "signedOut" | "signedIn" | "error";
type AuthContextValue = {
  status: AuthStatus;
  profile: Profile | null;
  error: string | null;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  restoreSession: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>("loading");
  const [profile, setProfile] = useState<Profile | null>(null);
  const [error, setError] = useState<string | null>(null);
  const authOperation = useRef(0);

  const restoreSession = useCallback(async () => {
    const operation = ++authOperation.current;
    setStatus("loading");
    setError(null);
    try {
      const access = await authApi.refresh();
      if (operation !== authOperation.current) return;
      setAccessToken(access.accessToken);
      const current = await authApi.getProfile();
      if (operation !== authOperation.current) return;
      setProfile(current);
      setStatus("signedIn");
    } catch (requestError: unknown) {
      if (operation !== authOperation.current) return;
      setAccessToken(null);
      setProfile(null);
      const apiError = toApiRequestError(requestError);
      if (apiError.status === 401) {
        setStatus("signedOut");
        return;
      }
      setError(apiError.message);
      setStatus("error");
    }
  }, []);

  useEffect(() => {
    void restoreSession();
  }, [restoreSession]);

  useEffect(() => {
    const onUnauthorized = () => {
      setProfile(null);
      setStatus("signedOut");
      setError(null);
    };
    window.addEventListener("klop:unauthorized", onUnauthorized);
    return () => window.removeEventListener("klop:unauthorized", onUnauthorized);
  }, []);

  const signIn = useCallback(async (email: string, password: string) => {
    ++authOperation.current;
    setError(null);
    setStatus("signedOut");
    try {
      const current = await authApi.login({ email, password });
      setProfile(current);
      setStatus("signedIn");
    } catch (requestError: unknown) {
      setAccessToken(null);
      throw toApiRequestError(requestError);
    }
  }, []);

  const signOut = useCallback(async () => {
    ++authOperation.current;
    try {
      await authApi.logout();
      setProfile(null);
      setStatus("signedOut");
      setError(null);
    } catch (requestError: unknown) {
      throw toApiRequestError(requestError);
    }
  }, []);

  const value = useMemo(
    () => ({ status, profile, error, signIn, signOut, restoreSession }),
    [status, profile, error, signIn, signOut, restoreSession],
  );
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used within AuthProvider.");
  return value;
}

export function isUnauthorized(error: unknown): boolean {
  return error instanceof ApiRequestError && error.status === 401;
}
