"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { usePrefersReducedMotion } from "./hooks";

// Fades + rises content into place the first time it scrolls into view.
// Dependency-free (plain IntersectionObserver) — this is the one thing that
// most separates a page that feels alive from a static printout, so it's
// applied broadly across section headers and cards, not just the hero.
export default function Reveal({
  children,
  delay = 0,
  className = "",
  as: Tag = "div",
}: {
  children: ReactNode;
  delay?: number;
  className?: string;
  as?: "div" | "li";
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  const reducedMotion = usePrefersReducedMotion();

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          observer.unobserve(el);
        }
      },
      { threshold: 0.15, rootMargin: "0px 0px -60px 0px" }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const Comp = Tag as "div";

  return (
    <Comp
      ref={ref}
      className={className}
      style={
        reducedMotion
          ? undefined
          : {
              transitionProperty: "opacity, transform",
              transitionDuration: "700ms",
              transitionTimingFunction: "cubic-bezier(.16,1,.3,1)",
              transitionDelay: `${delay}ms`,
              opacity: visible ? 1 : 0,
              transform: visible ? "none" : "translateY(22px)",
            }
      }
    >
      {children}
    </Comp>
  );
}
