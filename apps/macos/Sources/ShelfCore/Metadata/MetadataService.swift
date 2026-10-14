import Foundation

/// YouTube's oEmbed endpoint: reliable titles + thumbnails without the
/// consent-wall pages the HTML sometimes serves.
public struct YouTubeResolver: LinkResolver {
    let http: HTTP
    public init(http: HTTP = .shared) { self.http = http }

    public func canResolve(_ url: URL) -> Bool { LinkClassifier.youtubeID(url) != nil }

    public func resolve(_ url: URL) async throws -> Metadata? {
        guard let id = LinkClassifier.youtubeID(url),
              let api = URL.api("https://www.youtube.com/oembed", ["url": url.absoluteString, "format": "json"])
        else { return nil }
        let json = try await http.jsonObject(from: api)
        guard let title = json["title"] as? String else { return nil }
        var m = Metadata(kind: .video, title: title, provider: "YouTube", externalID: "youtube:\(id)")
        m.creator = json["author_name"] as? String
        m.url = URL(string: "https://www.youtube.com/watch?v=\(id)")
        m.imageURL = URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")
        return m
    }
}

/// The one entry point the app talks to: "search for this" and
/// "tell me about this link". Fans out to providers concurrently and
/// always returns *something* usable, even offline.
public struct MetadataService: Sendable {
    public var searchProviders: [any SearchProvider]
    public var resolvers: [any LinkResolver]
    let http: HTTP

    public init(searchProviders: [any SearchProvider], resolvers: [any LinkResolver], http: HTTP = .shared) {
        self.searchProviders = searchProviders
        self.resolvers = resolvers
        self.http = http
    }

    /// The default line-up. `extraProviders` lets the app add native sources
    /// (e.g. MapKit for places) that can't live in this portable module.
    public static func standard(tmdbAPIKey: String? = nil, extraProviders: [any SearchProvider] = []) -> MetadataService {
        var providers: [any SearchProvider] = []
        if let key = tmdbAPIKey?.trimmed, !key.isEmpty { providers.append(TMDBProvider(apiKey: key)) }
        providers += [
            OpenLibraryProvider(), GoogleBooksProvider(), ITunesProvider(),
            WikipediaFilmProvider(), TVmazeProvider(),
            ArxivProvider(), CrossrefProvider(), WikipediaProvider(),
        ]
        providers += extraProviders
        return MetadataService(
            searchProviders: providers,
            resolvers: [ArxivProvider(), CrossrefProvider(), YouTubeResolver(), IMDbResolver(), WikipediaProvider()]
        )
    }

    // MARK: Search

