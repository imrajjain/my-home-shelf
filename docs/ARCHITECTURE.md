# Architecture

## Layout

```
apps/macos/
  Package.swift
  Sources/
    ShelfCore/          Pure Foundation. No AppKit/SwiftUI. Portable & tested.
      Model/            ItemKind, ItemStatus, ItemRecord + ShelfArchive (the sync contract)
      Metadata/         Providers, link classification, HTML/JSON-LD parsing, MetadataService
      Capture/          CaptureRequest (deep links, loose text), LocalAPI (HTTP parsing, tokens)
    Shelf/              The macOS app
      App/              ShelfApp (scenes, commands), AppDelegate, Router
      Model/            SwiftData `Item` (mirrors ItemRecord), Persistence
      Design/           Theme (palette, type, motion), CoverView, components
      Views/            Root, Sidebar, Home, Library, ItemCard/Row, ItemDetail, Settings
      Capture/          Hotkey, quick-capture panel, CaptureModel/View, LocalServer,
                        Services provider, frontmost-browser reader, CaptureCoordinator
      Services/         Settings, image cache, MapKit places, JSON archive
  Support/              Info.plist, Shelf.icon (Icon Composer)
  scripts/bundle.sh     Builds a signed .app from the package
extensions/browser/     Manifest V3 extension
```

`ShelfCore` stays free of Apple UI frameworks on purpose. It holds the
logic the web app and sync service will need to agree on: kinds, statuses,
the record schema, how links are classified, and what metadata looks like.

## How capture flows

```
 hotkey ─┐                                    ┌─ MetadataService.resolve(url)
 ⌘N ─────┤                                    │    ├─ specialised resolvers (arXiv, DOI, YouTube, Wikipedia)
 panel ──┼─▶ CaptureModel ─┐                  │    ├─ generic HTML: OpenGraph + JSON-LD + citation_* tags
         │                 ├─▶ CaptureCoordinator ─┤    └─ enrich: Open Library / Apple / TMDB by title
 ext. ───┼─▶ LocalServer ──┤   (insert now,   │
 shelf:// ┼─▶ AppDelegate ──┤    enrich after) └─ ImageCache.download / MapCover.snapshot
 Services ┘                └──────────────────────▶ SwiftData (Item)
```

Items are inserted **immediately** with whatever is known (URL, page title)
and show a shimmer while metadata and cover art arrive. Re-adding a URL
that's already on the shelf (after stripping `utm_*`, trailing slashes and
`www.`) updates the existing item instead of making a duplicate.

### Local API (browser extension)

- Listens on `127.0.0.1:47291` only (`acceptLocalOnly` + loopback interface).
- `GET /v1/ping`, `POST /v1/items` (body is `CaptureRequest` JSON).
- Every request needs `X-Shelf-Token`. The pairing code from Settings is
  compared in constant time.
- Requests that carry a web-page `Origin` are rejected, and no CORS headers
  are ever sent, so websites can't drive it. Extension service workers
  aren't subject to CORS, so the extension doesn't need them.

## Data model & the sync plan

`ItemRecord` (in `ShelfCore/Model/ItemRecord.swift`) is the contract:

| field | notes |
|---|---|
| `id` | UUID, generated on the device that created the item |
| `kind`, `status` | string enums, see `ItemKind` / `ItemStatus` |
| `title`, `subtitle`, `creator`, `year`, `summary` | display metadata |
| `url`, `imageURL` | canonical link and remote cover |
| `notes`, `rating` (0–5), `progress` (0–1), `isFavorite`, `tags` | yours |
| `provider`, `externalID`, `extra` | where metadata came from; kind-specific details (`pages`, `runtime`, `doi`, `arxiv`, `venue`, `pdf`, `latitude`, `longitude`, …) |
| `createdAt`, `updatedAt`, `startedAt`, `finishedAt` | ISO-8601 |
| `deletedAt` | tombstone: deletes are soft so they can propagate |

Cover image bytes are a local cache only and are never synced. Each client
re-downloads from `imageURL`.

**Planned sync (v0.2):**

- A small service (Postgres via Supabase, or Cloudflare D1 + Workers) with a
  table that mirrors `ItemRecord`.
- `GET /items?since=<cursor>` and `PUT /items` (batch upsert).
- Conflict rule: last writer wins per record on `updatedAt` (the same rule
  JSON import already uses). Tombstones are garbage-collected after 30 days.
- The web app (likely Next.js or SvelteKit) reuses the same palette,
  serif type and generated-cover design so the two feel like one product.
- The macOS app syncs in the background on launch, on change (debounced)
  and every few minutes.

## Design principles

- **Paper, not chrome.** Warm off-white and lamp-lit dark modes, hairline
  borders, layered soft shadows. Gray is used sparingly.
- **Type does the work.** New York serif for titles and moments, SF for UI,
  and small tracked-out eyebrows for structure.
- **Every kind has a voice.** Its own accent color, cover proportions and
  status verbs.
- **Never look broken.** Missing art gets a generated cover. A failed
  fetch still leaves a tidy item.
- **Fast first, rich later.** Capture is instant and enrichment is
  asynchronous.
- **Keyboard-first, mouse-friendly.** Every primary action has a shortcut,
  and every shortcut is taught somewhere in the UI.
