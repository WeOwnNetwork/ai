import Button from "./Button";
import Container from "./Container";
import TrustLabelStrip from "./TrustLabelStrip";
import AnimatedChatMock from "./AnimatedChatMock";

export default function Hero() {
  return (
    <section
      className="overflow-hidden pt-16 pb-20 md:pt-24 md:pb-28"
      style={{
        background:
          "radial-gradient(ellipse 900px 560px at 50% -10%, rgba(0, 163, 255, .16), transparent 60%)",
      }}
    >
      <Container className="grid items-center gap-14 md:grid-cols-2 md:gap-10">
        <div style={{ animation: "weown-rise 0.7s cubic-bezier(.16,1,.3,1)" }}>
          <h1 className="text-[40px] font-bold leading-[1.08] tracking-[-0.02em] text-text sm:text-[48px] md:text-[56px]">
            Answers from your own material, on your own server.
          </h1>
          <p className="mt-6 max-w-xl text-lg text-text-mut">
            WeOwnChat is a dedicated assistant built entirely from your own
            documents — a chatbot for your website, and a private assistant
            for your team. Nothing shared. Nothing generic.
          </p>

          <div className="mt-9 flex flex-wrap items-center gap-4">
            <Button href="https://billing.weown.dev" size="lg">
              Get started
            </Button>
            <Button href="#how-it-works" variant="secondary" size="lg">
              See how it works
            </Button>
          </div>

          <div className="mt-10 border-t border-white/10 pt-6">
            <TrustLabelStrip />
          </div>
        </div>

        <div style={{ animation: "weown-rise 0.8s cubic-bezier(.16,1,.3,1) 0.15s backwards" }}>
          <AnimatedChatMock />
        </div>
      </Container>
    </section>
  );
}
