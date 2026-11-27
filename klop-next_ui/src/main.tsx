import React from "react";
import ReactDOM from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter } from "react-router-dom";
import { App } from "./app/App";
import { brand, brandAssets } from "./app/brand";
import { AuthProvider } from "./app/AuthContext";
import { ThemeProvider } from "./app/ThemeContext";
import "./index.css";

document.title = brand.browserTitle;
const description = document.querySelector<HTMLMetaElement>('meta[name="description"]');
if (description) description.content = `${brand.displayName}.`;
const favicon = document.createElement("link");
favicon.rel = "icon";
favicon.type = brandAssets.faviconMimeType;
favicon.href = brandAssets.favicon;
document.head.append(favicon);

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: 1, staleTime: 30_000, refetchOnWindowFocus: false },
    mutations: { retry: 0 },
  },
});

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <ThemeProvider>
          <AuthProvider>
            <App />
          </AuthProvider>
        </ThemeProvider>
      </BrowserRouter>
    </QueryClientProvider>
  </React.StrictMode>,
);
