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

// The marks from DesignSystem/Components, drawn the same way: the turning cube (WavetileMark) and
// the rippling wave (WaveMark). Each animates only while on screen. Reduce Motion holds them still.
const still = matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window);

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-mark]").forEach(mountCube);
  // With a mouse, the hero cube turns and the screenshots scroll only while the pointer is over
  // them. Touch has no hover, so there both just run while on screen.
  const fine = matchMedia("(hover: hover) and (pointer: fine)").matches;
  document.querySelectorAll(".hero").forEach((hero) => {
    const rays = hero.querySelector(".hero__cube [data-cube]");
    if (!rays) return;
    const over = hovering(hero);
    animate(rays.ownerSVGElement, cubeFrame(rays, () => !fine || over()));
  });
  if (!still) document.querySelectorAll(".screens").forEach((screens) => marquee(screens, fine));
  // The header's wave ripples only while the pointer is in the header, or the logo has keyboard
  // focus. Read live from :hover and :focus-visible, so a click (which focuses the link) or a page
  // restored from the back/forward cache can't leave it stuck on.
  document.querySelectorAll(".top").forEach((header) => {
    const link = header.querySelector(".brand"), wave = header.querySelector(".brand [data-wave]");
    if (!link || !wave) return;
    animate(wave.ownerSVGElement, waveFrame(wave, () => (fine && header.matches(":hover")) || link.matches(":focus-visible")));
  });
});

// Whether the pointer is over el, read live from :hover.
function hovering(el) {
  return () => el.matches(":hover");
}

// The screenshot marquee, driven here so it keeps its place: it slides left one set every 84 s
// (the CSS fallback's pace) and wraps seamlessly. With a mouse it moves only while the pointer is
// over it, easing up to speed and back to a stop over 0.4 s, and holds wherever it stopped,
// including while scrolled off screen. On touch it runs whenever it's on screen.
function marquee(screens, fine) {
  const track = screens.querySelector(".marquee");
  if (!track) return;
  track.style.animation = "none";
  let progress = 0, speed = fine ? 0 : 1, target = speed, visible = false, last = 0, id = 0;
  const tick = (now) => {
    const dt = Math.min(0.1, (now - last) / 1000); last = now;
    speed = target ? Math.min(1, speed + dt / 0.4) : Math.max(0, speed - dt / 0.4);
    progress = (progress + (speed * speed * (3 - 2 * speed)) * dt / 84) % 1;
    track.style.transform = `translateX(${(-50 * progress).toFixed(4)}%)`;
    id = visible && (speed > 0 || target > 0) ? requestAnimationFrame(tick) : 0;
  };
  const run = () => { if (!id && visible) { last = performance.now(); id = requestAnimationFrame(tick); } };
  if (fine) {
    screens.addEventListener("pointerenter", () => { target = 1; run(); });
    screens.addEventListener("pointerleave", () => { target = 0; run(); });
  }
  new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    if (visible) run(); else { cancelAnimationFrame(id); id = 0; }
  }).observe(screens);
}

// Runs frame(seconds) every animation frame while host is on screen, keeping its own clock so it
// resumes where it left off.
function animate(host, frame) {
  if (still) return;
  let visible = false, elapsed = 0, last = 0, id = 0;
  const tick = (now) => {
    elapsed += Math.min(0.1, (now - last) / 1000); last = now;
    frame(elapsed);
    if (visible) id = requestAnimationFrame(tick);
  };
  new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    cancelAnimationFrame(id);
    if (visible) { last = performance.now(); id = requestAnimationFrame(tick); }
  }).observe(host);
}

// Cube: three edges from the center slide a quarter turn around the frame, then rest.
// Same geometry, easing and timing as WavetileMark: 0.7 s moving, 0.5 s resting.
// With `active`, it only turns while that's true, finishing the turn it's in before it stops.
function cubeFrame(rays, active = () => true) {
  const low = 12, high = 88, rest = [0.5, 1.5, 3], move = 0.7, hold = 0.5;
  let clock = 0, last = 0;
  const point = (p) => {
    const s = ((p % 4) + 4) % 4, side = Math.floor(s), f = s - side, len = high - low;
    return [[low + len * f, low], [high, low + len * f], [high - len * f, high], [low, high - len * f]][side];
  };
  const ease = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
  return (t) => {
    const dt = t - last; last = t;
    // Idle, it finishes the turn in progress and skips the rest, so the next hover turns at once.
    const period = move + hold, phase = clock % period;
    if (active()) clock += dt;
    else if (phase > 0) clock = phase + dt < move ? clock + dt : clock - phase + period;
    const step = Math.floor(clock / (move + hold));
    const turn = step + ease(Math.min(1, (clock - step * (move + hold)) / move));
    rays.setAttribute("d", rest.map((r) => {
      const [x, y] = point(r + turn);
      return `M50 50L${x.toFixed(2)} ${y.toFixed(2)}`;
    }).join(""));
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
  animate(host, cubeFrame(host.querySelector("path")));
}

// Wave: wave.svg's six lobes; a sine pulse runs left to right through them (32% swell, 1.6 s per
// crossing), easing in from and back out to the resting line over 0.4 s, like WaveMark.
function waveFrame(path, active) {
  const base = 7.9, lobes = [
    [16, 6, 11, -1.3], [31, 20.5109, 25.5109, 15.3], [46, 36, 41, 0.5],
    [61, 51.2703, 56.2703, 16.1], [76, 66, 71, -0.3], [91, 80.6341, 85.6341, 14.9],
  ];
  const smooth = (x) => x * x * (3 - 2 * x);
  let level = 0, last = 0;
  return (t) => {
    const dt = t - last; last = t;
    level = Math.min(1, Math.max(0, level + (active() ? dt : -dt) / 0.4));
    const strength = 0.32 * smooth(level);
    path.setAttribute("d", `M1 ${base}` + lobes.map(([end, c1, c2, y], i) => {
      const cy = (base + (y - base) * (1 + strength * Math.sin(2 * Math.PI * (t / 1.6) - i * 0.75))).toFixed(2);
      return `C${c1} ${cy} ${c2} ${cy} ${end} ${base}`;
    }).join(""));
  };
}
