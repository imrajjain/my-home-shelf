import Foundation

/// "Please put this on my shelf" — from the browser extension, the
/// `shelf://` URL scheme, the Services menu or the quick-capture panel.
public struct CaptureRequest: Codable, Hashable, Sendable {
    public var url: URL?
    public var title: String?
    /// Selected text on the page, kept as a quote in the item's notes.
    public var selection: String?
    public var note: String?
    public var kind: ItemKind?
    public var status: ItemStatus?
    public var tags: [String]?

    public init(url: URL? = nil, title: String? = nil, selection: String? = nil, note: String? = nil,
                kind: ItemKind? = nil, status: ItemStatus? = nil, tags: [String]? = nil) {
        self.url = url; self.title = title; self.selection = selection; self.note = note
        self.kind = kind; self.status = status; self.tags = tags
    }

    public var isEmpty: Bool {
        url == nil && (title ?? "").trimmed.isEmpty && (selection ?? "").trimmed.isEmpty
    }

    /// Parses `shelf://add?url=…&title=…&selection=…&kind=book&status=done&tags=a,b`.
    /// Returns nil for anything that isn't an add request.
    public init?(deepLink: URL) {
        guard deepLink.scheme?.lowercased() == DeepLink.scheme else { return nil }
        let action = (deepLink.host ?? deepLink.pathComponents.dropFirst().first ?? "").lowercased()
        guard action == "add" || action == "capture" else { return nil }
        // Form-style decoding: browsers' URLSearchParams writes spaces as "+".
        let items = URLComponents(url: deepLink, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value?
                .replacingOccurrences(of: "+", with: " ").removingPercentEncoding?.nilIfEmpty
        }

        self.init(
            url: value("url").flatMap(URL.init(string:)),
            title: value("title"),
            selection: value("selection") ?? value("text"),
            note: value("note"),
            kind: value("kind").flatMap(ItemKind.init(rawValue:)),
            status: value("status").flatMap(ItemStatus.init(rawValue:)),
            tags: value("tags")?.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        )
        if url == nil, let text = selection, let found = LinkClassifier.firstURL(in: text), LinkClassifier.isBareURL(text) {
            url = found
            selection = nil
        }
        if isEmpty { return nil }
    }

    /// Interprets loose text (clipboard, Services menu): a bare link becomes
    /// a URL capture, anything else becomes a titled curiosity.
    public init(text: String) {
        let t = text.trimmed
        if LinkClassifier.isBareURL(t), let url = LinkClassifier.firstURL(in: t) {
            self.init(url: url)
        } else if t.count <= 140 && !t.contains("\n") {
            self.init(url: LinkClassifier.firstURL(in: t), title: t)
        } else {
            self.init(url: LinkClassifier.firstURL(in: t), selection: t)
        }
    }
}

public enum DeepLink {
    public static let scheme = "shelf"

    public static func addURL(for request: CaptureRequest) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "add"
        var q: [(String, String)] = []
        if let url = request.url { q.append(("url", url.absoluteString)) }
        if let title = request.title { q.append(("title", title)) }
        if let selection = request.selection { q.append(("selection", selection)) }
        if let note = request.note { q.append(("note", note)) }
        if let kind = request.kind { q.append(("kind", kind.rawValue)) }
        if let status = request.status { q.append(("status", status.rawValue)) }
        if let tags = request.tags, !tags.isEmpty { q.append(("tags", tags.joined(separator: ","))) }
        c.percentEncodedQueryItems = q.map { URLQueryItem(name: $0.0, value: $0.1.queryEncoded) }
        return c.url
    }
}
