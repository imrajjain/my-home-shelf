import Foundation

/// The portable, sync-ready shape of a shelf item.
///
/// This is the contract shared by the macOS app's export/import today and
/// the web app + sync service tomorrow (see docs/ARCHITECTURE.md). Keep it
/// additive: new fields must be optional so older clients keep decoding.
public struct ItemRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    public var status: ItemStatus
    public var title: String
    public var subtitle: String?
    public var creator: String?
    public var year: Int?
    public var summary: String?
    public var notes: String
    public var url: URL?
    public var imageURL: URL?
    public var rating: Int
    public var progress: Double
    public var isFavorite: Bool
    public var tags: [String]
    public var provider: String?
    public var externalID: String?
    public var extra: [String: String]
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    /// Tombstone: deleted items are kept (briefly) so deletions can sync.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), kind: ItemKind, status: ItemStatus = .want, title: String,
        subtitle: String? = nil, creator: String? = nil, year: Int? = nil, summary: String? = nil,
        notes: String = "", url: URL? = nil, imageURL: URL? = nil, rating: Int = 0,
        progress: Double = 0, isFavorite: Bool = false, tags: [String] = [],
        provider: String? = nil, externalID: String? = nil, extra: [String: String] = [:],
        createdAt: Date = .now, updatedAt: Date = .now, startedAt: Date? = nil,
        finishedAt: Date? = nil, deletedAt: Date? = nil
    ) {
        self.id = id; self.kind = kind; self.status = status; self.title = title
        self.subtitle = subtitle; self.creator = creator; self.year = year; self.summary = summary
        self.notes = notes; self.url = url; self.imageURL = imageURL; self.rating = rating
        self.progress = progress; self.isFavorite = isFavorite; self.tags = tags
        self.provider = provider; self.externalID = externalID; self.extra = extra
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.startedAt = startedAt
        self.finishedAt = finishedAt; self.deletedAt = deletedAt
    }
}

public struct ShelfArchive: Codable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var exportedAt: Date
    public var items: [ItemRecord]

    public init(items: [ItemRecord], exportedAt: Date = .now) {
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.items = items
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
