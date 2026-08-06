import Button from "./Button";
import Container from "./Container";
import Reveal from "./Reveal";
import { IconCheck } from "./icons";

// Guardrail: never display a specific price, bundle, or affiliate percentage
// here — every figure discussed internally is draft and not in writing
// (see the Branding & Marketing guide, §2). This section describes what's
// included and routes to a real conversation instead of a number.
const included = [
  "One dedicated server for your practice",
  "Public website chatbot + private team assistant",
  "Self-serve setup — upload documents before you pay anything",
  "Single sign-on, with self-service password reset",
  "Support for anything that touches your server, widget, or dashboard",
];

export default function Pricing() {
  return (
    <section id="pricing" className="bg-surface-1 py-20 md:py-24">
      <Container>
        <Reveal className="max-w-2xl">
          <p className="font-mono text-xs uppercase tracking-[0.02em] text-text-faint">
            Pricing
          </p>
          <h2 className="mt-3 text-3xl font-bold tracking-[-0.015em] text-text md:text-[36px]">
            Priced per practice, not per seat.
          </h2>
          <p className="mt-5 text-lg text-text-mut">
            Every instance is dedicated to one practice, so pricing is set
            per instance rather than per user. Get started and set up your
            instance first — you won&rsquo;t be asked to pay until it&rsquo;s
            ready to go live.
          </p>
        </Reveal>

        <Reveal
          delay={100}
          className="mt-12 grid gap-6 rounded-lg border border-white/10 bg-surface-2 p-8 md:grid-cols-[1fr_auto] md:items-center md:gap-12 md:p-10"
        >
          <ul className="space-y-3.5">
            {included.map((item) => (
              <li key={item} className="flex items-start gap-3">
                <IconCheck className="mt-0.5 h-5 w-5 shrink-0 text-accent" />
                <span className="text-[15px] text-text">{item}</span>
              </li>
            ))}
          </ul>

          <div className="flex flex-col items-start gap-3 border-t border-white/10 pt-6 md:items-stretch md:border-t-0 md:border-l md:pt-0 md:pl-12">
            <Button href="https://billing.weown.dev" size="lg">
              Get started
            </Button>
            <Button href="#faq" variant="secondary" size="lg">
              Talk to us first
            </Button>
          </div>
        </Reveal>
      </Container>
    </section>
  );
}
