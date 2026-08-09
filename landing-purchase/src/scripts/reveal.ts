// Generic scroll-reveal: one observer for the whole page instead of a
// wrapper component per section. Progressive enhancement — see the
// [data-reveal] comment in global.css for why elements are visible by
// default and only opt into the hidden-then-reveal transition here, plus
// why there's a timeout fallback in addition to the observer.
const elements = document.querySelectorAll<HTMLElement>("[data-reveal]");

function reveal(el: HTMLElement) {
  if (el.dataset.revealed === "true") return;
  const delay = el.dataset.revealDelay;
  if (delay) el.style.transitionDelay = `${delay}ms`;
  el.dataset.revealed = "true";
}

if (elements.length > 0) {
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          reveal(entry.target as HTMLElement);
          observer.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.15, rootMargin: "0px 0px -60px 0px" },
  );

  elements.forEach((el) => {
    el.classList.add("reveal-armed");
    observer.observe(el);
  });

  // Safety net: if the observer never fires for some element (should be
  // rare in a real browser, but was reproducible in testing — see
  // global.css), nothing should stay invisible forever.
  setTimeout(() => {
    elements.forEach((el) => {
      if (el.dataset.revealed !== "true") reveal(el);
    });
  }, 2500);
}
