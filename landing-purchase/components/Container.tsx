import type { ReactNode } from "react";

// Matches --container-max (1120px) from the design tokens reference.
export default function Container({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={`mx-auto max-w-[1120px] px-6 ${className}`}>
      {children}
    </div>
  );
}
