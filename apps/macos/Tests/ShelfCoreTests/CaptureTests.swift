import XCTest
@testable import ShelfCore

final class CaptureTests: XCTestCase {
    func testDeepLinkRoundTrip() throws {
        let request = CaptureRequest(url: URL(string: "https://arxiv.org/abs/1706.03762")!, title: "Attention & You",
                                     note: "for the reading group", kind: .paper, status: .done, tags: ["ml", "classics"])
        let link = try XCTUnwrap(DeepLink.addURL(for: request))
        let parsed = try XCTUnwrap(CaptureRequest(deepLink: link))
        XCTAssertEqual(parsed, request)
    }

    func testDeepLinkFromBrowserFormEncoding() throws {
        // What the extension's URLSearchParams produces.
        let link = URL(string: "shelf://add?url=https%3A%2F%2Fletterboxd.com%2Ffilm%2Fpast-lives%2F&title=Past+Lives+%26+Me")!
        let parsed = try XCTUnwrap(CaptureRequest(deepLink: link))
        XCTAssertEqual(parsed.title, "Past Lives & Me")
        XCTAssertEqual(parsed.url?.absoluteString, "https://letterboxd.com/film/past-lives/")
    }

    func testDeepLinkRejectsOtherActions() {
        XCTAssertNil(CaptureRequest(deepLink: URL(string: "shelf://open?id=1")!))
        XCTAssertNil(CaptureRequest(deepLink: URL(string: "https://add?url=x")!))
        XCTAssertNil(CaptureRequest(deepLink: URL(string: "shelf://add")!))
    }

    func testLooseText() {
        XCTAssertEqual(CaptureRequest(text: " https://example.com/x ").url?.absoluteString, "https://example.com/x")
        let question = CaptureRequest(text: "why do cats purr")
        XCTAssertNil(question.url)
        XCTAssertEqual(question.title, "why do cats purr")
    }

    func testHTTPParsing() throws {
        let body = #"{"url":"https://example.com"}"#
        let raw = "POST /v1/items?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Shelf-Token: abc\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard case .complete(let req) = LocalAPI.parse(Data(raw.utf8)) else { return XCTFail("expected complete") }
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/v1/items")
        XCTAssertEqual(req.headers["x-shelf-token"], "abc")
        let capture = try JSONDecoder().decode(CaptureRequest.self, from: req.body)
        XCTAssertEqual(capture.url?.absoluteString, "https://example.com")

        let partial = "POST /v1/items HTTP/1.1\r\nContent-Length: 50\r\n\r\n{\"url\""
        guard case .needMoreData = LocalAPI.parse(Data(partial.utf8)) else { return XCTFail("expected needMoreData") }
    }

    func testTokens() {
        let token = LocalAPI.makeToken()
        XCTAssertEqual(token.count, 23)
        XCTAssertTrue(LocalAPI.tokensMatch(token, token))
        XCTAssertFalse(LocalAPI.tokensMatch("nope", token))
        XCTAssertFalse(LocalAPI.tokensMatch(nil, token))
    }

    func testArchiveRoundTrip() throws {
        let record = ItemRecord(kind: .book, status: .done, title: "Dune", creator: "Frank Herbert", rating: 5, tags: ["sci-fi"])
        let data = try ShelfArchive.encoder.encode(ShelfArchive(items: [record]))
        let decoded = try ShelfArchive.decoder.decode(ShelfArchive.self, from: data)
        XCTAssertEqual(decoded.items.first?.title, "Dune")
        XCTAssertEqual(decoded.items.first?.rating, 5)
        XCTAssertEqual(decoded.version, ShelfArchive.currentVersion)
    }

    func testInterleaveDedupes() {
        let a = [Metadata(kind: .book, title: "Dune", year: 1965, provider: "A"),
                 Metadata(kind: .book, title: "Dune Messiah", year: 1969, provider: "A")]
        let b = [Metadata(kind: .book, title: "Dune", creator: "Frank Herbert", year: 1965, provider: "B")]
        let merged = MetadataService.interleave([a, b])
        XCTAssertEqual(merged.map(\.title), ["Dune", "Dune Messiah"])
        XCTAssertEqual(merged.first?.creator, "Frank Herbert")
    }
}
