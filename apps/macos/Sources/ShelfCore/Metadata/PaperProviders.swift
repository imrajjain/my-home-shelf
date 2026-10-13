import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// arXiv — search and resolve preprints via the public Atom API.
public struct ArxivProvider: SearchProvider, LinkResolver {
    public let name = "arXiv"
    public let kinds: Set<ItemKind> = [.paper]
    let http: HTTP

    public init(http: HTTP = .shared) { self.http = http }

    public func search(_ query: String, kind: ItemKind) async throws -> [Metadata] {
        guard let url = URL.api("https://export.arxiv.org/api/query", [
            "search_query": "all:\(query)", "max_results": "8", "sortBy": "relevance",
        ]) else { return [] }
        let (data, _) = try await http.data(url, accept: "application/atom+xml")
        return ArxivFeedParser.parse(data).map { $0.metadata(provider: name) }
    }

    public func canResolve(_ url: URL) -> Bool { LinkClassifier.arxivID(url) != nil }

    public func resolve(_ url: URL) async throws -> Metadata? {
        guard let id = LinkClassifier.arxivID(url),
              let api = URL.api("https://export.arxiv.org/api/query", ["id_list": id]) else { return nil }
        let (data, _) = try await http.data(api, accept: "application/atom+xml")
        return ArxivFeedParser.parse(data).first?.metadata(provider: name)
    }
}

struct ArxivEntry {
    var id = ""
    var title = ""
    var summary = ""
    var published = ""
    var authors: [String] = []
    var categories: [String] = []
    var pdf: String?
    var journalRef: String?

    func metadata(provider: String) -> Metadata {
        let shortID = id.components(separatedBy: "/abs/").last.map {
            $0.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
        } ?? id
        var m = Metadata(kind: .paper, title: title.squished, provider: provider, externalID: "arxiv:\(shortID)")
        m.creator = authors.count > 3 ? authors.prefix(3).joined(separator: ", ") + " et al." : authors.joined(separator: ", ")
        m.year = published.leadingYear
        m.summary = summary.squished
        m.url = URL(string: "https://arxiv.org/abs/\(shortID)")
        m.extra["arxiv"] = shortID
        m.extra["venue"] = journalRef ?? "arXiv"
        if let pdf { m.extra["pdf"] = pdf }
        m.tags = Array(categories.prefix(3))
        return m
    }
}

/// Minimal SAX parser for arXiv's Atom feed.
final class ArxivFeedParser: NSObject, XMLParserDelegate {
    private var entries: [ArxivEntry] = []
    private var current: ArxivEntry?
    private var text = ""
    private var inAuthor = false

    static func parse(_ data: Data) -> [ArxivEntry] {
        let delegate = ArxivFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "entry": current = ArxivEntry()
        case "author": inAuthor = true
        case "category": if let term = attributes["term"] { current?.categories.append(term) }
        case "link":
            if attributes["title"] == "pdf", let href = attributes["href"] { current?.pdf = href }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmed
        switch name {
        case "entry": if let current, !current.title.isEmpty { entries.append(current) }; current = nil
        case "id": if current != nil && !inAuthor { current?.id = value }
        case "title": current?.title = value
        case "summary": current?.summary = value
        case "published": current?.published = value
        case "name": if inAuthor { current?.authors.append(value) }
        case "author": inAuthor = false
        case "arxiv:journal_ref", "journal_ref": current?.journalRef = value.nilIfEmpty
        default: break
        }
        text = ""
    }
}

/// Crossref — the DOI registry. Resolves DOIs and searches published work.
public struct CrossrefProvider: SearchProvider, LinkResolver {
    public let name = "Crossref"
    public let kinds: Set<ItemKind> = [.paper]
    let http: HTTP

    public init(http: HTTP = .shared) { self.http = http }

