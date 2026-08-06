"use client";

import { useEffect, useRef, useState } from "react";
import { usePrefersReducedMotion } from "./hooks";

// A live, looping recreation of the real product's own chat UI — not an
// abstract skeleton mockup. Bubble shapes, colors, and the "thinking" dots
// are copied property-for-property from the real dashboard
// (anythingllm-docker/template/dashboard/public/index.html: .msg.user
// .mbubble, .msg.bot .mbubble, .thinking i) rather than approximated.
// Content is illustrative — a small-practice website FAQ exchange — never
// implies this is a real customer's data.

const exchanges = [
  {
    user: "Do you offer evening appointments?",
    bot: "Yes — Tuesdays and Thursdays until 7pm, by appointment. I can also pull up our other hours or services if that helps.",
  },
  {
    user: "What do I need to bring for my first visit?",
    bot: "A photo ID, and your intake reference number if this is a returning matter. Want the full checklist?",
  },
];

type Phase = "thinking" | "answering" | "hold" | "clearing";

export default function AnimatedChatMock() {
  const reducedMotion = usePrefersReducedMotion();
  const [pairIndex, setPairIndex] = useState(0);
  const [phase, setPhase] = useState<Phase>("thinking");
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const current = exchanges[pairIndex];

  useEffect(() => {
    if (reducedMotion) {
      setPhase("hold");
      return;
    }

    const durations: Record<Phase, number> = {
      thinking: 1100,
      answering: 3200,
      hold: 1400,
      clearing: 350,
    };

    timeoutRef.current = setTimeout(() => {
      setPhase((p) => {
        if (p === "thinking") return "answering";
        if (p === "answering") return "hold";
        if (p === "hold") return "clearing";
        return "thinking";
      });
      if (phase === "clearing") {
        setPairIndex((i) => (i + 1) % exchanges.length);
      }
    }, durations[phase]);

    return () => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, [phase, reducedMotion]);

  const showUser = phase !== "clearing";
  const showThinking = phase === "thinking";
  const showAnswer = phase === "answering" || phase === "hold";

  return (
    <div className="relative">
      <div
        className="absolute -inset-6 -z-10 rounded-[32px] bg-accent/10 blur-2xl"
        style={{ animation: reducedMotion ? undefined : "weown-glow-pulse 4s ease-in-out infinite" }}
      />
      <div className="rounded-lg border border-white/10 bg-surface-2 p-4">
        <div className="mb-4 flex items-center justify-between">
          <div className="flex gap-2">
            <div className="flex items-center gap-1.5 rounded-full border border-white/10 px-3 py-1.5 text-xs font-semibold text-text-faint">
              <span className="h-1.5 w-1.5 rounded-full bg-ok" />
              Private assistant
            </div>
            <div className="flex items-center gap-1.5 rounded-full bg-warn/[0.13] border border-warn/40 px-3 py-1.5 text-xs font-semibold text-[#ff8f8f]">
              <span className="h-1.5 w-1.5 rounded-full bg-warn" />
              Website chatbot
            </div>
          </div>
          <span className="hidden font-mono text-[10px] uppercase tracking-[0.02em] text-text-faint sm:inline">
            live preview
          </span>
        </div>

        {/* min-height keeps the card from jumping as message lengths change */}
        <div className="flex min-h-[168px] flex-col justify-end gap-3 rounded-md bg-bg p-4">
          {showUser && (
            <div
              key={`user-${pairIndex}`}
              className="ml-auto flex max-w-[85%] items-end gap-2"
              style={{ animation: reducedMotion ? undefined : "weown-rise 0.4s cubic-bezier(.16,1,.3,1)" }}
            >
              <p className="rounded-[14px_14px_4px_14px] border border-accent/[0.38] bg-[#173257] px-3.5 py-2.5 text-[13.5px] leading-snug text-text">
                {current.user}
              </p>
            </div>
          )}

          {showThinking && (
            <div className="flex items-center gap-1.5 rounded-[14px_14px_14px_4px] px-1 py-2">
              {[0, 1, 2].map((i) => (
                <span
                  key={i}
                  className="h-1.5 w-1.5 rounded-full bg-text-faint"
                  style={{
                    animation: reducedMotion ? undefined : `weown-bounce 1.1s ease-in-out infinite`,
                    animationDelay: `${i * 0.15}s`,
                  }}
                />
              ))}
            </div>
          )}

          {showAnswer && (
            <div
              key={`bot-${pairIndex}`}
              className="flex max-w-[88%] items-start gap-2"
              style={{ animation: reducedMotion ? undefined : "weown-rise 0.45s cubic-bezier(.16,1,.3,1)" }}
            >
              <span className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-md border border-white/10 bg-surface-3 text-[10px] font-extrabold text-text-mut">
                W
              </span>
              <p className="pt-0.5 text-[13.5px] leading-relaxed text-text">
                {current.bot}
              </p>
            </div>
          )}
        </div>

        <div className="mt-4 flex items-center gap-2 rounded-full border border-white/10 bg-surface-3 px-4 py-2.5">
          <span className="h-2 flex-1 rounded-full bg-white/10" />
          <span className="flex h-6 w-6 items-center justify-center rounded-full bg-accent text-white">
            <svg viewBox="0 0 24 24" className="h-3 w-3" fill="none" stroke="currentColor" strokeWidth={2}>
              <path d="M12 19V5M5 12l7-7 7 7" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
        </div>
      </div>

      <div className="absolute -right-4 -top-4 rounded-full border border-white/10 bg-surface-3 px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.02em] text-text-faint sm:-right-8 sm:-top-6">
        Live in ~5 min
      </div>
    </div>
  );
}
