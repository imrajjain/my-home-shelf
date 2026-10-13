import { addToShelf, ping, guessKind, KINDS, STATUSES } from "./shelf.js";

const $ = (id) => document.getElementById(id);
const state = { url: "", kind: "article", kindTouched: false, status: "want", image: null, selection: undefined };

init();

async function init() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  state.url = tab?.url || "";
  $("title").value = tab?.title || "";
  try { $("host").textContent = new URL(state.url).hostname.replace(/^www\./, ""); } catch {}
  state.kind = guessKind(state.url);

  renderKinds();
  renderStatus();
  applyTint();

  // Grab the page's preview image and any selected text.
  if (tab?.id !== undefined && state.url.startsWith("http")) {
    try {
      const [{ result }] = await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => {
          const meta = (p) => document.querySelector(`meta[property="${p}"], meta[name="${p}"]`)?.content;
          return {
            image: meta("og:image") || meta("twitter:image"),
            title: meta("og:title"),
            selection: String(window.getSelection() || "").trim(),
          };
        },
      });
      if (result?.image) {
        state.image = new URL(result.image, state.url).href;
        $("cover").style.backgroundImage = `url("${state.image.replace(/"/g, "%22")}")`;
        $("cover-fallback").textContent = "";
      }
      if (result?.title && result.title.length < ($("title").value || "").length) $("title").value = result.title;
      if (result?.selection) {
        state.selection = result.selection;
        $("note").placeholder = `“${result.selection.slice(0, 60)}${result.selection.length > 60 ? "…" : ""}” will be saved as a quote`;
      }
    } catch { /* restricted page */ }
  }
  if (!state.image) $("cover-fallback").textContent = ($("title").value || "?").trim().charAt(0).toUpperCase();

  const status = await ping();
  setConnection(status);

  $("add").addEventListener("click", () => submit());
  document.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey && (e.target.id !== "note" || e.metaKey)) {
      e.preventDefault();
      submit(e.metaKey ? "done" : undefined);
    }
  });
  $("settings").addEventListener("click", (e) => { e.preventDefault(); chrome.runtime.openOptionsPage(); });
  $("title").focus();
  $("title").select();
}

function renderKinds() {
  const box = $("kinds");
  box.replaceChildren();
  for (const [key, info] of Object.entries(KINDS)) {
    const b = document.createElement("button");
    b.className = "chip";
    b.textContent = info.label;
    b.setAttribute("role", "radio");
    b.setAttribute("aria-checked", String(key === state.kind));
    b.addEventListener("click", () => {
      state.kind = key;
      state.kindTouched = true;
      renderKinds();
      renderStatus();
      applyTint();
    });
    box.append(b);
  }
}

function renderStatus() {
  const box = $("status");
  box.replaceChildren();
  KINDS[state.kind].verbs.forEach((verb, i) => {
    const key = STATUSES[i];
    const b = document.createElement("button");
    b.textContent = verb;
    b.setAttribute("role", "radio");
    b.setAttribute("aria-checked", String(key === state.status));
    b.addEventListener("click", () => { state.status = key; renderStatus(); });
    box.append(b);
  });
}

function applyTint() {
  const info = KINDS[state.kind];
  document.documentElement.style.setProperty("--tint", info.color);
  $("kind-label").textContent = info.label;
}

function setConnection({ ok, reason }) {
  const dot = $("dot");
  dot.className = "dot " + (ok ? "ok" : "warn");
  $("connection").textContent = ok
    ? "Connected to Shelf"
    : reason === "unpaired" ? "Not paired — open Settings" : "Shelf isn’t running — will open it";
}

async function submit(statusOverride) {
  const button = $("add");
  button.disabled = true;
  const status = statusOverride || state.status;
  const result = await addToShelf({
    url: state.url,
    title: $("title").value,
    note: $("note").value,
    selection: state.selection,
    kind: state.kindTouched ? state.kind : undefined,
    status,
  });
  if (!result.ok) {
    button.disabled = false;
    setConnection({ ok: false, reason: result.error });
    if (result.error === "unpaired") chrome.runtime.openOptionsPage();
    return;
  }
  const kindLabel = KINDS[result.item?.kind || state.kind]?.label || "";
  $("app").hidden = true;
  $("done").hidden = false;
  $("done-sub").textContent = result.via === "api"
    ? `${kindLabel} · ${KINDS[state.kind].verbs[STATUSES.indexOf(status)]}`
    : "Handing it to the Shelf app…";
  setTimeout(() => window.close(), 1100);
}
