import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One book from a Goodreads shelf feed.
public struct GoodreadsBook: Equatable, Sendable {
    public var bookID: String
    public var title: String
    /// "(Dune Chronicles, #1)" split off the title.
    public var series: String?
    public var author: String?
    public var imageURL: URL?
    public var summary: String?
    public var pages: Int?
    public var isbn: String?
    public var published: Int?
    /// 0 when unrated.
    public var rating: Int
    public var readAt: Date?
    public var dateAdded: Date?
    /// Every shelf the book is on, as Goodreads names them.
    public var shelves: [String]

    public init(bookID: String, title: String, series: String? = nil, author: String? = nil, imageURL: URL? = nil,
                summary: String? = nil, pages: Int? = nil, isbn: String? = nil, published: Int? = nil,
                rating: Int = 0, readAt: Date? = nil, dateAdded: Date? = nil, shelves: [String] = []) {
        self.bookID = bookID; self.title = title; self.series = series; self.author = author
        self.imageURL = imageURL; self.summary = summary; self.pages = pages; self.isbn = isbn
        self.published = published; self.rating = rating; self.readAt = readAt
        self.dateAdded = dateAdded; self.shelves = shelves
    }

    static let exclusiveShelves: Set<String> = ["to-read", "currently-reading", "read"]

    /// Goodreads' exclusive shelves map onto Shelf's statuses. The feed
    /// leaves "read" out of the list, so a book on neither of the other two
    /// has been read.
    public var status: ItemStatus {
        if shelves.contains("currently-reading") { return .inProgress }
        if shelves.contains("to-read") { return .want }
        return .done
    }

    /// Your own shelves ("own-copy", "sci-fi"), which become tags.
    public var customShelves: [String] {
        shelves.filter { !Self.exclusiveShelves.contains($0) }
    }

    public var url: URL { URL(string: "https://www.goodreads.com/book/show/\(bookID)")! }

    public var metadata: Metadata {
        var m = Metadata(kind: .book, title: title, subtitle: series, creator: author, year: published,
                         summary: summary, imageURL: imageURL, url: url, provider: "Goodreads",
                         externalID: "goodreads:\(bookID)")
        if let pages { m.extra["pages"] = String(pages) }
        if let isbn { m.extra["isbn"] = isbn }
        return m
    }
}

/// Reads a Goodreads profile's shelves through its RSS feeds — the one
/// door Goodreads left open after retiring its API (December 2020).
/// Public profiles need only the user ID; private ones need the feed's key.
public enum GoodreadsFeed {
    public struct Source: Equatable, Sendable {
        public var userID: String
        public var key: String?
    }

    /// Accepts a profile link, a feed link (with `key=` for private
    /// profiles) or a bare ID: ".../user/show/55855190-raj" → 55855190.
    public static func source(from input: String) -> Source? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"^\d+$"#, options: .regularExpression) != nil { return Source(userID: text) }
        guard let components = URLComponents(string: text.hasPrefix("http") ? text : "https://" + text),
              components.host?.hasSuffix("goodreads.com") == true
        else { return nil }
        let path = components.path
        guard let match = path.range(of: #"/(user/show|review/list_rss|review/list|user/\w+)/(\d+)"#,
                                     options: .regularExpression) else { return nil }
        let id = String(path[match]).components(separatedBy: "/").last.map { $0.prefix { $0.isNumber } }.map(String.init)
        guard let id, !id.isEmpty else { return nil }
        let key = components.queryItems?.first { $0.name == "key" }?.value
        return Source(userID: id, key: key)
    }

    public static func feedURL(_ source: Source, page: Int, perPage: Int = 200) -> URL? {
        var query = ["shelf": "#ALL#", "per_page": String(perPage), "page": String(page)]
        if let key = source.key { query["key"] = key }
        return URL.api("https://www.goodreads.com/review/list_rss/\(source.userID)", query)
    }

    /// Every book on every shelf, following pages until one comes back short.
    public static func fetchAll(_ source: Source, http: HTTP = .shared) async throws -> [GoodreadsBook] {
        var books: [GoodreadsBook] = []
        for page in 1...50 {
            guard let url = feedURL(source, page: page) else { break }
            let (data, _) = try await http.data(url, accept: "application/rss+xml, application/xml")
            let batch = parse(data)
            books += batch
            if batch.count < 150 { break }
        }
        // A book can show up twice when pages shift mid-fetch.
        var seen = Set<String>()
        return books.filter { seen.insert($0.bookID).inserted }
    }

    public static func parse(_ data: Data) -> [GoodreadsBook] {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.books
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()
}

private final class FeedParser: NSObject, XMLParserDelegate {
    var books: [GoodreadsBook] = []
    private var fields: [String: String]?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "item" { fields = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        text += String(data: data, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard fields != nil else { return }
        if name == "item" {
            if let book = makeBook(fields ?? [:]) { books.append(book) }
            fields = nil
            return
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep the first value: <book_id> and the nested <book id=…> both exist.
        if !value.isEmpty, fields?[name] == nil { fields?[name] = value }
        text = ""
    }

    private func makeBook(_ f: [String: String]) -> GoodreadsBook? {
        guard let id = f["book_id"], var title = f["title"] else { return nil }
        var series: String?
        if let r = title.range(of: #"\s*\(([^()]*#\s*[\d.]+)\)\s*$"#, options: .regularExpression) {
            series = String(title[r]).trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
            title = String(title[..<r.lowerBound])
        }
        let image = (f["book_large_image_url"] ?? f["book_image_url"]).flatMap(URL.init(string:))
        let date = { (key: String) in f[key].flatMap(GoodreadsFeed.dateFormatter.date(from:)) }
        return GoodreadsBook(
            bookID: id,
            title: title.trimmingCharacters(in: .whitespaces),
            series: series,
            author: f["author_name"],
            // Goodreads' "no cover" placeholder is worse than our own.
            imageURL: image?.absoluteString.contains("nophoto") == true ? nil : image,
            summary: f["book_description"]?.strippingTags.nilIfEmpty,
            pages: f["num_pages"].flatMap(Int.init),
            isbn: f["isbn"],
            published: f["book_published"].flatMap(Int.init),
            rating: f["user_rating"].flatMap(Int.init) ?? 0,
            readAt: date("user_read_at"),
            dateAdded: date("user_date_added") ?? date("user_date_created"),
            shelves: (f["user_shelves"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        )
    }
}
