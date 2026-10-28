// Landing page: copy buttons, the username box, and a banknote that tilts
// as you scroll past and lean toward the pointer, like the app's stage.

for (const button of document.querySelectorAll("[data-copy]")) {
  button.addEventListener("click", async () => {
    const text = button.parentElement.querySelector("code").textContent;
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = "Copied";
      setTimeout(() => (button.textContent = "Copy"), 1600);
    } catch {
      button.textContent = "Select ▸ ⌘C";
    }
  });
}

document.getElementById("find").addEventListener("submit", (event) => {
  event.preventDefault();
  const name = document.getElementById("name").value.trim().replace(/^@/, "").toLowerCase();
  if (/^[a-z0-9_]{3,20}$/.test(name)) location.href = `/u/${name}`;
});

const note = document.getElementById("note");
const stage = note?.parentElement;
const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
if (note && stage && !still) {
  let lean = 0, pitch = 0;
  const paint = () => {
    const box = stage.getBoundingClientRect();
    // -1 above the fold … 1 past it: the note turns gently as it scrolls by.
    const travel = Math.max(-1, Math.min(1, (box.top + box.height / 2 - innerHeight / 2) / innerHeight));
    note.style.transform = `rotateY(${travel * -18 + lean}deg) rotateX(${8 + pitch}deg)`;
  };
  addEventListener("scroll", paint, { passive: true });
  stage.addEventListener("pointermove", (e) => {
    const box = stage.getBoundingClientRect();
    lean = ((e.clientX - box.left) / box.width - 0.5) * 16;
    pitch = -((e.clientY - box.top) / box.height - 0.5) * 8;
    paint();
  });
  stage.addEventListener("pointerleave", () => { lean = 0; pitch = 0; paint(); });
  paint();
}
