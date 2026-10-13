import XCTest
@testable import ShelfCore

final class LinkClassifierTests: XCTestCase {
    private func kind(_ s: String) -> ItemKind { LinkClassifier.kind(for: URL(string: s)!) }

    func testKinds() {
        XCTAssertEqual(kind("https://www.goodreads.com/book/show/44767458-dune"), .book)
        XCTAssertEqual(kind("https://letterboxd.com/film/past-lives/"), .film)
        XCTAssertEqual(kind("https://www.imdb.com/title/tt11280740/"), .film)
        XCTAssertEqual(kind("https://www.themoviedb.org/tv/95396-severance"), .show)
        XCTAssertEqual(kind("https://arxiv.org/abs/1706.03762"), .paper)
        XCTAssertEqual(kind("https://example.com/files/paper.pdf"), .paper)
        XCTAssertEqual(kind("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .video)
        XCTAssertEqual(kind("https://podcasts.apple.com/us/podcast/x/id123"), .podcast)
        XCTAssertEqual(kind("https://open.spotify.com/album/abc"), .music)
        XCTAssertEqual(kind("https://www.google.com/maps/place/Blue+Bottle"), .place)
        XCTAssertEqual(kind("https://www.google.com/search?q=why+is+the+sky+blue"), .curiosity)
        XCTAssertEqual(kind("https://en.wikipedia.org/wiki/Rayleigh_scattering"), .curiosity)
        XCTAssertEqual(kind("https://paulgraham.com/greatwork.html"), .article)
    }

    func testGoogleQuery() {
        let url = URL(string: "https://www.google.com/search?q=why+is+the+sky+blue&oq=why")!
        XCTAssertEqual(LinkClassifier.googleSearchQuery(url), "why is the sky blue")
        XCTAssertNil(LinkClassifier.googleSearchQuery(URL(string: "https://www.google.com/maps")!))
    }

    func testArxivID() {
        XCTAssertEqual(LinkClassifier.arxivID(URL(string: "https://arxiv.org/abs/1706.03762v7")!), "1706.03762")
        XCTAssertEqual(LinkClassifier.arxivID(URL(string: "https://arxiv.org/pdf/2303.08774")!), "2303.08774")
        XCTAssertNil(LinkClassifier.arxivID(URL(string: "https://example.com/abs/1706.03762")!))
    }

    func testDOI() {
        XCTAssertEqual(LinkClassifier.doi(in: "https://doi.org/10.1038/nature14539"), "10.1038/nature14539")
        XCTAssertEqual(LinkClassifier.doi(in: "see (10.1145/3290605.3300233)."), "10.1145/3290605.3300233")
    }

    func testYouTubeID() {
        XCTAssertEqual(LinkClassifier.youtubeID(URL(string: "https://youtu.be/abc123")!), "abc123")
        XCTAssertEqual(LinkClassifier.youtubeID(URL(string: "https://www.youtube.com/shorts/xyz")!), "xyz")
    }

    func testFirstURL() {
        XCTAssertEqual(LinkClassifier.firstURL(in: "  https://example.com/a  ")?.absoluteString, "https://example.com/a")
        XCTAssertTrue(LinkClassifier.isBareURL("https://example.com"))
        XCTAssertFalse(LinkClassifier.isBareURL("read this https://example.com"))
        XCTAssertFalse(LinkClassifier.isBareURL("dune"))
    }
}
