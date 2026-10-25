import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A Wikipedia article worth wandering into.
public struct WikiArticle: Identifiable, Hashable, Sendable {
    public var title: String
    public var description: String?
    public var extract: String?
    public var thumbnail: URL?
    public var id: String { title }

    public init(title: String, description: String? = nil, extract: String? = nil, thumbnail: URL? = nil) {
        self.title = title; self.description = description; self.extract = extract; self.thumbnail = thumbnail
    }

    public var url: URL {
        URL(string: "https://en.wikipedia.org/wiki/" + title.replacingOccurrences(of: " ", with: "_").pathEncoded)!
    }

    /// The mobile page reads more cleanly in a small window.
    public var readerURL: URL {
        URL(string: "https://en.m.wikipedia.org/wiki/" + title.replacingOccurrences(of: " ", with: "_").pathEncoded)!
    }
}

/// Finds Wikipedia articles related to things on your shelf, using
/// Wikipedia's own "more like this" search.
public struct WikipediaFeed: Sendable {
    let http: HTTP

    public init(http: HTTP = .shared) { self.http = http }

    /// How far to stray from the thing on your shelf.
    public enum Route: CaseIterable, Sendable {
        /// "More like this", skipping the most obvious matches.
        case near
        /// Two steps out: more like something that's like it.
        case hop
        /// Somewhere the article (or a neighbour) links to.
        case links
    }

    /// An article found on a walk, and the stepping stone it came through.
    public struct Found: Sendable {
        public var article: WikiArticle
        public var via: String?
    }

    /// Wanders out from something on your shelf along `route`, skipping
    /// anything in `avoiding` (already seen, already on the shelf).
    public func wander(fromTitle title: String, creator: String?, kind: ItemKind, route: Route,
                       limit: Int, avoiding: Set<String>) async -> [Found] {
        guard let seed = await article(for: title, creator: creator, kind: kind) else { return [] }
        func fresh(_ list: [WikiArticle], besides: Set<String> = []) -> [WikiArticle] {
            list.filter { $0.title != seed && !besides.contains($0.title)
                && !avoiding.contains($0.title.lowercased()) && Self.isReadable($0) }
        }
        let near = (try? await search("morelike:\(seed)", limit: 30)) ?? []

        switch route {
        case .near:
            // The first few are the obvious ones (the film of the book, the author).
            let pool = fresh(Array(near.dropFirst(3)))
            return pool.shuffled().prefix(limit).map { Found(article: $0, via: nil) }

        case .hop:
            guard let stone = fresh(near).shuffled().first else { return [] }
            let far = (try? await search("morelike:\(stone.title)", limit: 30)) ?? []
            let pool = fresh(far, besides: Set(near.map(\.title)).union([stone.title]))
            return pool.shuffled().prefix(limit).map { Found(article: $0, via: stone.title) }

        case .links:
            // From the article itself or one of its neighbours, follow a few links at random.
            let stone = Bool.random() ? nil : fresh(near).shuffled().first?.title
            let titles = (try? await links(from: stone ?? seed)) ?? []
            let sample = titles.filter { $0 != seed && !avoiding.contains($0.lowercased()) }.shuffled().prefix(20)
            let pages = (try? await details(Array(sample))) ?? []
            // Links include years, countries and stubs; keep ones with something to say.
            let pool = fresh(pages).filter { $0.description != nil && ($0.extract?.count ?? 0) > 120 }
            return pool.prefix(limit).map { Found(article: $0, via: stone) }
        }
    }

    /// Titles of the articles a page links to.
    func links(from title: String) async throws -> [String] {
        guard let url = URL.api("https://en.wikipedia.org/w/api.php", [
            "action": "query", "format": "json", "formatversion": "2",
            "titles": title, "prop": "links", "plnamespace": "0", "pllimit": "max",
        ]) else { return [] }
        let json = try await http.jsonObject(from: url)
        let pages = (json["query"] as? [String: Any])?["pages"] as? [[String: Any]] ?? []
        return pages.flatMap { ($0["links"] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String } }
    }

