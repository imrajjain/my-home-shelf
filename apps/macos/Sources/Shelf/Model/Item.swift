import Foundation
import SwiftData
import ShelfCore

/// A thing on the shelf. Stored locally with SwiftData; every field maps
/// 1:1 onto `ItemRecord` so it can be exported and, later, synced.
@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var statusRaw: String
    var title: String
    var subtitle: String?
    var creator: String?
    var year: Int?
    var summary: String?
    var notes: String
    var urlString: String?
    var imageURLString: String?
    /// Cover art, cached locally so the shelf is instant and works offline.
    @Attribute(.externalStorage) var imageData: Data?
    var rating: Int
    var progress: Double
    var isFavorite: Bool
    var tags: [String]
    var provider: String?
    var externalID: String?
    var extra: [String: String]
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var deletedAt: Date?
    /// True while metadata is still being fetched in the background.
    var isEnriching: Bool

    init(kind: ItemKind, status: ItemStatus = .want, title: String) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.title = title
        self.notes = ""
        self.rating = 0
        self.progress = 0
        self.isFavorite = false
        self.tags = []
        self.extra = [:]
        self.createdAt = .now
        self.updatedAt = .now
        self.isEnriching = false
        if status == .done { finishedAt = .now }
        if status == .inProgress { startedAt = .now }
    }

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .article }
        set { kindRaw = newValue.rawValue; touch() }
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .want }
        set {
            guard newValue.rawValue != statusRaw else { return }
            let wasDone = statusRaw == ItemStatus.done.rawValue
            statusRaw = newValue.rawValue
            switch newValue {
            case .inProgress:
                // Starting (or starting again after finishing) begins at 0%.
                if wasDone || progress >= 1 {
                    progress = 0
                    startedAt = .now
                    finishedAt = nil
                }
                startedAt = startedAt ?? .now
            case .done:
                finishedAt = .now; startedAt = startedAt ?? finishedAt; progress = 1
            case .want:
                finishedAt = nil; startedAt = nil; progress = 0
            case .dropped:
                break
            }
            touch()
        }
    }

    var url: URL? {
        get { urlString.flatMap(URL.init(string:)) }
        set { urlString = newValue?.absoluteString; touch() }
    }

    var imageURL: URL? {
        get { imageURLString.flatMap(URL.init(string:)) }
        set { imageURLString = newValue?.absoluteString }
    }

    var statusLabel: String { kind.label(for: status) }

    var byline: String {
        var parts: [String] = []
        if let creator, !creator.isEmpty { parts.append(creator) }
        if let year { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }

    var host: String? {
        guard let host = url?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func touch() { updatedAt = .now }

    /// Applies fetched metadata without clobbering anything the user typed.
    func apply(_ m: Metadata, overwriteTitle: Bool = false) {
        if overwriteTitle || title.isEmpty { title = m.title }
        subtitle = subtitle ?? m.subtitle
        creator = creator ?? m.creator
        year = year ?? m.year
        summary = summary ?? m.summary
        if urlString == nil { urlString = m.url?.absoluteString }
        if imageURLString == nil { imageURLString = m.imageURL?.absoluteString }
        provider = provider ?? m.provider
        externalID = externalID ?? m.externalID
        if tags.isEmpty { tags = m.tags.map { $0.lowercased() } }
        extra.merge(m.extra) { mine, _ in mine }
        touch()
    }
}

// MARK: - Records

extension Item {
    var record: ItemRecord {
        ItemRecord(
            id: id, kind: kind, status: status, title: title, subtitle: subtitle, creator: creator,
            year: year, summary: summary, notes: notes, url: url, imageURL: imageURL, rating: rating,
            progress: progress, isFavorite: isFavorite, tags: tags, provider: provider,
            externalID: externalID, extra: extra, createdAt: createdAt, updatedAt: updatedAt,
            startedAt: startedAt, finishedAt: finishedAt, deletedAt: deletedAt
        )
    }

    convenience init(record r: ItemRecord) {
        self.init(kind: r.kind, status: r.status, title: r.title)
        id = r.id
        update(from: r)
    }

    func update(from r: ItemRecord) {
        kindRaw = r.kind.rawValue; statusRaw = r.status.rawValue; title = r.title
        subtitle = r.subtitle; creator = r.creator; year = r.year; summary = r.summary; notes = r.notes
        urlString = r.url?.absoluteString; imageURLString = r.imageURL?.absoluteString
        rating = r.rating; progress = r.progress; isFavorite = r.isFavorite; tags = r.tags
        provider = r.provider; externalID = r.externalID; extra = r.extra
        createdAt = r.createdAt; updatedAt = r.updatedAt; startedAt = r.startedAt
        finishedAt = r.finishedAt; deletedAt = r.deletedAt
    }
}
