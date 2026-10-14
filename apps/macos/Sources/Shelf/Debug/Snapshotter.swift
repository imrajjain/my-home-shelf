import AppKit
import SwiftUI
import SwiftData
import ShelfCore

/// Renders the main window in a series of states to PNGs, invisibly, then
/// quits. A design aid that needs no screen-recording permission:
///
///     SHELF_STORE_DIR=/tmp/copy SHELF_SNAPSHOT=/tmp/shots Shelf.app/Contents/MacOS/Shelf
///
/// Optional SHELF_SNAPSHOT_ONLY=home,books limits which states render.
@MainActor
enum Snapshotter {
    struct Shot {
        let name: String
        let setup: (Router, [Item]) -> Void
    }

    static let shots: [Shot] = [
        Shot(name: "home") { r, _ in r.selection = .home; r.showingInspector = false },
        Shot(name: "home-detail") { r, items in
            r.selection = .home
            if let item = items.first(where: { $0.kind == .film }) ?? items.first { r.open(item) }
        },
        Shot(name: "books") { r, _ in r.selection = .kind(.book); r.showingInspector = false },
        Shot(name: "films-detail") { r, items in
            r.selection = .kind(.film)
            if let item = items.first(where: { $0.kind == .film }) { r.open(item) }
        },
        Shot(name: "papers") { r, _ in r.selection = .kind(.paper); r.showingInspector = false },
        Shot(name: "upnext") { r, _ in r.selection = .status(.want); r.showingInspector = false },
        Shot(name: "empty-shelf") { r, _ in r.selection = .kind(.place); r.showingInspector = false },
        Shot(name: "capture") { r, _ in r.selection = .home; r.showingInspector = false; r.showingCapture = true },
    ]

    static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let only = ProcessInfo.processInfo.environment["SHELF_SNAPSHOT_ONLY"].flatMap { $0.isEmpty ? nil : $0 }.map { Set($0.split(separator: ",").map(String.init)) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.frame.width > 400 }) else {
                NSLog("Snapshotter: no window"); NSApp.terminate(nil); return
            }
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.setContentSize(NSSize(width: 1240, height: 820))

            // SHELF_SNAPSHOT_SYNC=1 runs a Goodreads sync on the (copied) store first.
            if ProcessInfo.processInfo.environment["SHELF_SNAPSHOT_SYNC"] == "1" {
                await GoodreadsSync.shared.sync()
                NSLog("Snapshotter: sync state \(String(describing: GoodreadsSync.shared.state))")
            }
            // SHELF_SNAPSHOT_ONLY=art renders every backdrop style side by side.
            if only?.contains("art") == true { renderArtGallery(into: dir) }
            let items = (try? Persistence.context.fetch(FetchDescriptor<Item>(
                predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            ))) ?? []
            let router = Router.shared
            for appearance in [NSAppearance.Name.darkAqua, .aqua] {
                NSApp.appearance = NSAppearance(named: appearance)
                for shot in shots where only?.contains(shot.name) ?? true {
                    router.showingCapture = false
                    shot.setup(router, items)
                    try? await Task.sleep(for: .milliseconds(1200))
                    let suffix = appearance == .darkAqua ? "dark" : "light"
                    capture(window, to: dir.appending(path: "\(shot.name)-\(suffix).png"))
                    if router.showingCapture, let sheet = window.attachedSheet {
                        capture(sheet, to: dir.appending(path: "\(shot.name)-sheet-\(suffix).png"))
                    }
                }
            }
            NSApp.terminate(nil)
        }
    }

    private static func renderArtGallery(into dir: URL) {
        for scheme in [ColorScheme.dark, .light] {
            let gallery = LazyVGrid(columns: Array(repeating: GridItem(.fixed(420), spacing: 12), count: 3), spacing: 12) {
                ForEach(BackdropArt.allCases) { art in
                    ZStack(alignment: .bottomLeading) {
                        Color(nsColor: .textBackgroundColor)
                        BackdropArtLayer(art: art)
                        Text(art.title).font(.system(size: 13, weight: .semibold)).padding(10)
                    }
                    .frame(width: 420, height: 300)
                }
            }
            .padding(12)
            .background(Color.black)
            .environment(\.colorScheme, scheme)
            NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let renderer = ImageRenderer(content: gallery)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appending(path: "art-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    private static func capture(_ window: NSWindow, to url: URL) {
        // The theme frame includes the toolbar and window chrome.
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
