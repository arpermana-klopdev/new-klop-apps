import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        brand: {
          50: "rgb(var(--klop-brand-50-rgb) / <alpha-value>)",
          100: "rgb(var(--klop-brand-100-rgb) / <alpha-value>)",
          500: "rgb(var(--klop-brand-500-rgb) / <alpha-value>)",
          600: "rgb(var(--klop-brand-600-rgb) / <alpha-value>)",
          700: "rgb(var(--klop-brand-700-rgb) / <alpha-value>)",
          950: "rgb(var(--klop-brand-950-rgb) / <alpha-value>)",
        },
      },
      boxShadow: {
        soft: "var(--klop-shadow-card)",
      },
    },
  },
  plugins: [require("@tailwindcss/forms")],
} satisfies Config;
