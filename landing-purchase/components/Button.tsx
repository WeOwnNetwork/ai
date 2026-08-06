import Link from "next/link";
import type { ReactNode } from "react";

type ButtonProps = {
  href: string;
  children: ReactNode;
  variant?: "primary" | "secondary" | "ghost";
  size?: "md" | "lg";
};

// r-md (10px), matching the dashboard's own .btn-solid — not a pill.
// Full-pill radius is reserved for badges/chips/avatars (see BrandMark,
// TrustLabelStrip, the status dots), never for buttons. Hover/active
// transforms are copied from the real product's own primary button
// (.pf-v5-c-button.pf-m-primary in the Keycloak theme): lift 1px on hover,
// settle 2% smaller on press — not invented values. No shadow — this page
// runs shadow-free by design (the real button does use one; this is a
// deliberate landing-page deviation, see BrandMark.tsx).
const base =
  "inline-flex items-center justify-center rounded-md font-semibold font-sans transition-[background-color,border-color,color,transform] duration-150 ease-[cubic-bezier(.16,1,.3,1)] active:scale-[0.98] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-strong";

const variants: Record<NonNullable<ButtonProps["variant"]>, string> = {
  primary: "bg-accent text-white hover:bg-accent-strong hover:-translate-y-px",
  secondary:
    "bg-surface-2 text-text border border-white/20 hover:border-accent hover:-translate-y-px",
  ghost: "bg-transparent text-text-mut hover:text-text",
};

const sizes: Record<NonNullable<ButtonProps["size"]>, string> = {
  md: "px-4 py-2.5 text-[15px]",
  lg: "px-6 py-3.5 text-base",
};

export default function Button({
  href,
  children,
  variant = "primary",
  size = "md",
}: ButtonProps) {
  const isExternal = href.startsWith("http");
  const className = `${base} ${variants[variant]} ${sizes[size]}`;

  if (isExternal) {
    return (
      <a href={href} className={className} target="_blank" rel="noopener noreferrer">
        {children}
      </a>
    );
  }

  return (
    <Link href={href} className={className}>
      {children}
    </Link>
  );
}
