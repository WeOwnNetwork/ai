"use client";

import { useRef, useState } from "react";
import Container from "./Container";
import Reveal from "./Reveal";

// This is not a mockup — it's the real dashboard (anythingllm-docker/
// template/dashboard/public/index.html) running unmodified inside an
// iframe, fed realistic seeded content via public/_demo/dashboard-preview.html
// (see that file's own header comment). What a visitor sees here is exactly
// what a customer's actual instance looks like.
export default function ProductShowcase() {
  const [tab, setTab] = useState<"private" | "public">("private");
  const iframeRef = useRef<HTMLIFrameElement>(null);

  function switchTab(next: "private" | "public") {
    setTab(next);
    const win = iframeRef.current?.contentWindow;
    if (win) {
      win.location.hash = `#${next}`;
    }
  }

  return (
    <section className="bg-surface-1 py-20 md:py-24">
      <Container>
        <Reveal className="flex flex-col items-start justify-between gap-6 sm:flex-row sm:items-end">
          <div className="max-w-2xl">
            <p className="font-mono text-xs uppercase tracking-[0.02em] text-text-faint">
              Live preview
            </p>
            <h2 className="mt-3 text-3xl font-bold tracking-[-0.015em] text-text md:text-[36px]">
              See exactly what you&rsquo;re signing up for.
            </h2>
            <p className="mt-4 text-lg text-text-mut">
              Every screen below is the real dashboard, with example content
              standing in for your own.
            </p>
          </div>

          <div className="flex gap-2 rounded-full border border-white/10 bg-bg p-1">
            <button
              type="button"
              onClick={() => switchTab("private")}
              className={`rounded-full px-4 py-2 text-sm font-semibold transition-colors ${
                tab === "private" ? "bg-ok/[0.16] text-ok" : "text-text-faint hover:text-text-mut"
              }`}
            >
              Private
            </button>
            <button
              type="button"
              onClick={() => switchTab("public")}
              className={`rounded-full px-4 py-2 text-sm font-semibold transition-colors ${
                tab === "public" ? "bg-warn/[0.16] text-[#ff8f8f]" : "text-text-faint hover:text-text-mut"
              }`}
            >
              Public
            </button>
          </div>
        </Reveal>

        <Reveal delay={120} className="mt-10">
          <div className="overflow-hidden rounded-lg border border-white/10 bg-surface-2">
            <div className="flex items-center gap-3 border-b border-white/10 bg-surface-3 px-4 py-2.5">
              <div className="flex gap-1.5">
                <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
                <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
                <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
              </div>
              <div className="mx-auto flex items-center gap-1.5 rounded-full bg-bg px-3 py-1 font-mono text-[11px] text-text-faint">
                <svg viewBox="0 0 24 24" className="h-3 w-3 text-ok" fill="none" stroke="currentColor" strokeWidth={2}>
                  <rect x="5" y="11" width="14" height="9" rx="2" />
                  <path d="M8 11V8a4 4 0 0 1 8 0v3" />
                </svg>
                harborviewcpa.weown.dev/app
              </div>
            </div>
            <iframe
              ref={iframeRef}
              src="/_demo/dashboard-preview.html"
              title="WeOwnChat dashboard preview, with example content"
              className="h-[420px] w-full sm:h-[540px]"
              style={{ border: 0, background: "#0e1726" }}
              loading="lazy"
            />
          </div>
        </Reveal>
      </Container>
    </section>
  );
}
