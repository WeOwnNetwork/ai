"use client";

import { useState } from "react";
import Link from "next/link";
import Button from "./Button";
import Container from "./Container";
import BrandMark from "./BrandMark";

const links = [
  { href: "#how-it-works", label: "How it works" },
  { href: "#pricing", label: "Pricing" },
  { href: "#faq", label: "FAQ" },
];

export default function Nav() {
  const [open, setOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-white/10 bg-surface-1/90 backdrop-blur-md">
      <Container className="flex items-center justify-between py-3.5">
        <Link
          href="/"
          className="flex items-center gap-2.5 text-lg font-bold tracking-tight text-text"
          onClick={() => setOpen(false)}
        >
          <BrandMark size={32} />
          WeOwn<span className="text-accent">Chat</span>
        </Link>

        <nav className="hidden items-center gap-8 md:flex">
          {links.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="text-[15px] text-text-mut transition-colors hover:text-text"
            >
              {link.label}
            </a>
          ))}
        </nav>

        <div className="flex items-center gap-3">
          <a
            href="https://billing.weown.dev"
            className="hidden text-[15px] text-text-mut transition-colors hover:text-text sm:inline"
          >
            Sign in
          </a>
          <Button href="https://billing.weown.dev" size="md">
            Get started
          </Button>
          <button
            type="button"
            aria-label={open ? "Close menu" : "Open menu"}
            aria-expanded={open}
            onClick={() => setOpen((v) => !v)}
            className="flex h-9 w-9 items-center justify-center rounded-full border border-white/10 text-text md:hidden"
          >
            <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round">
              {open ? <path d="M6 6l12 12M18 6L6 18" /> : <path d="M4 7h16M4 12h16M4 17h16" />}
            </svg>
          </button>
        </div>
      </Container>

      {open && (
        <nav className="border-t border-white/10 bg-surface-1 px-6 py-4 md:hidden">
          <ul className="space-y-1">
            {links.map((link) => (
              <li key={link.href}>
                <a
                  href={link.href}
                  onClick={() => setOpen(false)}
                  className="block rounded-sm px-2 py-2.5 text-[15px] text-text-mut hover:bg-surface-2 hover:text-text"
                >
                  {link.label}
                </a>
              </li>
            ))}
            <li>
              <a
                href="https://billing.weown.dev"
                className="block rounded-sm px-2 py-2.5 text-[15px] text-text-mut hover:bg-surface-2 hover:text-text"
              >
                Sign in
              </a>
            </li>
          </ul>
        </nav>
      )}
    </header>
  );
}
