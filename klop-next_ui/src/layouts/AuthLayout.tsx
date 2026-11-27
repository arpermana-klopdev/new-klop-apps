import { Check } from "lucide-react";
import type { ReactNode } from "react";
import { brand, brandAssets } from "../app/brand";
import ecosystemIllustration from "../../docs/klop-next-enterprise-ecosystem-animated.svg";

export function AuthLayout({
  header,
  children,
}: {
  header?: ReactNode;
  children: ReactNode;
}) {
  return (
    <main className="auth-page">
      <aside className="auth-brand" aria-label={brand.displayName}>
        <div className="auth-brand-art" aria-hidden="true">
          <span className="auth-hexagon auth-hexagon-one" />
          <span className="auth-hexagon auth-hexagon-two" />
          <span className="auth-hexagon auth-hexagon-three" />
        </div>
        <div className="auth-brand-top">
          <img
            className="auth-brand-logo"
            src={brandAssets.logo}
            alt={brand.displayName}
            width={2149}
            height={732}
          />
        </div>
        <div className="auth-brand-message">
          <p className="auth-brand-eyebrow">
            KLOP ENTERPRISE PLATFORM
          </p>
          <h1>
            One Portal.
            <br />
            <span>Seamless Experience.</span>
          </h1>
          <p className="auth-brand-description">
            A unified enterprise platform for secure access, connected workflows, and intelligent
            business operations.
          </p>
          <ul className="auth-brand-features" aria-label="Platform benefits">
            <li><Check aria-hidden="true" />Secure &amp; Reliable</li>
            <li><Check aria-hidden="true" />Integrated Workflows</li>
            <li><Check aria-hidden="true" />Role-based Access Control</li>
          </ul>
        </div>
        <img
          className="auth-brand-illustration"
          src={ecosystemIllustration}
          alt=""
          aria-hidden="true"
          width={1100}
          height={680}
        />
      </aside>

      <section className="auth-content" aria-label="Account access">
        {header && <header className="auth-topbar">{header}</header>}
        <div className="auth-main">{children}</div>
        <footer className="auth-footer">
          <span className="auth-footer-product">
            {brand.displayName} <span aria-hidden="true">|</span> Secure. Connected. Built for business.
          </span>
          <span className="auth-footer-credit">Developed by PT Solusi Manufaktur Teknologi</span>
        </footer>
      </section>
    </main>
  );
}
