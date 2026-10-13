import XCTest
@testable import ShelfCore

final class HTMLMetadataParserTests: XCTestCase {
    func testOpenGraphAndEntities() {
        let html = """
        <html><head>
        <title>Ignored &amp; fallback</title>
        <meta content="The Art of Noticing &#8212; A Field Guide" property="og:title">
        <meta property='og:image' content='/img/cover.jpg' />
        <meta name="description" content="A small essay.">
        <meta property="og:site_name" content="Example">
        <link rel="canonical" href="https://example.com/noticing">
        </head><body></body></html>
        """
        let url = URL(string: "https://example.com/noticing?utm_source=x")!
        let page = HTMLMetadataParser().parse(html, baseURL: url)
        let m = page.metadata(for: url, guessedKind: .article)
        XCTAssertEqual(m.title, "The Art of Noticing — A Field Guide")
        XCTAssertEqual(m.imageURL?.absoluteString, "https://example.com/img/cover.jpg")
        XCTAssertEqual(m.summary, "A small essay.")
        XCTAssertEqual(m.url?.absoluteString, "https://example.com/noticing")
        XCTAssertEqual(m.provider, "Example")
    }

    func testLetterboxdStyleJSONLD() {
        let html = """
        <html><head>
        <meta property="og:title" content="Past Lives (2023)">
        <meta name="twitter:label1" content="Directed by"><meta name="twitter:data1" content="Celine Song">
        </head><body>
        <script type="application/ld+json">
        /* <![CDATA[ */
        {"@context":"http://schema.org","@type":"Movie","name":"Past Lives",
         "image":"https://a.ltrbxd.com/poster.jpg","director":[{"@type":"Person","name":"Celine Song"}],
         "dateCreated":"2023-01-21","genre":["Drama","Romance"]}
        /* ]]> */
        </script></body></html>
        """
        let url = URL(string: "https://letterboxd.com/film/past-lives/")!
        let m = HTMLMetadataParser().parse(html, baseURL: url).metadata(for: url, guessedKind: .film)
        XCTAssertEqual(m.kind, .film)
        XCTAssertEqual(m.title, "Past Lives")
        XCTAssertEqual(m.creator, "Celine Song")
        XCTAssertEqual(m.year, 2023)
        XCTAssertEqual(m.imageURL?.absoluteString, "https://a.ltrbxd.com/poster.jpg")
        XCTAssertEqual(m.tags, ["Drama", "Romance"])
    }

    func testGoodreadsStyleBook() {
        let html = """
        <head><script type="application/ld+json">{"@context":"https://schema.org","@type":"Book",
        "name":"Dune","image":"https://images.gr-assets.com/dune.jpg","numberOfPages":658,
        "author":[{"@type":"Person","name":"Frank Herbert"}]}</script></head>
        """
        let url = URL(string: "https://www.goodreads.com/book/show/44767458-dune")!
        let m = HTMLMetadataParser().parse(html, baseURL: url).metadata(for: url, guessedKind: .book)
        XCTAssertEqual(m.kind, .book)
        XCTAssertEqual(m.title, "Dune")
        XCTAssertEqual(m.creator, "Frank Herbert")
        XCTAssertEqual(m.extra["pages"], "658")
    }

    func testCitationTagsMakeAPaper() {
        let html = """
        <head><meta name="citation_title" content="Deep learning">
        <meta name="citation_author" content="LeCun, Yann"><meta name="citation_doi" content="10.1038/nature14539">
        <meta name="citation_journal_title" content="Nature"><meta name="citation_publication_date" content="2015/05/28"></head>
        """
        let url = URL(string: "https://www.nature.com/articles/nature14539")!
        let m = HTMLMetadataParser().parse(html, baseURL: url).metadata(for: url, guessedKind: .paper)
        XCTAssertEqual(m.kind, .paper)
        XCTAssertEqual(m.title, "Deep learning")
        XCTAssertEqual(m.extra["doi"], "10.1038/nature14539")
        XCTAssertEqual(m.extra["venue"], "Nature")
        XCTAssertEqual(m.year, 2015)
    }
}
