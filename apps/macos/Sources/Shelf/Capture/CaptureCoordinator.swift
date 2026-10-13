import Foundation
import SwiftData
import ShelfCore

/// The single path by which things land on the shelf, wherever they come
/// from. Items appear *immediately*; metadata and covers arrive after.
@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private var context: ModelContext { Persistence.context }

    /// From a link/selection (browser extension, URL scheme, Services, paste).
    @discardableResult
    func add(_ request: CaptureRequest) -> Item? {
        guard !request.isEmpty else { return nil }

        if let url = request.url, let existing = item(matching: url) {
            // Already on the shelf: respect the new intent instead of duplicating.
            if let status = request.status { existing.status = status }
            appendNotes(request, to: existing)
            existing.touch()
            try? context.save()
            return existing
        }

        let kind = request.kind ?? request.url.map(LinkClassifier.kind(for:)) ?? .curiosity
        let fallbackTitle = request.url.map { MetadataService.fallback(for: $0, kind: kind).title } ?? "Untitled"
        let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? request.url.flatMap(LinkClassifier.googleSearchQuery)
            ?? (request.selection.map { String($0.prefix(80)) })
            ?? fallbackTitle

        let item = Item(kind: kind, status: request.status ?? .want, title: title)
        item.url = request.url
        item.tags = request.tags ?? []
        appendNotes(request, to: item)
        context.insert(item)
        try? context.save()

        if let url = request.url {
            enrich(item, from: url, hint: request.kind, keepTitle: false)
        } else if kind == .curiosity {
            enrichCuriosity(item)
        }
        return item
    }

    /// From a search result the user picked: already rich, just fetch art.
    @discardableResult
    func add(_ m: Metadata, status: ItemStatus, note: String? = nil) -> Item {
        if let url = m.url, let existing = item(matching: url) {
            existing.status = status
            try? context.save()
            return existing
        }
        let item = Item(kind: m.kind, status: status, title: m.title)
        item.apply(m, overwriteTitle: true)
        if let note, !note.isEmpty { item.notes = note }
        context.insert(item)
        try? context.save()
        cacheCover(for: item)
        return item
    }

    /// Re-fetch metadata for an existing item (detail view → "Refresh").
    func refresh(_ item: Item) {
        guard let url = item.url else {
            if item.kind == .curiosity { enrichCuriosity(item) }
            return
        }
        item.imageURLString = nil
        item.imageData = nil
        enrich(item, from: url, hint: item.kind, keepTitle: false, force: true)
    }

    // MARK: - Enrichment

    private func enrich(_ item: Item, from url: URL, hint: ItemKind?, keepTitle: Bool, force: Bool = false) {
        item.isEnriching = true
        let service = AppSettings.metadata
        Task { @MainActor in
            let m = await service.resolve(url, hint: hint)
            if hint == nil { item.kindRaw = m.kind.rawValue }
            if force {
                item.summary = nil; item.creator = nil; item.year = nil; item.subtitle = nil
            }
            // A fetch that failed yields a slug-derived title; the page title we
            // were handed (if any) is better than that.
            let isFallback = m.title == MetadataService.fallback(for: url, kind: m.kind).title
            item.apply(m, overwriteTitle: !keepTitle && !isFallback)
            item.isEnriching = false
            try? context.save()
            cacheCover(for: item)
        }
    }

    private func enrichCuriosity(_ item: Item) {
        item.isEnriching = true
        let query = item.title
        Task { @MainActor in
            if let wiki = try? await WikipediaProvider().summary(title: query) {
                item.subtitle = item.subtitle ?? wiki.subtitle
                item.summary = item.summary ?? wiki.summary
                item.imageURLString = item.imageURLString ?? wiki.imageURL?.absoluteString
                if item.url == nil { item.urlString = wiki.url?.absoluteString }
            }
            item.isEnriching = false
            try? context.save()
            cacheCover(for: item)
        }
    }

    private func cacheCover(for item: Item) {
        guard item.imageData == nil else { return }
        Task { @MainActor in
            if let url = item.imageURL {
                item.imageData = await ImageCache.download(url)
            } else if item.kind == .place,
                      let lat = item.extra["latitude"].flatMap(Double.init),
                      let lon = item.extra["longitude"].flatMap(Double.init) {
                item.imageData = await MapCover.snapshot(latitude: lat, longitude: lon)
            }
            try? context.save()
        }
    }

    // MARK: - Helpers

    private func appendNotes(_ request: CaptureRequest, to item: Item) {
        var blocks: [String] = []
        if let selection = request.selection?.trimmingCharacters(in: .whitespacesAndNewlines), !selection.isEmpty {
            blocks.append(selection.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n"))
        }
        if let note = request.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            blocks.append(note)
        }
        guard !blocks.isEmpty else { return }
        let addition = blocks.joined(separator: "\n\n")
        guard !item.notes.contains(addition) else { return }
        item.notes = item.notes.isEmpty ? addition : item.notes + "\n\n" + addition
    }

    private func item(matching url: URL) -> Item? {
        let target = Self.normalize(url)
        let candidates = (try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        return candidates.first { $0.url.map(Self.normalize) == target }
    }

    /// Ignore tracking params, fragments and trailing slashes when deduping.
    static func normalize(_ url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        c.fragment = nil
        c.scheme = "https"
        c.host = c.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        c.queryItems = c.queryItems?.filter { item in
            !item.name.hasPrefix("utm_") && !["ref", "fbclid", "gclid", "si", "source"].contains(item.name)
        }
        if c.queryItems?.isEmpty == true { c.queryItems = nil }
        var s = c.string ?? url.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
