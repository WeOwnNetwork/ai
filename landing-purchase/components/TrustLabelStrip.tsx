// The "trust-label" device from the weownchat-design skill: plain facts,
// not marketing copy, set like a spec sheet. Pulled directly from the
// Branding & Marketing guide's proof-points list (§10) — never invent a new
// claim here. One consistent treatment now — the whole page is dark, so
// there's no separate "inverse" surface to account for.
type TrustLabelStripProps = {
  items?: string[];
};

const defaultItems = [
  "Dedicated server, not shared",
  "Documents never leave your instance",
  "Live in about 20 minutes",
];

export default function TrustLabelStrip({
  items = defaultItems,
}: TrustLabelStripProps) {
  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-2 font-mono text-[11px] uppercase tracking-[0.02em] text-text-faint md:text-xs">
      {items.map((item, i) => (
        <span key={item} className="flex items-center gap-x-3">
          <span>{item}</span>
          {i < items.length - 1 && (
            <span aria-hidden className="opacity-50">
              &middot;
            </span>
          )}
        </span>
      ))}
    </div>
  );
}
