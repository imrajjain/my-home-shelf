import Foundation

/// Extracts OpenGraph, Twitter Card and JSON-LD metadata from an HTML page.
///
/// Deliberately regex-based and forgiving: we only need the `<head>` and a
/// few `<script type="application/ld+json">` blocks, not a DOM.
public struct HTMLMetadataParser: Sendable {
    public struct Page {
        public var meta: [String: String] = [:]   // lowercased property/name -> content
        public var title: String?
        public var canonical: URL?
        public var jsonLD: [[String: Any]] = []

        public subscript(_ key: String) -> String? { meta[key.lowercased()]?.nilIfEmpty }

        public init() {}
    }

    public init() {}

    public func parse(_ html: String, baseURL: URL? = nil) -> Page {
        var page = Page()
        // Everything useful lives before </head>; cap the work for huge pages.
        let head: Substring = {
            if let end = html.range(of: "</head>", options: .caseInsensitive) {
                return html[..<end.upperBound]
            }
            return html.prefix(400_000)
        }()
        let headString = String(head)

        for tag in matches(of: #"<meta\b[^>]*>"#, in: headString) {
            let attrs = attributes(in: tag)
            guard let content = attrs["content"] else { continue }
            for key in ["property", "name", "itemprop"] {
                if let name = attrs[key]?.lowercased(), page.meta[name] == nil {
                    page.meta[name] = decodeEntities(content)
                }
            }
        }

        if let title = firstCapture(of: #"<title[^>]*>([\s\S]*?)</title>"#, in: headString) {
            page.title = decodeEntities(title).squished.nilIfEmpty
        }

        for tag in matches(of: #"<link\b[^>]*>"#, in: headString) {
            let attrs = attributes(in: tag)
            if attrs["rel"]?.lowercased() == "canonical", let href = attrs["href"] {
                page.canonical = URL(string: href, relativeTo: baseURL)?.absoluteURL
            }
        }

        // JSON-LD can appear in <body> too (Letterboxd), so scan the whole doc.
        let scripts = captures(
            of: #"<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#,
            in: String(html.prefix(2_000_000))
        )
        for raw in scripts {
            var body = raw.trimmed
            // Letterboxd wraps JSON-LD in /* <![CDATA[ */ ... /* ]]> */
            body = body.replacingOccurrences(of: #"/\*\s*<!\[CDATA\[\s*\*/"#, with: "", options: .regularExpression)
            body = body.replacingOccurrences(of: #"/\*\s*\]\]>\s*\*/"#, with: "", options: .regularExpression)
            guard let data = body.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            page.jsonLD.append(contentsOf: flattenLD(object))
        }
        return page
    }

    // MARK: - JSON-LD

    private func flattenLD(_ object: Any) -> [[String: Any]] {
        if let array = object as? [Any] { return array.flatMap(flattenLD) }
        guard let dict = object as? [String: Any] else { return [] }
        if let graph = dict["@graph"] { return flattenLD(graph) }
        return [dict]
    }

    // MARK: - Regex helpers

    private func matches(of pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private func captures(of pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : nil
        }
    }

    private func firstCapture(of pattern: String, in text: String) -> String? {
        captures(of: pattern, in: text).first
    }

    func attributes(in tag: String) -> [String: String] {
        guard let re = try? NSRegularExpression(
            pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#
        ) else { return [:] }
        let ns = tag as NSString
        var result: [String: String] = [:]
        for m in re.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            for i in 2...4 where m.range(at: i).location != NSNotFound {
                result[name] = ns.substring(with: m.range(at: i))
                break
            }
        }
        return result
    }

    func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named: [String: String] = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">",
            "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…",
            "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“",
        ]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        // Numeric entities: &#8217; and &#x2019;
        if let re = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let hex = ns.substring(with: m.range(at: 1)) == "x"
                let digits = ns.substring(with: m.range(at: 2))
                if let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    result.unicodeScalars.append(scalar)
                } else {
                    result += ns.substring(with: m.range)
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }
}

// MARK: - Page -> Metadata

