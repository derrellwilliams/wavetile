// Loaded in <head> (not deferred) so the .js class is set before first paint and revealed
// content never flashes.
document.documentElement.classList.add("js");

document.addEventListener("DOMContentLoaded", () => {
  const reveals = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window)) return reveals.forEach((el) => el.classList.add("is-in"));
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add("is-in"); io.unobserve(e.target); }
  }, { rootMargin: "0px 0px -8% 0px" });
  reveals.forEach((el) => io.observe(el));
});

// The turning cube from WavetileMark.swift: three edges slide around the frame from the center.
// Same geometry, easing and timing: a quarter turn, then a rest. Each mark animates only while
// on screen and resumes where it left off.
document.addEventListener("DOMContentLoaded", () => {
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window);
  document.querySelectorAll("[data-mark]").forEach((host) => mountMark(host, still));
});

function mountMark(host, still) {
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", "0 0 100 100");
  svg.innerHTML =
    '<rect x="10" y="10" width="80" height="80" rx="8" fill="none" stroke="currentColor" stroke-width="11"/>' +
    '<path fill="none" stroke="currentColor" stroke-width="11"/>' +
    '<circle cx="50" cy="50" r="5.5" fill="currentColor"/>';
  host.append(svg);
  const rays = svg.querySelector("path");

  const low = 12, high = 88, rest = [0.5, 1.5, 3];
  const point = (p) => {
    const s = ((p % 4) + 4) % 4, side = Math.floor(s), f = s - side, len = high - low;
    return [[low + len * f, low], [high, low + len * f], [high - len * f, high], [low, high - len * f]][side];
  };
  const ease = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
  const draw = (turn) => rays.setAttribute("d", rest.map((r) => {
    const [x, y] = point(r + turn);
    return `M50 50L${x.toFixed(2)} ${y.toFixed(2)}`;
  }).join(""));
  draw(0);
  if (still) return;

  // 0.7 s moving, 1.2 s resting.
  const move = 0.7, hold = 1.2;
  const turnAt = (t) => {
    const period = move + hold, step = Math.floor(t / period);
    return step + ease(Math.min(1, (t - step * period) / move));
  };

  let visible = false, elapsed = 0, last = 0, frame = 0;
  const tick = (now) => {
    elapsed += (now - last) / 1000; last = now;
    draw(turnAt(elapsed));
    if (visible) frame = requestAnimationFrame(tick);
  };
  new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    cancelAnimationFrame(frame);
    if (visible) { last = performance.now(); frame = requestAnimationFrame(tick); }
  }).observe(host);
}
