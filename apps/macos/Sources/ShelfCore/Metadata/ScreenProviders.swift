import Foundation

/// Apple's iTunes Search API — keyless posters & artwork for films, shows,
/// podcasts and albums.
public struct ITunesProvider: SearchProvider {
    public let name = "Apple"
    public let kinds: Set<ItemKind> = [.film, .show, .podcast, .music]
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