extension HTMLMetadataParser.Page {
    /// Best-effort interpretation of the page as a shelf item.
    public func metadata(for url: URL, guessedKind: ItemKind) -> Metadata {
        let ld = primaryLD
        let ldType = (ld?["@type"] as? String) ?? ((ld?["@type"] as? [String])?.first)

        let kind = Self.kind(fromLD: ldType) ?? Self.kind(fromOG: self["og:type"]) ?? guessedKind
        let finalKind = (guessedKind != .article) ? guessedKind : kind

        var title = (ld?["name"] as? String) ?? (ld?["headline"] as? String)
            ?? self["og:title"] ?? self["twitter:title"] ?? self.title ?? url.absoluteString
        title = HTMLMetadataParser().decodeEntities(title).squished

        let siteName = self["og:site_name"] ?? url.hostWithoutWWW
        var meta = Metadata(kind: finalKind, title: title, provider: siteName)
        meta.url = canonical ?? URL(string: self["og:url"] ?? "") ?? url
        meta.summary = (ld?["description"] as? String).map { HTMLMetadataParser().decodeEntities($0) }
            ?? self["og:description"] ?? self["twitter:description"] ?? self["description"]
        meta.summary = meta.summary?.squished.nilIfEmpty

        if let img = Self.image(fromLD: ld) ?? self["og:image"] ?? self["twitter:image"] ?? self["twitter:image:src"],
           let imgURL = URL(string: img, relativeTo: url)?.absoluteURL {
            meta.imageURL = imgURL.secured
        }

        meta.creator = Self.people(ld?["author"]) ?? Self.people(ld?["director"]) ?? Self.people(ld?["creator"])
            ?? self["author"] ?? self["article:author"].flatMap { $0.hasPrefix("http") ? nil : $0 }
            ?? self["book:author"].flatMap { $0.hasPrefix("http") ? nil : $0 }
        if meta.creator == nil, let directed = self["twitter:data1"], self["twitter:label1"]?.lowercased().contains("direct") == true {
            meta.creator = directed
        }

        let dateString = (ld?["datePublished"] as? String) ?? (ld?["dateCreated"] as? String)
            ?? self["article:published_time"] ?? self["citation_publication_date"] ?? self["citation_date"]
        meta.year = dateString?.leadingYear

        if let pages = ld?["numberOfPages"] { meta.extra["pages"] = "\(pages)" }
        if let isbn = ld?["isbn"] as? String { meta.extra["isbn"] = isbn }

        // Highwire/Google Scholar tags, common on academic pages.
        if let citationTitle = self["citation_title"] {
            meta.kind = .paper
            meta.title = citationTitle
            meta.creator = meta.creator ?? self["citation_author"]
            meta.extra["venue"] = self["citation_journal_title"] ?? self["citation_conference_title"]
            if let doi = self["citation_doi"] { meta.extra["doi"] = doi }
            if let pdf = self["citation_pdf_url"] { meta.extra["pdf"] = pdf }
        }

        // Letterboxd/IMDb titles often look like "Dune (2021)" — split the year out.
        if [.film, .show].contains(meta.kind),
           let r = meta.title.range(of: #"\s*\((\d{4})\)\s*$"#, options: .regularExpression) {
            meta.year = meta.year ?? String(meta.title[r]).leadingYear
            meta.title = String(meta.title[..<r.lowerBound])
        }
        // Strip " | Site" / " - Site" suffixes on generic pages.
        for sep in [" | ", " – ", " — ", " - "] where meta.kind == .article {
            if let r = meta.title.range(of: sep, options: .backwards),
               meta.title[r.upperBound...].count < 40,
               siteName.lowercased().contains(meta.title[r.upperBound...].lowercased().trimmed) {
                meta.title = String(meta.title[..<r.lowerBound])
            }
        }
        if let rating = (ld?["aggregateRating"] as? [String: Any])?["ratingValue"] {
            meta.extra["communityRating"] = "\(rating)"
        }
        if let genres = ld?["genre"] as? [String] { meta.tags = Array(genres.prefix(4)) }
        else if let genre = ld?["genre"] as? String { meta.tags = [genre] }
        return meta
    }

    /// The JSON-LD node that describes the main thing on the page.
    private var primaryLD: [String: Any]? {
        let preferred = ["Book", "Movie", "TVSeries", "TVSeason", "ScholarlyArticle", "Article", "NewsArticle",
                         "BlogPosting", "VideoObject", "PodcastSeries", "PodcastEpisode", "MusicAlbum",
                         "MusicRecording", "Place", "Restaurant", "LocalBusiness", "TouristAttraction"]
        for type in preferred {
            if let node = jsonLD.first(where: { node in
                if let t = node["@type"] as? String { return t == type }
                if let ts = node["@type"] as? [String] { return ts.contains(type) }
                return false
            }) { return node }
        }
        return nil
    }

    static func kind(fromLD type: String?) -> ItemKind? {
        switch type {
        case "Book": .book
        case "Movie": .film
        case "TVSeries", "TVSeason", "TVEpisode": .show
        case "ScholarlyArticle": .paper
        case "Article", "NewsArticle", "BlogPosting": .article
        case "VideoObject": .video
        case "PodcastSeries", "PodcastEpisode": .podcast
        case "MusicAlbum", "MusicRecording": .music
        case "Place", "Restaurant", "LocalBusiness", "TouristAttraction": .place
        default: nil
        }
    }

    static func kind(fromOG type: String?) -> ItemKind? {
        guard let type = type?.lowercased() else { return nil }
        if type == "book" || type.hasPrefix("books.") { return .book }
        if type == "video.movie" { return .film }
        if type.hasPrefix("video.tv_show") || type == "video.episode" { return .show }
        if type.hasPrefix("video") { return .video }
        if type.hasPrefix("music") { return .music }
        if type == "place" || type == "restaurant.restaurant" { return .place }
        return nil
    }

    static func image(fromLD ld: [String: Any]?) -> String? {
        guard let image = ld?["image"] else { return nil }
        if let s = image as? String { return s }
        if let d = image as? [String: Any] { return d["url"] as? String }
        if let a = image as? [Any] {
            if let s = a.first as? String { return s }
            if let d = a.first as? [String: Any] { return d["url"] as? String }
        }
        return nil
    }

    static func people(_ value: Any?) -> String? {
        func name(_ v: Any) -> String? {
            if let s = v as? String { return s.hasPrefix("http") ? nil : s }
            if let d = v as? [String: Any] { return d["name"] as? String }
            return nil
        }
        guard let value else { return nil }
        if let array = value as? [Any] {
            let names = array.compactMap(name)
            guard !names.isEmpty else { return nil }
            return names.count > 3 ? names.prefix(3).joined(separator: ", ") + " et al." : names.joined(separator: ", ")
        }
        return name(value)?.nilIfEmpty
    }
}