    /// Descriptions, opening lines and pictures for up to 20 titles.
    func details(_ titles: [String]) async throws -> [WikiArticle] {
        guard !titles.isEmpty, let url = URL.api("https://en.wikipedia.org/w/api.php", [
            "action": "query", "format": "json", "formatversion": "2", "redirects": "1",
            "titles": titles.prefix(20).joined(separator: "|"),
            "prop": "pageimages|description|extracts",
            "exintro": "1", "explaintext": "1", "exsentences": "2", "exlimit": "max",
            "piprop": "thumbnail", "pithumbsize": "480", "pilimit": "max",
        ]) else { return [] }
        let json = try await http.jsonObject(from: url)
        let pages = (json["query"] as? [String: Any])?["pages"] as? [[String: Any]] ?? []
        return pages.compactMap(Self.article(from:)).shuffled()
    }

    /// The article about the thing itself, e.g. "Flowers for Algernon".
    func article(for title: String, creator: String?, kind: ItemKind) async -> String? {
        let hint: String = switch kind {
        case .book: creator ?? "novel"
        case .film: "film"
        case .show: "television series"
        default: creator ?? ""
        }
        let query = [title, hint].filter { !$0.isEmpty }.joined(separator: " ")
        return (try? await search(query, limit: 1))?.first?.title
    }

    func search(_ query: String, limit: Int) async throws -> [WikiArticle] {
        guard let url = URL.api("https://en.wikipedia.org/w/api.php", [
            "action": "query", "format": "json", "formatversion": "2",
            "generator": "search", "gsrsearch": query, "gsrlimit": String(limit),
            "prop": "pageimages|description|extracts",
            "exintro": "1", "explaintext": "1", "exsentences": "2", "exlimit": "max",
            "piprop": "thumbnail", "pithumbsize": "480",
        ]) else { return [] }
        let json = try await http.jsonObject(from: url)
        let pages = (json["query"] as? [String: Any])?["pages"] as? [[String: Any]] ?? []
        return pages
            .sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
            .compactMap(Self.article(from:))
    }

    static func article(from page: [String: Any]) -> WikiArticle? {
        guard let title = page["title"] as? String else { return nil }
        let thumb = (page["thumbnail"] as? [String: Any])?["source"] as? String
        return WikiArticle(
            title: title,
            description: (page["description"] as? String)?.nilIfEmpty,
            extract: (page["extract"] as? String)?.nilIfEmpty,
            thumbnail: thumb.flatMap(URL.init(string:))
        )
    }

    /// Links every article's references carry; not topics anyone wanders into.
    static let plumbing: Set<String> = [
        "ISBN", "ISSN", "Digital object identifier", "JSTOR", "OCLC", "PubMed", "PubMed Central",
        "PMID", "Bibcode", "ArXiv", "S2CID", "Semantic Scholar", "ProQuest", "Wayback Machine",
        "Internet Archive", "Wikidata", "Wikimedia Commons", "Wikisource", "Wikiquote", "Library of Congress Control Number",
        "Virtual International Authority File", "Integrated Authority File", "Hdl (identifier)", "Handle System",
        "Doi (identifier)", "Issn (identifier)", "IMDb", "Rotten Tomatoes", "Metacritic", "Box Office Mojo",
        "AllMovie", "Goodreads", "Project Gutenberg", "LibriVox", "Google Books", "The New York Times",
    ]

    /// Skips lists, disambiguation pages and the like.
    static func isReadable(_ article: WikiArticle) -> Bool {
        let t = article.title
        if ["List of", "Lists of", "Outline of", "Index of", "Timeline of", "Glossary of"].contains(where: t.hasPrefix)
            || t.contains("(disambiguation)") || plumbing.contains(t) { return false }
        if t.range(of: #"^\d{4} in "#, options: .regularExpression) != nil { return false }
        if article.description?.localizedCaseInsensitiveContains("disambiguation") == true { return false }
        return article.extract != nil
    }
}

extension String {
    var pathEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#"))) ?? self
    }
}
