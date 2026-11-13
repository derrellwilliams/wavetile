// Loaded in <head> (not deferred) so the .js class is set before first paint and revealed
// content never flashes.
document.documentElement.classList.add("js");
// iOS Safari only shows :active (the pressed state) once a page listens for touches.
document.addEventListener("touchstart", () => {}, { passive: true });

document.addEventListener("DOMContentLoaded", () => {
  const reveals = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window)) return reveals.forEach((el) => el.classList.add("is-in"));
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add("is-in"); io.unobserve(e.target); }
  }, { rootMargin: "0px 0px -8% 0px" });
  reveals.forEach((el) => io.observe(el));
});

// The turning cube from DesignSystem/Components (WavetileMark) and the screenshot marquee. Each
// runs frames only while it's on screen and actually moving. Reduce Motion holds both still.
const still = matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window);
// With a mouse, the marquee moves only while the pointer is over it. Without hover (phones,
// tablets) it moves whenever it's on screen.
const fine = matchMedia("(hover: hover) and (pointer: fine)").matches;
const smooth = (x) => x * x * (3 - 2 * x);

document.addEventListener("DOMContentLoaded", () => {
  // Footer cube: always turning while on screen, like the app's loading mark.
  document.querySelectorAll("[data-mark]").forEach((host) => {
    const rays = mountCube(host);
    animate(host, cubeStep(rays, () => true));
  });
  // Hero cube: always turning while on screen, too.
  document.querySelectorAll(".hero__cube [data-cube]").forEach((rays) => animate(rays.ownerSVGElement, cubeStep(rays, () => true)));
  document.querySelectorAll(".screens").forEach((screens) => {
    const track = screens.querySelector(".marquee");
    if (!track || still) return;
    track.style.animation = "none"; // the CSS loop is the no-JS fallback
    let wake = () => {};
    const active = fine ? pointerOver(screens, () => wake()) : () => true;
    wake = animate(screens, marqueeStep(track, active));
  });
});

// Calls step(seconds since the last frame) every frame while host is on screen and step returns
// true (still moving). Returns wake(), which restarts the loop after it has settled.
function animate(host, step) {
  if (still) return () => {};
  let visible = false, last = 0, id = 0;
  const tick = (now) => {
    // rAF's timestamp can be a little before `last` (taken in an event), so never go backwards.
    const dt = Math.max(0, Math.min(0.1, (now - last) / 1000)); last = now;
    id = visible && step(dt) ? requestAnimationFrame(tick) : 0;
  };
  const wake = () => { if (!id && visible) { last = performance.now(); id = requestAnimationFrame(tick); } };
  new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    if (visible) wake(); else { cancelAnimationFrame(id); id = 0; }
  }).observe(host);
  return wake;
}

// Whether a mouse is over el, calling wake() on every change. A touch on el (a touchscreen laptop)
// switches it on for good, since touch has no hover to end it. A page restored from the
// back/forward cache starts with the pointer outside.
function pointerOver(el, wake) {
  let mouse = false, touched = false;
  el.addEventListener("pointerenter", (e) => { if (e.pointerType !== "touch") { mouse = true; wake(); } });
  el.addEventListener("pointerleave", (e) => { if (e.pointerType !== "touch") { mouse = false; wake(); } });
  el.addEventListener("pointerdown", (e) => { if (e.pointerType === "touch") { touched = true; wake(); } });
  addEventListener("pageshow", (e) => { if (e.persisted) { mouse = false; wake(); } });
  return () => mouse || touched;
}

// Cube: three edges from the center slide a quarter turn around the frame, then rest.
// Same geometry, easing and timing as WavetileMark: 0.7 s moving, 0.5 s resting. When `active`
// goes false it finishes the turn in progress, skips the rest and stops, so the next hover turns
// at once. Whole turns are counted as an integer, so rest poses are exact.
function cubeStep(rays, active) {
  const low = 12, high = 88, rest = [0.5, 1.5, 3], move = 0.7, period = 0.7 + 0.5;
  const point = (p) => {
    const s = ((p % 4) + 4) % 4, side = Math.floor(s), f = s - side, len = high - low;
    return [[low + len * f, low], [high, low + len * f], [high - len * f, high], [low, high - len * f]][side];
  };
  const ease = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
  let turns = 0, within = 0;
  return (dt) => {
    const on = active();
    if (!on && within === 0) return false;
    within += dt;
    if (within >= period) { turns += 1; within = on ? within - period : 0; }
    else if (!on && within >= move) { turns += 1; within = 0; }
    const turn = turns + ease(Math.min(1, within / move));
    rays.setAttribute("d", rest.map((r) => {
      const [x, y] = point(r + turn);
      return `M50 50L${x.toFixed(2)} ${y.toFixed(2)}`;
    }).join(""));
    return on || within > 0;
  };
}

// Footer cube, built here. The stroke stays 1.5px at any size, matching the arrow icon.
function mountCube(host) {
  const stroke = (150 / (host.clientWidth || 32)).toFixed(3);
  host.innerHTML =
    `<svg viewBox="0 0 100 100" fill="none" stroke="currentColor" stroke-width="${stroke}">` +
    '<rect x="10" y="10" width="80" height="80" rx="8"/>' +
    '<path d="M50 50L50 12M50 50L88 50M50 50L12 88"/>' +
    `<circle cx="50" cy="50" r="${stroke / 2}" fill="currentColor" stroke="none"/></svg>`;
  return host.querySelector("path");
}

// Marquee: slides left one set of screens every 84 s (the CSS fallback's pace) and wraps
// seamlessly. It eases up to speed and back to a stop over 0.4 s, and holds wherever it stopped.
function marqueeStep(track, active) {
  let progress = 0, speed = 0;
  return (dt) => {
    const on = active();
    speed = on ? Math.min(1, speed + dt / 0.4) : Math.max(0, speed - dt / 0.4);
    progress = (progress + smooth(speed) * dt / 84) % 1;
    track.style.transform = `translateX(${(-50 * progress).toFixed(4)}%)`;
    return on || speed > 0;
  };
}

// QR dialog: the QR button (desktop only; a phone just taps Download) opens a modal <dialog>
// that grows out of the button. Closes on the X, Esc, or a click on the backdrop.
document.addEventListener("DOMContentLoaded", () => {
  const dialog = document.querySelector("dialog.qr");
  const open = document.querySelector("[data-qr-open]");
  if (!dialog || !open || typeof dialog.showModal !== "function" || !fine) return;
  open.hidden = false;
  open.addEventListener("click", () => {
    dialog.showModal();
    // The dialog is centered, so its box follows from its size; aim the grow at the button's center.
    const b = open.getBoundingClientRect();
    const x = b.left + b.width / 2 - (innerWidth - dialog.offsetWidth) / 2;
    const y = b.top + b.height / 2 - (innerHeight - dialog.offsetHeight) / 2;
    dialog.style.setProperty("--ox", `${x.toFixed(1)}px`);
    dialog.style.setProperty("--oy", `${y.toFixed(1)}px`);
  });
  dialog.querySelector("[data-qr-close]").addEventListener("click", () => dialog.close());
  // The backdrop is part of the dialog, so a click whose target is the dialog itself is outside the card.
  dialog.addEventListener("click", (e) => { if (e.target === dialog) dialog.close(); });
});