    public func search(_ query: String, kind: ItemKind) async throws -> [Metadata] {
        guard let url = URL.api("https://api.crossref.org/works", [
            "query.bibliographic": query, "rows": "8",
            "select": "DOI,title,author,issued,container-title,abstract,type,URL",
        ]) else { return [] }
        let json = try await http.jsonObject(from: url)
        let items = ((json["message"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
        return items.compactMap(metadata(from:))
    }

    public func canResolve(_ url: URL) -> Bool {
        url.hostWithoutWWW.hasSuffix("doi.org") && LinkClassifier.doi(in: url.absoluteString) != nil
    }

    public func resolve(_ url: URL) async throws -> Metadata? {
        guard let doi = LinkClassifier.doi(in: url.absoluteString) else { return nil }
        return try await resolve(doi: doi)
    }

    public func resolve(doi: String) async throws -> Metadata? {
        let escaped = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
        guard let url = URL(string: "https://api.crossref.org/works/\(escaped)") else { return nil }
        let json = try await http.jsonObject(from: url)
        return (json["message"] as? [String: Any]).flatMap(metadata(from:))
    }

    func metadata(from work: [String: Any]) -> Metadata? {
        guard let title = (work["title"] as? [String])?.first?.squished, !title.isEmpty else { return nil }
        let doi = work["DOI"] as? String
        var m = Metadata(kind: .paper, title: title, provider: name, externalID: doi.map { "doi:\($0)" })
        let authors = ((work["author"] as? [[String: Any]]) ?? []).compactMap { a -> String? in
            let parts = [a["given"] as? String, a["family"] as? String].compactMap { $0 }
            return parts.isEmpty ? (a["name"] as? String) : parts.joined(separator: " ")
        }
        let byline = authors.count > 3 ? authors.prefix(3).joined(separator: ", ") + " et al." : authors.joined(separator: ", ")
        m.creator = byline.nilIfEmpty
        if let parts = (work["issued"] as? [String: Any])?["date-parts"] as? [[Any]],
           let year = parts.first?.first as? Int {
            m.year = year
        }
        m.extra["venue"] = (work["container-title"] as? [String])?.first
        if let doi { m.extra["doi"] = doi; m.url = URL(string: "https://doi.org/\(doi)") }
        m.summary = (work["abstract"] as? String)?.strippingTags
            .replacingOccurrences(of: #"^Abstract\s*"#, with: "", options: .regularExpression)
        return m
    }
}

/// Wikipedia — summaries and thumbnails for curiosities, places, anything.
public struct WikipediaProvider: SearchProvider, LinkResolver {
    public let name = "Wikipedia"
    public let kinds: Set<ItemKind> = [.curiosity, .place]
    let http: HTTP

    public init(http: HTTP = .shared) { self.http = http }

    public func search(_ query: String, kind: ItemKind) async throws -> [Metadata] {
        guard let url = URL.api("https://en.wikipedia.org/w/rest.php/v1/search/title", ["q": query, "limit": "6"])
        else { return [] }
        let json = try await http.jsonObject(from: url)
        let pages = (json["pages"] as? [[String: Any]]) ?? []
        return pages.compactMap { page in
            guard let title = page["title"] as? String, let key = page["key"] as? String else { return nil }
            var m = Metadata(kind: kind, title: title, provider: name, externalID: "wiki:\(key)")
            m.subtitle = (page["description"] as? String)?.nilIfEmpty
            m.url = URL(string: "https://en.wikipedia.org/wiki/\(key)")
            if let thumb = (page["thumbnail"] as? [String: Any])?["url"] as? String {
                let full = thumb.hasPrefix("//") ? "https:" + thumb : thumb
                // Thumbnails are /60px-...; ask for something worthy of a card.
                m.imageURL = URL(string: full.replacingOccurrences(of: #"/\d+px-"#, with: "/640px-", options: .regularExpression))
            }
            return m
        }
    }

    public func canResolve(_ url: URL) -> Bool {
        url.hostWithoutWWW.hasSuffix("wikipedia.org") && url.path.hasPrefix("/wiki/")
    }

    public func resolve(_ url: URL) async throws -> Metadata? {
        let lang = url.hostWithoutWWW.components(separatedBy: ".").first.flatMap { $0 == "wikipedia" ? nil : $0 } ?? "en"
        let title = String(url.path.dropFirst("/wiki/".count))
        return try await summary(title: title, lang: lang)
    }

    /// Page summary for an exact (or close) title.
    public func summary(title: String, lang: String = "en", kind: ItemKind = .curiosity) async throws -> Metadata? {
        let slug = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(slug)") else { return nil }
        let json = try await http.jsonObject(from: url)
        guard let pageTitle = json["title"] as? String, json["type"] as? String != "disambiguation" else { return nil }
        var m = Metadata(kind: kind, title: pageTitle, provider: name, externalID: "wiki:\(slug)")
        m.subtitle = (json["description"] as? String)?.nilIfEmpty
        m.summary = (json["extract"] as? String)?.nilIfEmpty
        if let img = ((json["originalimage"] as? [String: Any]) ?? (json["thumbnail"] as? [String: Any]))?["source"] as? String {
            m.imageURL = URL(string: img)
        }
        if let page = ((json["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String {
            m.url = URL(string: page)
        }
        if let coords = json["coordinates"] as? [String: Any],
           let lat = coords["lat"] as? Double, let lon = coords["lon"] as? Double {
            m.extra["latitude"] = String(lat)
            m.extra["longitude"] = String(lon)
        }
        return m
    }
}
