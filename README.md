# Shelf

*An index of everything you're curious about — beautifully kept.*

Shelf is a native macOS app for the books you want to read, the films and
shows you want to watch, the papers and essays on your reading table, the
places you want to go and the things you Googled at 1am. It holds both
what you want to get to and what you've already finished. It's meant to be
a small happy place: warm paper, editorial serif type, real covers, and
smooth motion.

```
apps/macos/          Native SwiftUI app (Swift package) + ShelfCore library
extensions/browser/  "Add to Shelf" browser extension (Chrome, Arc, Brave, Edge)
docs/                Architecture, data format and the web/sync roadmap
```

## What's in v0.1

**Ten shelves.** Books · Films · Shows · Papers · Articles & Blogs · Videos ·
Podcasts · Music · Places · Curiosities. Each one uses its own verbs ("Want
to read · Reading · Read", "Want to go · Planning · Been there") and its
own accent color.

**Real metadata, no setup.**

| Source | Gives you |
|---|---|
| Open Library, Google Books | Book covers, authors, page counts, descriptions |
| Wikipedia, TVmaze | Films and shows, with posters |
| Apple (iTunes Search) | Podcasts, albums |
| TMDB *(optional free key)* | Richer film & TV results |
| arXiv, Crossref | Papers: authors, abstracts, venues, DOIs, PDF links |
| Wikipedia | Curiosities and anything else: summaries and images |
| Apple Maps | Places, with a generated map-tile cover |
| Any web page | Goodreads, Letterboxd, IMDb, Substack, Medium… via OpenGraph, JSON-LD and Highwire citation tags |

A Google search URL becomes a curiosity titled with your query. When an
item has no art, Shelf typesets a cover for it, so nothing looks broken.

**Capture from anywhere.**

- **⇧⌘Space** (configurable) opens a Spotlight-style panel over any app.
  If you're in Safari, Chrome, Arc, Brave, Edge or Vivaldi, the current tab
  is already offered. Type to search catalogues, or paste a link. **↩** adds
  it, **⌘↩** adds it as finished, **⇥** switches shelf.
- **Browser extension:** the toolbar popup or **⌥⇧S** to review before
  adding, **⌥⇧A** to add instantly. Right-click menus work for pages,
  links and selected text. The extension talks to the app over a paired,
  localhost-only API, so adding is silent.
- **Services menu:** select text in any app → right-click → Services →
  *Add to Shelf*.
- **URL scheme:** `shelf://add?url=…&title=…&kind=book&status=done`, for
  Shortcuts, Raycast and Alfred.
- **⌘N** in the app.

**The app.** Home has a greeting, *Continue*, *Up next*, the reading table,
your year in numbers, *Recently finished* and a rediscovered favorite from
the archive. The library has grid and list views with status filters,
sorting and search. The inspector holds ratings, favorites, progress,
notes, tags and a map for places. Everything saves as you go. It's
keyboard-friendly throughout (⌘1–5, ⌘⌥1–9, ⌘⌥I, ⌫), and there's a
menu-bar item.

**Your data.** It's stored locally with SwiftData in `~/Library/Application
Support/Shelf`. JSON export and import use the same format the web app will
sync, so nothing is locked in.

## Run it

Requires macOS 14+ and Xcode 15.3+ (or a Swift 5.10+ toolchain with the macOS SDK).

```sh
cd apps/macos
swift run Shelf              # quickest: runs unbundled (no URL scheme/Services)
./scripts/bundle.sh          # builds dist/Shelf.app (icon, URL scheme, Services)
./scripts/bundle.sh --install  # …and installs to /Applications and launches it
swift test                   # ShelfCore unit tests
```

You can also open `apps/macos/Package.swift` in Xcode and press ⌘R.

> If you use swiftly or a swift.org toolchain, prefix commands with `xcrun`
> (`xcrun swift build`). Only Xcode's toolchain has the SwiftData/SwiftUI
> macros and MapKit overlays the app needs; `bundle.sh` does this for you.

> The first time you use quick capture from a browser, macOS asks whether
> Shelf may control that browser. That's how it reads the current tab.

### Browser extension

1. Open `chrome://extensions` (or `arc://extensions`, etc.), turn on
   **Developer mode**, click **Load unpacked** and pick `extensions/browser`.
2. Shelf → Settings (⌘,) → Capture → copy the **pairing code**, then paste
   it into the extension's settings page (it opens on install).

If Shelf isn't running, the extension falls back to the `shelf://` URL
scheme, which launches the app.

## Roadmap

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The short version:

1. **Now:** a native app with a local store and capture everywhere.
2. **Next:** a sync service and a web app that mirrors the shelf (same
   `ItemRecord` schema, last-writer-wins on `updatedAt`, tombstones for
   deletes), plus import from Goodreads and Letterboxd CSV exports.
3. **Later:** an iOS share sheet, Safari Web Extension packaging, smart
   "what should I watch tonight" picks, and reading-time estimates for papers.
