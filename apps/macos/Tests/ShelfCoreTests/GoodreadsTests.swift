import Foundation
import Testing
@testable import ShelfCore

struct GoodreadsTests {
    static let feed = """
    <?xml version="1.0"?>
    <rss version="2.0"><channel><title>Raj's bookshelf: all</title>
    <item>
      <title>Flowers for Algernon</title>
      <book_id>18373</book_id>
      <book_large_image_url><![CDATA[https://i.gr-assets.com/books/1689071681l/18373.jpg]]></book_large_image_url>
      <book_description><![CDATA[<b>Winner of both the Hugo and Nebula Awards.</b><br />]]></book_description>
      <book id="18373"><num_pages>311</num_pages></book>
      <author_name>Daniel Keyes</author_name>
      <isbn>015603008X</isbn>
      <user_rating>0</user_rating>
      <user_read_at></user_read_at>
      <user_date_added><![CDATA[Mon, 12 Oct 2026 13:10:32 -0700]]></user_date_added>
      <user_shelves>currently-reading, own-copy</user_shelves>
      <book_published>1966</book_published>
    </item>
    <item>
      <title>Dune (Dune Chronicles, #1)</title>
      <book_id>44767458</book_id>
      <book_large_image_url><![CDATA[https://s.gr-assets.com/assets/nophoto/book/111x148.png]]></book_large_image_url>
      <author_name>Frank Herbert</author_name>
      <user_rating>5</user_rating>
      <user_read_at><![CDATA[Sat, 01 Mar 2025 00:00:00 -0800]]></user_read_at>
      <user_shelves></user_shelves>
    </item>
    <item>
      <title>Piranesi</title>
      <book_id>50202953</book_id>
      <user_shelves>to-read</user_shelves>
    </item>
    </channel></rss>
    """

    @Test func parsesBooks() throws {
        let books = GoodreadsFeed.parse(Data(Self.feed.utf8))
        #expect(books.map(\.bookID) == ["18373", "44767458", "50202953"])

        let algernon = try #require(books.first)
        #expect(algernon.title == "Flowers for Algernon")
        #expect(algernon.author == "Daniel Keyes")
        #expect(algernon.pages == 311)
        #expect(algernon.published == 1966)
        #expect(algernon.summary == "Winner of both the Hugo and Nebula Awards.")
        #expect(algernon.status == .inProgress)
        #expect(algernon.customShelves == ["own-copy"])
        #expect(algernon.dateAdded != nil)
        #expect(algernon.metadata.url?.absoluteString == "https://www.goodreads.com/book/show/18373")
    }

    @Test func readShelfAndSeries() {
        let books = GoodreadsFeed.parse(Data(Self.feed.utf8))
        let dune = books[1]
        #expect(dune.title == "Dune")
        #expect(dune.series == "Dune Chronicles, #1")
        #expect(dune.status == .done)      // the feed leaves "read" out of the list
        #expect(dune.rating == 5)
        #expect(dune.readAt != nil)
        #expect(dune.imageURL == nil)      // Goodreads' placeholder is dropped
        #expect(books[2].status == .want)
    }

    @Test func sources() {
        #expect(GoodreadsFeed.source(from: "https://www.goodreads.com/user/show/55855190")?.userID == "55855190")
        #expect(GoodreadsFeed.source(from: "goodreads.com/user/show/55855190-raj-jain")?.userID == "55855190")
        #expect(GoodreadsFeed.source(from: "55855190")?.userID == "55855190")
        let feed = GoodreadsFeed.source(from: "https://www.goodreads.com/review/list_rss/55855190?key=abc123&shelf=read")
        #expect(feed == GoodreadsFeed.Source(userID: "55855190", key: "abc123"))
        #expect(GoodreadsFeed.source(from: "https://example.com/user/show/1") == nil)
        #expect(GoodreadsFeed.source(from: "raj") == nil)
    }
}
