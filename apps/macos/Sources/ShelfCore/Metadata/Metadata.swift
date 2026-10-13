import Foundation

/// A candidate description of something, as returned by a provider.
/// The capture UI shows these as choices; picking one becomes an item.
public struct Metadata: Codable, Hashable, Identifiable, Sendable {
    public var kind: ItemKind
    public var title: String
    public var subtitle: String?
    public var creator: String?
    public var year: Int?
    public var summary: String?
    public var imageURL: URL?
    public var url: URL?
    /// Human-readable source, e.g. "Open Library", "arXiv", "Letterboxd".
    public var provider: String
    public var externalID: String?
    public var tags: [String]
    /// Kind-specific details: pages, runtime, venue, doi, latitude, ...
    public var extra: [String: String]

    public var id: String {
        [provider, externalID ?? url?.absoluteString ?? title].joined(separator: ":")
    }

    public init(
        kind: ItemKind, title: String, subtitle: String? = nil, creator: String? = nil,
        year: Int? = nil, summary: String? = nil, imageURL: URL? = nil, url: URL? = nil,
        provider: String, externalID: String? = nil, tags: [String] = [], extra: [String: String] = [:]
    ) {
        self.kind = kind; self.title = title; self.subtitle = subtitle; self.creator = creator
        self.year = year; self.summary = summary; self.imageURL = imageURL; self.url = url
        self.provider = provider; self.externalID = externalID; self.tags = tags; self.extra = extra
    }

    /// One-line description under the title: "Frank Herbert · 1965 · 412 pages".
    public var byline: String {
        var parts: [String] = []
        if let creator, !creator.isEmpty { parts.append(creator) }
        if let year { parts.append(String(year)) }
        if let pages = extra["pages"] { parts.append("\(pages) pages") }
        if let runtime = extra["runtime"] { parts.append(runtime) }
        if let venue = extra["venue"] { parts.append(venue) }
        return parts.joined(separator: " · ")
    }

    /// Fill gaps in `self` with values from `other` (self wins on conflicts).
    public func merged(with other: Metadata) -> Metadata {
        var m = self
        if m.subtitle == nil { m.subtitle = other.subtitle }
        if m.creator == nil { m.creator = other.creator }
        if m.year == nil { m.year = other.year }
        if (m.summary ?? "").count < (other.summary ?? "").count / 2 { m.summary = other.summary }
        if m.imageURL == nil { m.imageURL = other.imageURL }
        if m.url == nil { m.url = other.url }
        if m.tags.isEmpty { m.tags = other.tags }
        m.extra.merge(other.extra) { mine, _ in mine }
        return m
    }
}

public enum MetadataError: Error, Sendable {
    case badResponse(Int)
    case unreadable
    case missingConfiguration(String)
}

/// Searches a catalogue by free text ("dune", "attention is all you need").
public protocol SearchProvider: Sendable {
    var name: String { get }
    var kinds: Set<ItemKind> { get }
    func search(_ query: String, kind: ItemKind) async throws -> [Metadata]
}

/// Turns a specific URL into rich metadata (arXiv abstracts, DOIs, ...).
public protocol LinkResolver: Sendable {
    func canResolve(_ url: URL) -> Bool
    func resolve(_ url: URL) async throws -> Metadata?
}

extension String {
    /// Pulls a plausible four-digit year out of "2021-10-22", "Oct 2021", etc.
    var leadingYear: Int? {
        guard let range = range(of: #"(1[5-9]|20)\d{2}"#, options: .regularExpression) else { return nil }
        return Int(self[range])
    }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfEmpty: String? { trimmed.isEmpty ? nil : trimmed }

    /// Collapses runs of whitespace (incl. newlines) to single spaces.
    var squished: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Removes XML/HTML tags, e.g. JATS markup in Crossref abstracts.
    var strippingTags: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression).squished
    }
}
