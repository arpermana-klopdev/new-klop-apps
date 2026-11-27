import { brand, brandAssets } from "../app/brand";

export function AppLogo({
  size = "standard",
  className = "",
}: {
  size?: "standard" | "compact";
  className?: string;
}) {
  return (
    <img
      className={`app-logo ${size === "compact" ? "app-logo--compact" : ""} ${className}`}
      src={brandAssets.logo}
      alt={brand.displayName}
      width={2149}
      height={732}
    />
  );
}
