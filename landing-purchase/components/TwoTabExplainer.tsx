import Container from "./Container";
import Reveal from "./Reveal";
import { IconUsers, IconGlobe, IconKey } from "./icons";

export default function TwoTabExplainer() {
  return (
    <section className="border-y border-white/10 bg-bg py-20 md:py-24">
      <Container>
        <Reveal className="max-w-2xl">
          <p className="font-mono text-xs uppercase tracking-[0.02em] text-text-faint">
            The rule that governs everything
          </p>
          <h2 className="mt-3 text-3xl font-bold tracking-[-0.015em] text-text md:text-[36px]">
            Two tabs. One rule you never have to think twice about.
          </h2>
          <p className="mt-5 text-lg text-text-mut">
            &ldquo;If you would not print it on a flyer, it does not go on
            the red tab.&rdquo; That single sentence is the whole model —
            and the reason nothing confidential ever reaches the public
            chatbot by accident.
          </p>
        </Reveal>

        <div className="mt-14 grid gap-6 md:grid-cols-2">
          <Reveal
            delay={0}
            className="group rounded-lg border border-ok/30 bg-ok/[0.06] p-8 transition-all duration-300 hover:-translate-y-1 hover:border-ok/50 hover:bg-ok/[0.09]"
          >
            <div className="flex items-center gap-2.5">
              <span className="h-2.5 w-2.5 rounded-full bg-ok" />
              <span className="font-mono text-xs uppercase tracking-[0.02em] text-ok">
                Private assistant
              </span>
            </div>
            <h3 className="mt-4 flex items-center gap-2.5 text-xl font-bold text-text">
              <IconUsers className="h-5 w-5 text-text-mut" />
              Only you and your team
            </h3>
            <p className="mt-3 text-[15px] leading-relaxed text-text-mut">
              Client files, contracts, internal notes — anything
              confidential. Powers your own team&rsquo;s private chat, never
              the public site.
            </p>
          </Reveal>

          <Reveal
            delay={100}
            className="group rounded-lg border border-warn/30 bg-warn/[0.06] p-8 transition-all duration-300 hover:-translate-y-1 hover:border-warn/50 hover:bg-warn/[0.09]"
          >
            <div className="flex items-center gap-2.5">
              <span className="h-2.5 w-2.5 rounded-full bg-warn" />
              <span className="font-mono text-xs uppercase tracking-[0.02em] text-[#ff8f8f]">
                Website chatbot
              </span>
            </div>
            <h3 className="mt-4 flex items-center gap-2.5 text-xl font-bold text-text">
              <IconGlobe className="h-5 w-5 text-text-mut" />
              Open to your visitors
            </h3>
            <p className="mt-3 text-[15px] leading-relaxed text-text-mut">
              Hours, services, pricing sheets, FAQs. Answers your website
              visitors — and only on domains you&rsquo;ve explicitly
              authorized.
            </p>
          </Reveal>
        </div>

        <Reveal
          delay={200}
          className="mt-6 flex items-start gap-3 rounded-lg border border-white/10 bg-surface-2 p-6"
        >
          <IconKey className="mt-0.5 h-5 w-5 shrink-0 text-accent" />
          <p className="text-[15px] leading-relaxed text-text">
            The domain allow-list is a real security control, not a
            convenience. Paste the widget anywhere else and it simply stays
            silent — by design.
          </p>
        </Reveal>
      </Container>
    </section>
  );
}
