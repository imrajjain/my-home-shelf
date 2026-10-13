import AppKit
import SwiftData
import UniformTypeIdentifiers
import ShelfCore

/// JSON export/import in the portable `ShelfArchive` format.
@MainActor
enum ArchiveService {
    static func exportWithPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Shelf \(Date.now.formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try export(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try importArchive(from: url)
            let alert = NSAlert()
            alert.messageText = "Imported \(count) item\(count == 1 ? "" : "s")"
            alert.informativeText = "Newer versions of items you already had were kept."
            alert.runModal()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func export(to url: URL) throws {
        let items = try Persistence.context.fetch(FetchDescriptor<Item>())
        let archive = ShelfArchive(items: items.map(\.record))
        try ShelfArchive.encoder.encode(archive).write(to: url, options: .atomic)
    }

    /// Merges by id with last-writer-wins on `updatedAt` — the same rule
    /// the sync service will use.
    @discardableResult
    static func importArchive(from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let archive = try ShelfArchive.decoder.decode(ShelfArchive.self, from: data)
        let context = Persistence.context
        let existing = try context.fetch(FetchDescriptor<Item>())
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = 0
        for record in archive.items {
            if let item = byID[record.id] {
                guard record.updatedAt > item.updatedAt else { continue }
                item.update(from: record)
                item.imageData = nil
            } else {
                context.insert(Item(record: record))
            }
            changed += 1
        }
        try context.save()
        // Re-fetch covers in the background.
        Task { @MainActor in
            let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
            for item in items where item.imageData == nil {
                if let url = item.imageURL { item.imageData = await ImageCache.download(url) }
            }
            try? context.save()
        }
        return changed
    }
}
