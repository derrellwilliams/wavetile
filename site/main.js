// Loaded in <head> (not deferred) so the .js class is set before first paint and revealed
// content never flashes. Everything else waits for the DOM.
document.documentElement.classList.add("js");

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");

document.addEventListener("DOMContentLoaded", () => {
  const nav = document.querySelector("[data-nav]");
  const fan = document.querySelector("[data-fan]");

  // Fan the hero phones out once the screenshots have had a frame to decode.
  if (fan) requestAnimationFrame(() => requestAnimationFrame(() => fan.classList.add("is-open")));

  // Scroll: frosted nav, and the fan spreads a little wider as you scroll past it.
  let ticking = false;
  const onScroll = () => {
    ticking = false;
    const y = scrollY;
    nav?.classList.toggle("is-scrolled", y > 8);
    if (fan && !reduceMotion.matches) {
      const spread = Math.min(1, Math.max(0, y / (innerHeight * 0.7)));
      fan.style.setProperty("--spread", spread.toFixed(3));
    }
  };
  addEventListener("scroll", () => {
    if (!ticking) { ticking = true; requestAnimationFrame(onScroll); }
  }, { passive: true });
  onScroll();

  // Reveal sections as they enter the viewport.
  const reveals = document.querySelectorAll(".reveal, .cascade");
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) { e.target.classList.add("is-in"); io.unobserve(e.target); }
    }, { rootMargin: "0px 0px -10% 0px" });
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add("is-in"));
  }

  // Story: the step crossing the middle of the screen picks the sticky phone's screen.
  const steps = document.querySelectorAll(".step");
  const screens = document.querySelectorAll(".phone--stage img");
  const activate = (name) => {
    steps.forEach((s) => s.classList.toggle("is-active", s.dataset.step === name));
    screens.forEach((img) => img.classList.toggle("is-active", img.dataset.screen === name));
  };
  if (steps.length && "IntersectionObserver" in window) {
    const so = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) activate(e.target.dataset.step);
    }, { rootMargin: "-45% 0px -45% 0px" });
    steps.forEach((s) => so.observe(s));
    activate(steps[0].dataset.step);
  }

  document.querySelectorAll(".mark[data-animate]").forEach(animateMark);
});

// The turning cube from WavetileMark.swift: three edges slide a quarter turn around the frame,
// rest, then turn again. Same geometry (100-unit grid) and timing (0.7s move, 0.5s hold).
function animateMark(host) {
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", "0 0 100 100");
  svg.setAttribute("aria-hidden", "true");
  svg.innerHTML =
    '<rect x="10" y="10" width="80" height="80" rx="8" fill="none" stroke="currentColor" stroke-width="11"/>' +
    '<path fill="none" stroke="currentColor" stroke-width="11"/>' +
    '<circle cx="50" cy="50" r="5.5" fill="currentColor"/>';
  host.append(svg);
  host.classList.add("is-live");
  const rays = svg.querySelector("path");

  const low = 12, high = 88, rest = [0.5, 1.5, 3], move = 0.7, hold = 0.5;
  const point = (p) => {
    const s = ((p % 4) + 4) % 4, side = Math.floor(s), f = s - side, len = high - low;
    return [[low + len * f, low], [high, low + len * f], [high - len * f, high], [low, high - len * f]][side];
  };
  const ease = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
  const draw = (turn) => {
    rays.setAttribute("d", rest.map((r) => { const [x, y] = point(r + turn); return `M50 50L${x.toFixed(2)} ${y.toFixed(2)}`; }).join(""));
  };
  draw(0);
  if (reduceMotion.matches) return;

  let visible = false, start = 0, frame = 0;
  const tick = (now) => {
    const t = (now - start) / 1000, period = move + hold, step = Math.floor(t / period);
    draw(step + ease(Math.min(1, (t - step * period) / move)));
    if (visible) frame = requestAnimationFrame(tick);
  };
  new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    cancelAnimationFrame(frame);
    if (visible) { start = performance.now(); frame = requestAnimationFrame(tick); }
  }).observe(host);
}
