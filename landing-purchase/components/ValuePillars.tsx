import Container from "./Container";
import Reveal from "./Reveal";
import {
  IconServer,
  IconDocument,
  IconShield,
  IconChat,
  IconCheck,
  IconUsers,
} from "./icons";

const pillars = [
  {
    icon: IconServer,
    title: "Your own server",
    body: "Not a shared account on someone else's infrastructure. One dedicated, hardened server, for you alone.",
  },
  {
    icon: IconDocument,
    title: "Grounded in your material",
    body: "It doesn't guess and it doesn't reach for the open web. It answers from what you actually gave it — nothing else.",
  },
  {
    icon: IconShield,
    title: "Built for confidential data",
    body: "Your documents stay on your server. Only the specific question and answer being processed ever leaves it.",
  },
  {
    icon: IconChat,
    title: "Two products, one setup",
    body: "A public chatbot for your website and a private assistant for your team — from the same upload, on the same instance.",
  },
  {
    icon: IconCheck,
    title: "No technical skill required",
    body: "Upload documents, add your domain, paste one line of code. Set up over a coffee break — no developer needed.",
  },
  {
    icon: IconUsers,
    title: "Real support when it matters",
    body: "Anything that touches your server, widget, or dashboard is on us — sign-in issues, password resets, adding team members, document help.",
  },
];

export default function ValuePillars() {
  return (
    <section className="py-20 md:py-24">
      <Container>
        <Reveal className="max-w-2xl">
          <p className="font-mono text-xs uppercase tracking-[0.02em] text-text-faint">
            Why it&rsquo;s built this way
          </p>
          <h2 className="mt-3 text-3xl font-bold tracking-[-0.015em] text-text md:text-[36px]">
            Every choice here favors trust over convenience.
          </h2>
        </Reveal>

        <div className="mt-14 grid gap-px overflow-hidden rounded-lg border border-white/10 bg-white/10 sm:grid-cols-2 lg:grid-cols-3">
          {pillars.map((pillar, i) => (
            <Reveal
              key={pillar.title}
              delay={(i % 3) * 90}
              className="group relative bg-surface-1 p-8 transition-colors duration-300 hover:bg-surface-2"
            >
              <span className="flex h-10 w-10 items-center justify-center rounded-full bg-accent/[0.14] text-accent transition-transform duration-300 group-hover:scale-110">
                <pillar.icon className="h-5 w-5" />
              </span>
              <h3 className="mt-5 text-lg font-bold text-text">
                {pillar.title}
              </h3>
              <p className="mt-2 text-[15px] leading-relaxed text-text-mut">
                {pillar.body}
              </p>
            </Reveal>
          ))}
        </div>
      </Container>
    </section>
  );
}