    /// Searches every provider that knows about `kind`, interleaving results
    /// so the best hit from each source shows up near the top.
    public func search(_ query: String, kind: ItemKind) async -> [Metadata] {
        let query = query.trimmed
        guard query.count >= 2 else { return [] }
        let providers = searchProviders.filter { $0.kinds.contains(kind) }

        let batches: [[Metadata]] = await withTaskGroup(of: (Int, [Metadata]).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    let results = (try? await provider.search(query, kind: kind)) ?? []
                    return (index, results)
                }
            }
            var collected = Array(repeating: [Metadata](), count: providers.count)
            for await (index, results) in group { collected[index] = results }
            return collected
        }
        return Self.interleave(batches)
    }

    static func interleave(_ batches: [[Metadata]]) -> [Metadata] {
        var seen = Set<String>()
        var out: [Metadata] = []
        let longest = batches.map(\.count).max() ?? 0
        for i in 0..<longest {
            for batch in batches where i < batch.count {
                let m = batch[i]
                let key = m.title.lowercased().filter { $0.isLetter || $0.isNumber } + "|" + (m.year.map(String.init) ?? "")
                if seen.insert(key).inserted {
                    out.append(m)
                } else if let existing = out.firstIndex(where: {
                    $0.title.lowercased().filter { $0.isLetter || $0.isNumber } + "|" + ($0.year.map(String.init) ?? "") == key
                }) {
                    // Same work from another source: keep the first, fill its gaps.
                    out[existing] = out[existing].merged(with: m)
                }
            }
        }
        return out
    }

    // MARK: Resolve

    /// Everything we can learn about a link. Never throws: on failure you
    /// get a tidy fallback built from the URL itself.
    public func resolve(_ url: URL, hint: ItemKind? = nil) async -> Metadata {
        let guessed = hint ?? LinkClassifier.kind(for: url)

        if let query = LinkClassifier.googleSearchQuery(url) {
            var m = Metadata(kind: .curiosity, title: query, url: url, provider: "Search")
            if let wiki = try? await WikipediaProvider(http: http).summary(title: query) {
                m.subtitle = wiki.subtitle
                m.summary = wiki.summary
                m.imageURL = wiki.imageURL
            }
            return m
        }

        for resolver in resolvers where resolver.canResolve(url) {
            if var m = try? await resolver.resolve(url) {
                if let hint { m.kind = hint }
                return await enrich(m)
            }
        }

        // A DOI hiding inside a publisher URL?
        if guessed == .paper, let doi = LinkClassifier.doi(in: url.absoluteString),
           let m = try? await CrossrefProvider(http: http).resolve(doi: doi) {
            return m
        }

        var result: Metadata
        if url.path.lowercased().hasSuffix(".pdf") {
            result = Self.fallback(for: url, kind: guessed)
        } else if let fetched = try? await http.data(url, accept: "text/html,application/xhtml+xml"),
                  let html = String(data: fetched.0, encoding: .utf8) ?? String(data: fetched.0, encoding: .isoLatin1),
                  case let page = HTMLMetadataParser().parse(html, baseURL: fetched.1),
                  case let parsed = page.metadata(for: fetched.1, guessedKind: guessed),
                  // Bot walls (Goodreads, IMDb) send an empty page: no title but the URL itself.
                  parsed.title != fetched.1.absoluteString, parsed.title != url.absoluteString {
            result = parsed
            result.url = result.url ?? url
            // Academic landing pages often carry a DOI: upgrade via Crossref.
            if result.kind == .paper, let doi = result.extra["doi"],
               let rich = try? await CrossrefProvider(http: http).resolve(doi: doi) {
                result = rich.merged(with: result)
            }
        } else {
            result = Self.fallback(for: url, kind: guessed)
            return await enrich(result, trustCatalogTitle: true)
        }
        return await enrich(result)
    }

    /// Fills missing covers/authors by asking a catalogue about the title.
    /// `trustCatalogTitle` is for slug-derived guesses: "Flowers For Algernon"
    /// should become the catalogue's "Flowers for Algernon".
    public func enrich(_ metadata: Metadata, trustCatalogTitle: Bool = false) async -> Metadata {
        let needsHelp = metadata.imageURL == nil || metadata.creator == nil || metadata.year == nil
        guard needsHelp else { return metadata }
        let query = [metadata.title, metadata.creator].compactMap { $0 }.joined(separator: " ")
        let provider: (any SearchProvider)?
        switch metadata.kind {
        case .book:
            provider = OpenLibraryProvider(http: http)
        case .film:
            provider = searchProviders.first { $0 is TMDBProvider } ?? WikipediaFilmProvider(http: http)
        case .show:
            provider = searchProviders.first { $0 is TMDBProvider } ?? TVmazeProvider(http: http)
        case .podcast, .music:
            provider = ITunesProvider(http: http)
        default:
            provider = nil
        }
        guard let provider,
              let best = try? await provider.search(query, kind: metadata.kind).first(where: { Self.similar($0.title, metadata.title) })
        else { return metadata }
        var merged = metadata.merged(with: best)
        if trustCatalogTitle { merged.title = best.title }
        return merged
    }

    /// What a loosely typed title ("flowers of algernon") most likely means,
    /// or nil when nothing in the catalogues is a confident match.
    public func bestMatch(for title: String, kind: ItemKind) async -> Metadata? {
        if let hit = await search(title, kind: kind).first(where: { Self.sameWords($0.title, title) }) { return hit }
        // Small words are where typos hide: retry with just the big ones.
        let core = Self.words(title).joined(separator: " ")
        guard !core.isEmpty, core != title.lowercased() else { return nil }
        return await search(core, kind: kind).first { Self.sameWords($0.title, title) }
    }

    static let smallWords: Set<String> = ["a", "an", "the", "of", "for", "and", "in", "on", "to", "at", "by", "with"]

    static func words(_ s: String) -> [String] {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !smallWords.contains($0) }
    }

    /// Same significant words, ignoring order, case, punctuation and filler.
    static func sameWords(_ a: String, _ b: String) -> Bool {
        let wa = Set(words(a)), wb = Set(words(b))
        guard !wa.isEmpty, !wb.isEmpty else { return false }
        return Double(wa.intersection(wb).count) / Double(wa.union(wb).count) >= 0.75
    }

    static func similar(_ a: String, _ b: String) -> Bool {
        let na = a.lowercased().filter { $0.isLetter || $0.isNumber }
        let nb = b.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !na.isEmpty, !nb.isEmpty else { return false }
        return na == nb || na.hasPrefix(nb) || nb.hasPrefix(na)
    }

    /// "https://example.com/blog/the-art-of-noticing" -> "The Art Of Noticing",
    /// "goodreads.com/book/show/18373.Flowers_for_Algernon" -> "Flowers for Algernon"
    public static func fallback(for url: URL, kind: ItemKind) -> Metadata {
        let fileExtensions: Set<String> = ["html", "htm", "php", "asp", "aspx", "pdf"]
        var slug = fileExtensions.contains(url.pathExtension.lowercased())
            ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        // Drop a leading numeric ID: "18373.Flowers…", "44767458-dune".
        slug = slug.replacingOccurrences(of: #"^\d+[.\-_]"#, with: "", options: .regularExpression)
        let words = slug.replacingOccurrences(of: #"[-_+]+"#, with: " ", options: .regularExpression).trimmed
        // "tt11280740" or "a8f3c2" is an ID, not a title: want a real word in there.
        let looksLikeWords = words.count > 3 && words.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil
        // Keep the slug's own casing when it has any; only title-case all-lowercase slugs.
        let cased = words == words.lowercased() ? words.capitalized : words
        let title = looksLikeWords ? cased : url.hostWithoutWWW
        return Metadata(kind: kind, title: title, url: url, provider: url.hostWithoutWWW)
    }
}
