import Foundation

/// Guesses what a URL points at from its shape alone — instant, offline.
public enum LinkClassifier {
    public static func kind(for url: URL) -> ItemKind {
        let host = url.hostWithoutWWW
        let path = url.path.lowercased()

        func on(_ domains: String...) -> Bool {
            domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }

        // Things you Googled become curiosities, titled by the query.
        if googleSearchQuery(url) != nil { return .curiosity }

        if on("goodreads.com", "openlibrary.org", "thestorygraph.com", "bookshop.org", "literal.club")
            || (on("books.google.com") || (on("google.com") && path.hasPrefix("/books")))
            || (on("amazon.com", "amazon.co.uk", "amazon.in") && path.contains("/dp/") && url.absoluteString.contains("book")) {
            return .book
        }
        if on("letterboxd.com") { return path.hasPrefix("/film") || path.contains("/film/") ? .film : .article }
        if on("imdb.com"), path.hasPrefix("/title") { return .film }
        if on("themoviedb.org") { return path.hasPrefix("/tv") ? .show : .film }
        if on("trakt.tv", "tvmaze.com", "serializd.com") { return .show }
        if on("tv.apple.com") { return path.contains("/show/") ? .show : .film }
        if on("netflix.com", "primevideo.com", "hulu.com", "max.com", "disneyplus.com") { return .show }

        if on("arxiv.org", "doi.org", "semanticscholar.org", "openreview.net", "aclanthology.org",
              "biorxiv.org", "medrxiv.org", "ssrn.com", "pubmed.ncbi.nlm.nih.gov", "ncbi.nlm.nih.gov",
              "dl.acm.org", "ieeexplore.ieee.org", "nature.com", "science.org", "jstor.org",
              "researchgate.net", "scholar.google.com", "paperswithcode.com", "paperswithcode.co", "proceedings.neurips.cc",
              "proceedings.mlr.press", "papers.nips.cc", "springer.com", "sciencedirect.com", "pnas.org")
            || path.hasSuffix(".pdf") {
            return .paper
        }

        if on("youtube.com", "youtu.be", "vimeo.com", "nebula.tv", "twitch.tv") { return .video }
        if on("podcasts.apple.com", "overcast.fm", "pocketcasts.com", "castro.fm")
            || (on("open.spotify.com") && (path.hasPrefix("/show") || path.hasPrefix("/episode"))) {
            return .podcast
        }
        if on("music.apple.com", "bandcamp.com", "soundcloud.com", "tidal.com", "rateyourmusic.com", "discogs.com")
            || (on("open.spotify.com") && (path.hasPrefix("/album") || path.hasPrefix("/track") || path.hasPrefix("/artist"))) {
            return .music
        }
        if on("maps.apple.com", "maps.app.goo.gl", "yelp.com", "tripadvisor.com", "atlasobscura.com", "beliapp.com")
            || (on("google.com") && path.hasPrefix("/maps"))
            || (host == "goo.gl" && path.hasPrefix("/maps")) {
            return .place
        }
        if on("wikipedia.org") { return .curiosity }
        return .article
    }

    /// "https://www.google.com/search?q=why+is+the+sky+blue" -> "why is the sky blue"
    public static func googleSearchQuery(_ url: URL) -> String? {
        let host = url.hostWithoutWWW
        let isSearchEngine = host.hasPrefix("google.") || host == "duckduckgo.com" || host == "bing.com"
            || host == "kagi.com" || host == "perplexity.ai"
        guard isSearchEngine, url.path == "/search" || host == "duckduckgo.com" else { return nil }
        return url.formValue("q")?.trimmed.nilIfEmpty
    }

    /// Finds the first http(s) URL in arbitrary text (clipboard, selection).
    public static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmed
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), url.host != nil, !trimmed.contains(" ") {
            return url
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let ns = trimmed as NSString
        let match = detector.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length))
        guard let url = match?.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    /// True when text is "just a link" rather than prose that contains one.
    public static func isBareURL(_ text: String) -> Bool {
        let t = text.trimmed
        return !t.contains(" ") && firstURL(in: t) != nil
    }

    // MARK: Identifiers

    /// "https://arxiv.org/abs/1706.03762v7" / ".../pdf/1706.03762" -> "1706.03762"
    public static func arxivID(_ url: URL) -> String? {
        guard url.hostWithoutWWW.hasSuffix("arxiv.org") else { return nil }
        let path = url.path
        guard let r = path.range(of: #"(\d{4}\.\d{4,5})(v\d+)?|([a-z\-]+(\.[A-Z]{2})?/\d{7})"#, options: .regularExpression)
        else { return nil }
        var id = String(path[r])
        if let v = id.range(of: #"v\d+$"#, options: .regularExpression) { id.removeSubrange(v) }
        return id
    }

    /// Finds a DOI in a URL or string: "10.1038/nature14539".
    public static func doi(in text: String) -> String? {
        let decoded = text.removingPercentEncoding ?? text
        guard let r = decoded.range(of: #"10\.\d{4,9}/[^\s"<>?#]+"#, options: .regularExpression) else { return nil }
        var doi = String(decoded[r])
        while let last = doi.last, ".,;)".contains(last) { doi.removeLast() }
        return doi
    }

    public static func youtubeID(_ url: URL) -> String? {
        let host = url.hostWithoutWWW
        if host == "youtu.be" { return url.pathComponents.dropFirst().first }
        if host.hasSuffix("youtube.com") {
            if let v = url.queryValue("v") { return v }
            let parts = url.pathComponents
            if let i = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }), i + 1 < parts.count {
                return parts[i + 1]
            }
        }
        return nil
    }
}
