import { ping, getToken } from "./shelf.js";

const input = document.getElementById("token");
const result = document.getElementById("result");

input.value = await getToken();

document.getElementById("save").addEventListener("click", save);
input.addEventListener("keydown", (e) => { if (e.key === "Enter") save(); });

async function save() {
  const token = input.value.trim();
  await chrome.storage.local.set({ token });
  result.textContent = "Checking…";
  const status = await ping(token);
  result.style.color = status.ok ? "#5E8A6E" : "#C2493F";
  result.textContent = status.ok
    ? "✓ Paired. You’re all set."
    : status.reason === "unpaired"
      ? "That code doesn’t match — copy it again from Shelf’s settings."
      : "Couldn’t reach Shelf. Is the app running?";
}
