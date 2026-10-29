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
