// The literal WeOwn brand mark — identical treatment to the dashboard
// sidebar and Keycloak login header (.brand-mark / #kc-header-wrapper::before),
// minus the drop shadow: this landing page runs shadow-free throughout by
// design, a deliberate flat-surface deviation from the dashboard (which does
// use shadow-md/-lg for elevation — see the weownchat-design skill).
export default function BrandMark({ size = 40 }: { size?: number }) {
  const radius = Math.round(size * 0.275);
  const fontSize = Math.round(size * 0.425);

  return (
    <div
      style={{ width: size, height: size, borderRadius: radius, fontSize }}
      className="flex shrink-0 items-center justify-center border border-white/16 bg-accent font-extrabold tracking-[-0.02em] text-white"
      aria-hidden
    >
      W
    </div>
  );
}
