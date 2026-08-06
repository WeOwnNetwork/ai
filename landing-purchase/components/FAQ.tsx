"use client";

import { useState } from "react";
import Container from "./Container";
import Reveal from "./Reveal";

// Grounded in the Branding & Marketing guide's objection-handling script —
// every answer here stays inside the "safe to say" list. Nothing about
// pricing, ZDR routing, or specific compliance certifications is answered
// directly; those route to a real conversation instead (see the guide's
// "escalate immediately" list).
const faqs = [
  {
    q: "Is this a shared AI tool with other customers?",
    a: "No. Every customer gets their own dedicated server — never shared, never multi-tenant infrastructure.",
  },
  {
    q: "What happens to our documents?",
    a: "They stay on your own server. Only the specific question and answer being processed ever leaves it.",
  },
  {
    q: "Can we upload documents before we pay?",
    a: "Yes. You can set up your instance, upload both public and private documents, and configure everything first. You're only asked to pay once it's ready to go live.",
  },
  {
    q: "Can our team administer the AI system directly?",
    a: "No — WeOwn handles that part for you. It's a deliberate safety boundary, not a missing feature.",
  },
  {
    q: "How long does setup actually take?",
    a: "About 20 minutes for a first-time setup, and no developer or technical background is required.",
  },
  {
    q: "What does it cost?",
    a: "Pricing is set per instance, not per seat. Get started to set up your instance, or talk to us first if you'd rather discuss it before creating one.",
  },
];

export default function FAQ() {
  const [openIndex, setOpenIndex] = useState<number | null>(0);

  return (
    <section id="faq" className="border-t border-white/10 py-20 md:py-24">
      <Container>
        <Reveal className="max-w-2xl">
          <p className="font-mono text-xs uppercase tracking-[0.02em] text-text-faint">
            Questions
          </p>
          <h2 className="mt-3 text-3xl font-bold tracking-[-0.015em] text-text md:text-[36px]">
            Frequently asked, honestly answered.
          </h2>
        </Reveal>

        <Reveal
          delay={100}
          className="mt-12 max-w-3xl divide-y divide-white/10 border-t border-b border-white/10"
        >
          {faqs.map((item, i) => {
            const isOpen = openIndex === i;
            return (
              <div key={item.q}>
                <button
                  type="button"
                  onClick={() => setOpenIndex(isOpen ? null : i)}
                  aria-expanded={isOpen}
                  className="flex w-full items-center justify-between gap-6 rounded-sm px-2 py-5 text-left transition-colors hover:bg-surface-1 -mx-2"
                >
                  <span className="text-[17px] font-medium text-text">
                    {item.q}
                  </span>
                  <span
                    className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-white/10 text-text-mut transition-transform duration-200 ${
                      isOpen ? "rotate-45" : ""
                    }`}
                    aria-hidden
                  >
                    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor" strokeWidth={2}>
                      <path d="M12 5v14M5 12h14" strokeLinecap="round" />
                    </svg>
                  </span>
                </button>
                {isOpen && (
                  <p className="max-w-2xl pb-5 text-[15px] leading-relaxed text-text-mut">
                    {item.a}
                  </p>
                )}
              </div>
            );
          })}
        </Reveal>
      </Container>
    </section>
  );
}
