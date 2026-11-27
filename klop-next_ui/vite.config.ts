import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import { readFileSync } from "node:fs";

const tlsKeyPath = process.env.KLOP_DEV_TLS_KEY_PATH;
const tlsCertificatePath = process.env.KLOP_DEV_TLS_CERT_PATH;

if (Boolean(tlsKeyPath) !== Boolean(tlsCertificatePath)) {
  throw new Error("Set both KLOP_DEV_TLS_KEY_PATH and KLOP_DEV_TLS_CERT_PATH to enable HTTPS.");
}

const https = tlsKeyPath && tlsCertificatePath
  ? {
      key: readFileSync(tlsKeyPath),
      cert: readFileSync(tlsCertificatePath),
    }
  : undefined;

export default defineConfig(({ command }) => ({
  plugins: [react()],
  publicDir: command === "serve" ? "public" : false,
  server: {
    host: "localhost",
    port: 5173,
    strictPort: true,
    https,
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./tests/setup.ts"],
    clearMocks: true,
    include: ["tests/**/*.test.{ts,tsx}"],
    maxWorkers: 2,
  },
}));
