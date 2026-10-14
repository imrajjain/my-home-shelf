import Foundation

/// Apple's iTunes Search API — keyless posters & artwork for films, shows,
/// podcasts and albums.
public struct ITunesProvider: SearchProvider {
    public let name = "Apple"
    // Films and shows moved to Wikipedia/TVmaze: Apple's catalogue search for
    // them went quiet (`media=movie` returns nothing; TV hits are unrelated).
    public let kinds: Set<ItemKind> = [.podcast, .music]
    let http: HTTP

    public init(http: HTTP = .shared) { self.http = http }

    struct Response: Decodable {
        struct Result: Decodable {
            let trackId: Int?
            let collectionId: Int?
            let trackName: String?
            let collectionName: String?
            let artistName: String?
            let releaseDate: String?
            let longDescription: String?
            let description: String?
            let shortDescription: String?
            let artworkUrl100: String?
            let artworkUrl600: String?
            let trackViewUrl: String?
            let collectionViewUrl: String?
            let primaryGenreName: String?
            let trackTimeMillis: Int?
            let contentAdvisoryRating: String?
        }
        let results: [Result]
    }

    public func search(_ query: String, kind: ItemKind) async throws -> [Metadata] {
        let (media, entity): (String, String) = switch kind {
        case .film: ("movie", "movie")
        case .show: ("tvShow", "tvSeason")
        case .podcast: ("podcast", "podcast")
        default: ("music", "album")
        }
        guard let url = URL.api("https://itunes.apple.com/search", [
            "term": query, "media": media, "entity": entity, "limit": "10",
        ]) else { return [] }
        let response = try await http.json(Response.self, from: url)

        var seen = Set<String>()
        return response.results.compactMap { r in
            let title: String?
            switch kind {
            case .film: title = r.trackName
            case .show: title = r.artistName   // seasons are listed under the show's "artist"
            default: title = r.collectionName ?? r.trackName
            }
            guard let title, seen.insert(title.lowercased()).inserted else { return nil }

            var m = Metadata(kind: kind, title: title, provider: name)
            m.externalID = (r.trackId ?? r.collectionId).map(String.init)
            m.creator = kind == .show ? nil : r.artistName
            m.year = r.releaseDate?.leadingYear
            m.summary = r.longDescription ?? r.description?.strippingTags ?? r.shortDescription
            m.url = (r.trackViewUrl ?? r.collectionViewUrl).flatMap(URL.init(string:))
            if let art = r.artworkUrl600 ?? r.artworkUrl100 {
                m.imageURL = URL(string: art.replacingOccurrences(of: #"\d+x\d+bb"#, with: "1000x1000bb", options: .regularExpression))
            }
            if let genre = r.primaryGenreName { m.tags = [genre] }
            if let ms = r.trackTimeMillis, kind == .film { m.extra["runtime"] = Self.runtime(ms / 60_000) }
            return m
        }
    }

    static func runtime(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// The Movie Database — the best film/TV catalogue. Needs a free API key
/// (Settings → Sources). Falls back to Apple when missing.
public struct TMDBProvider: SearchProvider {
    public let name = "TMDB"
    public let kinds: Set<ItemKind> = [.film, .show]
    let apiKey: String
    let http: HTTP

    public init(apiKey: String, http: HTTP = .shared) {
        self.apiKey = apiKey
        self.http = http
    }

    struct Response: Decodable {
        struct Result: Decodable {
            let id: Int
            let media_type: String?
            let title: String?
            let name: String?
            let original_title: String?
            let release_date: String?
            let first_air_date: String?
            let overview: String?
            let poster_path: String?
            let vote_average: Double?
        }
        let results: [Result]
    }

    public func search(_ query: String, kind: ItemKind) async throws -> [Metadata] {
        let path = kind == .show ? "tv" : "movie"
        guard !apiKey.isEmpty,
              let url = URL.api("https://api.themoviedb.org/3/search/\(path)", ["query": query, "api_key": apiKey])
        else { throw MetadataError.missingConfiguration("TMDB API key") }
        let response = try await http.json(Response.self, from: url)
        return response.results.prefix(10).compactMap { r in
            guard let title = r.title ?? r.name else { return nil }
            var m = Metadata(kind: kind, title: title, provider: name, externalID: "\(path)/\(r.id)")
            m.year = (r.release_date ?? r.first_air_date)?.leadingYear
            m.summary = r.overview?.nilIfEmpty
            m.url = URL(string: "https://www.themoviedb.org/\(path)/\(r.id)")
            if let poster = r.poster_path { m.imageURL = URL(string: "https://image.tmdb.org/t/p/w780\(poster)") }
            if let vote = r.vote_average, vote > 0 { m.extra["communityRating"] = String(format: "%.1f/10", vote) }
            return m
        }
    }
}

/// IMDb answers non-browsers with an empty bot challenge, so look the title
/// up on Wikidata by its IMDb ID instead. That also tells films from shows.
public struct IMDbResolver: LinkResolver {
    let http: HTTP
    public init(http: HTTP = .shared) { self.http = http }

    /// Wikidata classes (P31) that mean "this is a show, not a film".
    static let showClasses: Set<String> = [
        "Q5398426",   // television series
        "Q1259759",   // miniseries
        "Q117467246", // animated television series
        "Q581714",    // animated series
        "Q526877",    // web series
    ]

    public func canResolve(_ url: URL) -> Bool { Self.imdbID(url) != nil }

    static func imdbID(_ url: URL) -> String? {
        guard url.hostWithoutWWW.hasSuffix("imdb.com") else { return nil }
        return url.pathComponents.first { $0.range(of: #"^tt\d+$"#, options: .regularExpression) != nil }
    }

    public func resolve(_ url: URL) async throws -> Metadata? {
        guard let imdb = Self.imdbID(url),
              let search = URL.api("https://www.wikidata.org/w/api.php", [
                  "action": "query", "list": "search", "srsearch": "haswbstatement:P345=\(imdb)", "format": "json",
              ])
        else { return nil }
        let hits = ((try await http.jsonObject(from: search))["query"] as? [String: Any])?["search"] as? [[String: Any]]
        guard let qid = hits?.first?["title"] as? String,
              let lookup = URL.api("https://www.wikidata.org/w/api.php", [
                  "action": "wbgetentities", "ids": qid, "props": "labels|claims|sitelinks",
                  "languages": "en", "sitefilter": "enwiki", "format": "json",
              ])
        else { return nil }
        let entity = ((try await http.jsonObject(from: lookup))["entities"] as? [String: Any])?[qid] as? [String: Any]
        guard let entity,
              let title = ((entity["labels"] as? [String: Any])?["en"] as? [String: Any])?["value"] as? String
        else { return nil }

        let claims = entity["claims"] as? [String: Any] ?? [:]
        func values(_ property: String) -> [Any] {
            ((claims[property] as? [[String: Any]]) ?? []).compactMap {
                (($0["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"]
            }
        }
        let classes = Set(values("P31").compactMap { ($0 as? [String: Any])?["id"] as? String })
        let kind: ItemKind = classes.isDisjoint(with: Self.showClasses) ? .film : .show

        var m = Metadata(kind: kind, title: title, provider: "IMDb", externalID: "imdb:\(imdb)")
        m.url = URL(string: "https://www.imdb.com/title/\(imdb)/")
        // P577 publication date, P580 start time (shows): "+2022-02-18T00:00:00Z".
        m.year = (values("P577") + values("P580"))
            .compactMap { (($0 as? [String: Any])?["time"] as? String)?.dropFirst().prefix(4) }
            .compactMap { Int($0) }.min()

        let wikiTitle = ((entity["sitelinks"] as? [String: Any])?["enwiki"] as? [String: Any])?["title"] as? String
        if let wikiTitle, let wiki = try? await WikipediaProvider(http: http).summary(title: wikiTitle, kind: kind) {
            m.summary = wiki.summary
            m.imageURL = wiki.imageURL
        }
        return m
    }
}

/// Keyless film search via Wikipedia, whose short descriptions read like
/// "2023 film by Celine Song" and whose infoboxes hold the poster.
/// (Apple's `media=movie` search stopped returning films in 2026.)
public struct WikipediaFilmProvider: SearchProvider {
    public let name = "Wikipedia"
    public let kinds: Set<ItemKind> = [.film]
    let http: HTTP

    public init(http: HTTP = .shared) { self.http = http }

    public func search(_ query: String, kind: ItemKind) async throws -> [Metadata] {
        // Exact-title matches first, then full-text hits for "<query> film".
        async let byTitle = pages("https://en.wikipedia.org/w/rest.php/v1/search/title", query)
        async let byText = pages("https://en.wikipedia.org/w/rest.php/v1/search/page", query + " film")
        var seen = Set<String>()
        let films = ((try? await byTitle) ?? []) + ((try? await byText) ?? [])
        let candidates = films.compactMap(Self.film(from:)).filter { seen.insert($0.externalID ?? $0.title).inserted }

        // Search results carry no posters; page summaries do. Fetch the top few.
        let top = Array(candidates.prefix(6))
        let wiki = WikipediaProvider(http: http)
        return await withTaskGroup(of: (Int, Metadata).self) { group in
            for (i, m) in top.enumerated() {
                group.addTask {
                    guard let key = m.externalID?.replacingOccurrences(of: "wiki:", with: ""),
                          let page = try? await wiki.summary(title: key, kind: .film)
                    else { return (i, m) }
                    var rich = m
                    rich.imageURL = page.imageURL
                    rich.summary = page.summary
                    return (i, rich)
                }
            }
            var out = top
            for await (i, m) in group { out[i] = m }
            return out
        }
    }

    private func pages(_ endpoint: String, _ q: String) async throws -> [[String: Any]] {
        guard let url = URL.api(endpoint, ["q": q, "limit": "10"]) else { return [] }
        return (try await http.jsonObject(from: url))["pages"] as? [[String: Any]] ?? []
    }

    /// "2019 South Korean film by Bong Joon Ho" → year 2019, creator "Bong Joon Ho".
    static func film(from page: [String: Any]) -> Metadata? {
        guard let title = page["title"] as? String, let key = page["key"] as? String,
              let description = page["description"] as? String,
              description.range(of: #"\bfilm\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
              description.range(of: #"\b(score|soundtrack|series|franchise|music|character|director|actor|actress)\b"#,
                                options: [.regularExpression, .caseInsensitive]) == nil
        else { return nil }
        // "Her (2013 film)" → "Her"
        let clean = title.replacingOccurrences(of: #"\s*\((\d{4} )?([A-Za-z ]+ )?film\)$"#, with: "", options: .regularExpression)
        var m = Metadata(kind: .film, title: clean, provider: "Wikipedia", externalID: "wiki:\(key)")
        m.year = description.range(of: #"\b(18|19|20)\d{2}\b"#, options: .regularExpression).flatMap { Int(description[$0]) }
        if let by = description.range(of: #"\b(?:by|directed by) (.+)$"#, options: .regularExpression) {
            let name = String(description[by]).replacingOccurrences(of: #"^(directed )?by "#, with: "", options: .regularExpression)
            m.creator = name.prefix(1).uppercased() + name.dropFirst()   // "the Wachowskis" → "The Wachowskis"
        }
        m.url = URL(string: "https://en.wikipedia.org/wiki/\(key)")
        return m
    }
}

/// TVmaze: keyless, accurate show search with posters and networks.
public struct TVmazeProvider: SearchProvider {
    public let name = "TVmaze"
    public let kinds: Set<ItemKind> = [.show]
    let http: HTTP

    public init(http: HTTP = .shared) { self.http = http }

    struct Hit: Decodable {
        struct Show: Decodable {
            struct Image: Decodable { let original: String?; let medium: String? }
            struct Channel: Decodable { let name: String? }
            struct Externals: Decodable { let imdb: String? }
            let id: Int
            let name: String
            let premiered: String?
            let summary: String?
            let image: Image?
            let network: Channel?
            let webChannel: Channel?
            let genres: [String]?
            let externals: Externals?
        }
        let show: Show
    }

    public func search(_ query: String, kind: ItemKind) async throws -> [Metadata] {
        guard let url = URL.api("https://api.tvmaze.com/search/shows", ["q": query]) else { return [] }
        let hits = try await http.json([Hit].self, from: url)
        return hits.prefix(10).map { hit in
            let s = hit.show
            var m = Metadata(kind: .show, title: s.name, provider: name, externalID: "tvmaze:\(s.id)")
            m.year = s.premiered?.leadingYear
            m.creator = s.network?.name ?? s.webChannel?.name
            m.summary = s.summary?.strippingTags.nilIfEmpty
            m.imageURL = (s.image?.original ?? s.image?.medium).flatMap(URL.init(string:))?.secured
            m.url = s.externals?.imdb.flatMap { URL(string: "https://www.imdb.com/title/\($0)/") }
                ?? URL(string: "https://www.tvmaze.com/shows/\(s.id)")
            m.tags = s.genres ?? []
            return m
        }
    }
}
