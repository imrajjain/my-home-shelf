// A public Shelf profile: /u/<username>. Shows only what that person shares
// with everyone; the API never returns anything else to this page.
const API = "https://shelfraj-api.azurewebsites.net";

const KINDS = [
  ["book", "Books"], ["film", "Films"], ["show", "Shows"], ["paper", "Papers"], ["article", "Articles & Blogs"],
  ["video", "Videos"], ["podcast", "Podcasts"], ["music", "Music"], ["place", "Places"], ["curiosity", "Curiosities"],
];
const SHAPE = { film: "", show: "wide", video: "wide", article: "wide", place: "wide", podcast: "square", music: "square" };

const page = document.getElementById("page");

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null) continue;
    if (k === "class") node.className = v; else node.setAttribute(k, v);
  }
  for (const child of children.flat()) node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  return node;
}

function initials(name) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join("") || "?";
}

function safeURL(value) {
  try { const u = new URL(value); return u.protocol === "https:" || u.protocol === "http:" ? u.href : null; } catch { return null; }
}

function card(item) {
  const image = safeURL(item.imageURL);
  const cover = el("div", { class: `cover ${SHAPE[item.kind] ?? ""}` },
    image ? el("img", { src: image, alt: "", loading: "lazy", referrerpolicy: "no-referrer" }) : el("div", { class: "typeset" }, item.title),
    item.status === "done" ? el("span", { class: "done", title: "Finished" }, "✓") : "");
  const by = [item.creator, item.year].filter(Boolean).join(" · ");
  const link = safeURL(item.url);
  return el(link ? "a" : "div", { class: "card", href: link, target: link ? "_blank" : null, rel: link ? "noopener" : null },
    cover, el("div", { class: "title" }, item.title), by ? el("div", { class: "by" }, by) : "");
}

function render({ profile, items }) {
  document.title = `${profile.displayName} (@${profile.username}) · Shelf`;
  page.replaceChildren(
    el("div", { class: "person" },
      el("div", { class: "avatar" }, initials(profile.displayName)),
      el("div", { class: "who" },
        el("h1", {}, profile.displayName),
        el("div", { class: "handle" }, `@${profile.username}`),
        profile.bio ? el("p", { class: "bio" }, profile.bio) : ""),
      el("div", { class: "actions" },
        el("a", { class: "pill primary", href: `shelf://u/${encodeURIComponent(profile.username)}` }, "Open in Shelf"),
        el("a", { class: "pill secondary", href: "/" }, "Get Shelf"))),
    ...(items.length === 0
      ? [el("p", { class: "empty" }, `${profile.displayName} hasn't shared anything with everyone yet.`)]
      : KINDS.map(([kind, title]) => {
          const list = items.filter((i) => i.kind === kind);
          if (!list.length) return "";
          return el("section", {}, el("h2", {}, title, el("small", {}, String(list.length))), el("div", { class: "grid" }, list.map(card)));
        })),
    el("footer", {}, "Shared from ", el("a", { href: "/" }, "Shelf"), ". Only what they share with everyone appears here."));
}

async function load() {
  const name = decodeURIComponent(location.pathname.split("/")[2] ?? "").toLowerCase();
  if (!/^[a-z0-9_]{3,20}$/.test(name)) {
    page.replaceChildren(el("p", { class: "note" }, "That isn't a Shelf username."));
    return;
  }
  try {
    const response = await fetch(`${API}/public/${name}`);
    if (response.status === 404) {
      page.replaceChildren(el("p", { class: "note" }, `No one on Shelf goes by @${name}.`));
      return;
    }
    if (!response.ok) throw new Error(String(response.status));
    render(await response.json());
  } catch {
    page.replaceChildren(el("p", { class: "note" }, "Couldn't open this shelf just now. Try again in a moment."));
  }
}

load();
