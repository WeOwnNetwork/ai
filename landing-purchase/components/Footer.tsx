import Button from "./Button";
import Container from "./Container";
import Reveal from "./Reveal";
import TrustLabelStrip from "./TrustLabelStrip";
import BrandMark from "./BrandMark";

const columns = [
  {
    heading: "Product",
    links: [
      { label: "How it works", href: "#how-it-works" },
      { label: "Pricing", href: "#pricing" },
      { label: "FAQ", href: "#faq" },
    ],
  },
  {
    heading: "Account",
    links: [
      { label: "Sign in", href: "https://billing.weown.dev" },
      { label: "Get started", href: "https://billing.weown.dev" },
    ],
  },
];

export default function Footer() {
  return (
    <footer className="border-t border-white/10 bg-surface-1 pt-20 pb-10 md:pt-24">
      <Container>
        <Reveal className="flex flex-col justify-between gap-12 border-b border-white/10 pb-14 md:flex-row md:items-end">
          <div className="max-w-md">
            <h2 className="text-3xl font-bold tracking-[-0.015em] text-text md:text-4xl">
              Ready to answer from your own material?
            </h2>
            <p className="mt-4 text-text-mut">
              Set up your instance and upload your first documents today —
              you won&rsquo;t be asked to pay until it&rsquo;s ready to go
              live.
            </p>
          </div>
          <Button href="https://billing.weown.dev" size="lg">
            Get started
          </Button>
        </Reveal>

        <div className="grid gap-12 py-14 sm:grid-cols-[1.5fr_1fr_1fr]">
          <div>
            <div className="flex items-center gap-2.5">
              <BrandMark size={30} />
              <span className="text-lg font-bold tracking-tight text-text">
                WeOwn<span className="text-accent">Chat</span>
              </span>
            </div>
            <p className="mt-3 max-w-xs text-sm text-text-mut">
              A dedicated AI assistant for agencies and professional
              practices — grounded only in what you give it.
            </p>
          </div>

          {columns.map((col) => (
            <div key={col.heading}>
              <p className="font-mono text-xs uppercase tracking-[0.02em] text-text-faint">
                {col.heading}
              </p>
              <ul className="mt-4 space-y-3">
                {col.links.map((link) => (
                  <li key={link.label}>
                    <a
                      href={link.href}
                      className="text-[15px] text-text-mut transition-colors hover:text-text"
                    >
                      {link.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="flex flex-col gap-4 border-t border-white/10 pt-8 sm:flex-row sm:items-center sm:justify-between">
          <TrustLabelStrip />
          <p className="text-xs text-text-faint">
            &copy; {new Date().getFullYear()} WeOwn. All rights reserved.
          </p>
        </div>
      </Container>
    </footer>
  );
}
