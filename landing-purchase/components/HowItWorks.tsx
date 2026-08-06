import Container from "./Container";
import Reveal from "./Reveal";
import { IconUpload, IconServer, IconGlobe } from "./icons";

const steps = [
  {
    icon: IconUpload,
    label: "01",
    title: "Upload your documents",
    body: "Add the material that already answers your clients' questions — FAQs, service sheets, internal notes. Public and private, kept on two separate tabs.",
  },
  {
    icon: IconServer,
    label: "02",
    title: "Your instance comes online",
    body: "A dedicated server is provisioned for you alone. Nothing about it is shared with any other customer, ever.",
  },
  {
    icon: IconGlobe,
    label: "03",
    title: "Go live, on your terms",
    body: "Add your website to the allow-list, paste one line of code, and your assistant starts answering — for visitors and for your team.",
  },
];

export default function HowItWorks() {
  return (
    <section id="how-it-works" className="py-20 md:py-24">
      <Container>
        <Reveal className="max-w-2xl">
          <p className="font-mono text-xs uppercase tracking-[0.02em] text-text-faint">
            How it works
          </p>
          <h2 className="mt-3 text-3xl font-bold tracking-[-0.015em] text-text md:text-[36px]">
            Live in about 20 minutes. No developer required.
          </h2>
        </Reveal>

        <div className="mt-14 grid gap-10 md:grid-cols-3 md:gap-8">
          {steps.map((step, i) => (
            <Reveal key={step.title} delay={i * 100} className="relative">
              <div className="flex items-center gap-3">
                <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full border border-white/10 bg-surface-2 text-text">
                  <step.icon className="h-5 w-5" />
                </span>
                <span className="font-mono text-xs text-text-faint">
                  {step.label}
                </span>
              </div>
              <h3 className="mt-5 text-lg font-bold text-text">
                {step.title}
              </h3>
              <p className="mt-2 text-[15px] leading-relaxed text-text-mut">
                {step.body}
              </p>
            </Reveal>
          ))}
        </div>
      </Container>
    </section>
  );
}
