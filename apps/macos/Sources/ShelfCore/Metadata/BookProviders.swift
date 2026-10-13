import Foundation

/// openlibrary.org — free, keyless, great covers.
public struct OpenLibraryProvider: SearchProvider {
    public let name = "Open Library"
    public let kinds: Set<ItemKind> = [.book]
    let http: HTTP

    public init(http: HTTP = .shared) { self.http = http }

    struct Response: Decodable {
        struct Doc: Decodable {
            let key: String
            let title: String
            let subtitle: String?
            let author_name: [String]?
            let first_publish_year: Int?
            let cover_i: Int?
            let number_of_pages_median: Int?
            let subject: [String]?
            let first_sentence: [String]?
        }
        let docs: [Doc]
    }

    public func search(_ query: String, kind: ItemKind) async throws -> [Metadata] {
        guard let url = URL.api("https://openlibrary.org/search.json", [
            "q": query, "limit": "8",
            "fields": "key,title,subtitle,author_name,first_publish_year,cover_i,number_of_pages_median,subject,first_sentence",
        ]) else { return [] }
        let response = try await http.json(Response.self, from: url)
        return response.docs.map { doc in
            var m = Metadata(kind: .book, title: doc.title, provider: name, externalID: doc.key)
            m.subtitle = doc.subtitle
            m.creator = doc.author_name?.prefix(2).joined(separator: ", ")
            m.year = doc.first_publish_year
            m.url = URL(string: "https://openlibrary.org\(doc.key)")
            if let cover = doc.cover_i { m.imageURL = URL(string: "https://covers.openlibrary.org/b/id/\(cover)-L.jpg") }
            if let pages = doc.number_of_pages_median { m.extra["pages"] = String(pages) }
            m.summary = doc.first_sentence?.first
            m.tags = Array((doc.subject ?? []).prefix(3))
            return m
        }
    }
}

/// Google Books — broad catalogue with descriptions. Keyless for light use.
public struct GoogleBooksProvider: SearchProvider {
    public let name = "Google Books"
    public let kinds: Set<ItemKind> = [.book]
    let http: HTTP

    public init(http: HTTP = .shared) { self.http = http }

    struct Response: Decodable {
        struct Item: Decodable {
            struct Info: Decodable {
                struct Images: Decodable { let thumbnail: String?; let smallThumbnail: String? }
                let title: String
                let subtitle: String?
                let authors: [String]?
                let publishedDate: String?
                let description: String?
                let pageCount: Int?
                let categories: [String]?
                let imageLinks: Images?
                let infoLink: String?
            }
            let id: String
            let volumeInfo: Info
        }
        let items: [Item]?
    }

    public func search(_ query: String, kind: ItemKind) async throws -> [Metadata] {
        guard let url = URL.api("https://www.googleapis.com/books/v1/volumes", [
            "q": query, "maxResults": "8", "printType": "books",
        ]) else { return [] }
        let response = try await http.json(Response.self, from: url)
        return (response.items ?? []).map { item in
            let info = item.volumeInfo
            var m = Metadata(kind: .book, title: info.title, provider: name, externalID: item.id)
            m.subtitle = info.subtitle
            m.creator = info.authors?.prefix(2).joined(separator: ", ")
            m.year = info.publishedDate?.leadingYear
            m.summary = info.description?.strippingTags
            m.url = info.infoLink.flatMap(URL.init(string:))?.secured
            if let thumb = info.imageLinks?.thumbnail ?? info.imageLinks?.smallThumbnail {
                // Ask for a larger rendition and drop the page-curl effect.
                let large = thumb.replacingOccurrences(of: "zoom=1", with: "zoom=2")
                    .replacingOccurrences(of: "&edge=curl", with: "")
                m.imageURL = URL(string: large)?.secured
            }
            if let pages = info.pageCount, pages > 0 { m.extra["pages"] = String(pages) }
            m.tags = Array((info.categories ?? []).prefix(3))
            return m
        }
    }
}
