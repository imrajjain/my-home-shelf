import Foundation

/// "Keep this text in my notes" — selected text and where it came from,
/// from the snippet shortcut, the Services menu, the browser extension
/// (`POST /v1/snippets`) or `shelf://snippet?text=…&url=…&title=…`.
public struct SnippetRequest: Codable, Hashable, Sendable {
    public var text: String
    /// The page or document the text was selected in.
    public var url: URL?
    /// Its title.
    public var title: String?
    /// The app it was selected in.
    public var app: String?
    /// A thought of your own to go with it.
    public var note: String?
    public var tags: [String]?

    public init(text: String, url: URL? = nil, title: String? = nil, app: String? = nil,
                note: String? = nil, tags: [String]? = nil) {
        self.text = text; self.url = url; self.title = title; self.app = app
        self.note = note; self.tags = tags
    }

    public var isEmpty: Bool { text.trimmed.isEmpty }

    public var source: SnippetSource? {
        let source = SnippetSource(url: url, title: title?.nilIfEmpty, app: app?.nilIfEmpty)
        return source.isEmpty ? nil : source
    }

    /// Parses `shelf://snippet?text=…&url=…&title=…&app=…&note=…&tags=a,b`.
    public init?(deepLink: URL) {
        guard deepLink.scheme?.lowercased() == DeepLink.scheme else { return nil }
        let action = (deepLink.host ?? deepLink.pathComponents.dropFirst().first ?? "").lowercased()
        guard action == "snippet" else { return nil }
        let items = URLComponents(url: deepLink, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value?
                .replacingOccurrences(of: "+", with: " ").removingPercentEncoding?.nilIfEmpty
        }
        guard let text = value("text") ?? value("selection") else { return nil }
        self.init(
            text: text,
            url: value("url").flatMap(URL.init(string:)),
            title: value("title"),
            app: value("app"),
            note: value("note"),
            tags: value("tags")?.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        )
    }
}

extension DeepLink {
    public static func snippetURL(for request: SnippetRequest) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "snippet"
        var q: [(String, String)] = [("text", request.text)]
        if let url = request.url { q.append(("url", url.absoluteString)) }
        if let title = request.title { q.append(("title", title)) }
        if let app = request.app { q.append(("app", app)) }
        if let note = request.note { q.append(("note", note)) }
        if let tags = request.tags, !tags.isEmpty { q.append(("tags", tags.joined(separator: ","))) }
        c.percentEncodedQueryItems = q.map { URLQueryItem(name: $0.0, value: $0.1.queryEncoded) }
        return c.url
    }
}
