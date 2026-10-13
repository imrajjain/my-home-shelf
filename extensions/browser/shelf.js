// Talks to the Shelf app's localhost API, falling back to the shelf://
// URL scheme if the app isn't reachable (it'll ask "Open Shelf?" once).

export const PORT = 47291;
const BASE = `http://127.0.0.1:${PORT}/v1`;

export async function getToken() {
  const { token } = await chrome.storage.local.get("token");
  return (token || "").trim();
}

export async function ping(token) {
  token ??= await getToken();
  try {
    const res = await fetch(`${BASE}/ping`, { headers: { "X-Shelf-Token": token } });
    if (res.status === 401) return { ok: false, reason: "unpaired" };
    return { ok: res.ok, reason: res.ok ? null : "error" };
  } catch {
    return { ok: false, reason: "offline" };
  }
}

/**
 * @param {{url?: string, title?: string, selection?: string, note?: string,
 *          kind?: string, status?: string, tags?: string[]}} capture
 * @returns {Promise<{ok: boolean, via: "api"|"scheme", item?: object, error?: string}>}
 */
export async function addToShelf(capture) {
  const body = JSON.stringify(clean(capture));
  const token = await getToken();
  if (token) {
    try {
      const res = await fetch(`${BASE}/items`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Shelf-Token": token },
        body,
      });
      const json = await res.json().catch(() => ({}));
      if (res.ok) return { ok: true, via: "api", item: json };
      if (res.status === 401) return { ok: false, via: "api", error: "unpaired" };
      return { ok: false, via: "api", error: json.error || `HTTP ${res.status}` };
    } catch {
      // App not running or API disabled — fall through to the URL scheme.
    }
  }
  await openScheme(capture);
  return { ok: true, via: "scheme" };
}

export function schemeURL(capture) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(clean(capture))) {
    params.set(key, Array.isArray(value) ? value.join(",") : value);
  }
  return `shelf://add?${params.toString()}`;
}

async function openScheme(capture) {
  // Open in a throwaway tab: the browser hands the URL to macOS, then we
  // tidy up so no blank tab is left behind.
  const tab = await chrome.tabs.create({ url: schemeURL(capture), active: false });
  setTimeout(() => chrome.tabs.remove(tab.id).catch(() => {}), 1500);
}

function clean(capture) {
  const out = {};
  for (const [key, value] of Object.entries(capture)) {
    if (value === undefined || value === null) continue;
    if (typeof value === "string" && value.trim() === "") continue;
    if (Array.isArray(value) && value.length === 0) continue;
    out[key] = typeof value === "string" ? value.trim().slice(0, 20000) : value;
  }
  return out;
}

/** Guesses what a page is, purely for the popup's label. The app decides for real. */
export function guessKind(url) {
  let u;
  try { u = new URL(url); } catch { return "article"; }
  const host = u.hostname.replace(/^www\./, "");
  const path = u.pathname.toLowerCase();
  const on = (...domains) => domains.some((d) => host === d || host.endsWith("." + d));
  if ((on("google.com") || host.startsWith("google.")) && path === "/search") return "curiosity";
  if (on("goodreads.com", "openlibrary.org", "thestorygraph.com", "bookshop.org")) return "book";
  if (on("letterboxd.com") && path.includes("/film/")) return "film";
  if (on("imdb.com") && path.startsWith("/title")) return "film";
  if (on("themoviedb.org")) return path.startsWith("/tv") ? "show" : "film";
  if (on("arxiv.org", "doi.org", "semanticscholar.org", "openreview.net", "aclanthology.org", "biorxiv.org", "ssrn.com", "dl.acm.org") || path.endsWith(".pdf")) return "paper";
  if (on("youtube.com", "youtu.be", "vimeo.com")) return "video";
  if (on("podcasts.apple.com", "overcast.fm", "pocketcasts.com")) return "podcast";
  if (on("music.apple.com", "bandcamp.com", "soundcloud.com")) return "music";
  if (on("maps.apple.com", "maps.app.goo.gl") || (on("google.com") && path.startsWith("/maps"))) return "place";
  if (on("wikipedia.org")) return "curiosity";
  return "article";
}

export const KINDS = {
  book:      { label: "Book",      verbs: ["Want to read", "Reading", "Read"],         color: "#C4643F" },
  film:      { label: "Film",      verbs: ["Want to watch", "Watching", "Watched"],    color: "#8E4A6B" },
  show:      { label: "Show",      verbs: ["Want to watch", "Watching", "Watched"],    color: "#4F5BA6" },
  paper:     { label: "Paper",     verbs: ["Want to read", "Reading", "Read"],         color: "#5E8A6E" },
  article:   { label: "Article",   verbs: ["Want to read", "Reading", "Read"],         color: "#C48A2C" },
  video:     { label: "Video",     verbs: ["Want to watch", "Watching", "Watched"],    color: "#C2493F" },
  podcast:   { label: "Podcast",   verbs: ["Want to listen", "Listening", "Listened"], color: "#7A5BB0" },
  music:     { label: "Music",     verbs: ["Want to listen", "Listening", "Listened"], color: "#2F8C8C" },
  place:     { label: "Place",     verbs: ["Want to go", "Planning", "Been there"],    color: "#3F7FA6" },
  curiosity: { label: "Curiosity", verbs: ["Want to explore", "Exploring", "Explored"], color: "#C2577E" },
};
export const STATUSES = ["want", "inProgress", "done"];
