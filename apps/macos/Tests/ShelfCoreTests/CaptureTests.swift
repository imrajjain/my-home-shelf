import Foundation
import Testing
@testable import ShelfCore

struct CaptureTests {
    @Test func deepLinkRoundTrip() throws {
        let request = CaptureRequest(url: URL(string: "https://arxiv.org/abs/1706.03762")!, title: "Attention & You",
                                     note: "for the reading group", kind: .paper, status: .done, tags: ["ml", "classics"])
        let link = try #require(DeepLink.addURL(for: request))
        let parsed = try #require(CaptureRequest(deepLink: link))
        #expect(parsed == request)
    }

    @Test func deepLinkFromBrowserFormEncoding() throws {
        // What the extension's URLSearchParams produces.
        let link = URL(string: "shelf://add?url=https%3A%2F%2Fletterboxd.com%2Ffilm%2Fpast-lives%2F&title=Past+Lives+%26+Me")!
        let parsed = try #require(CaptureRequest(deepLink: link))
        #expect(parsed.title == "Past Lives & Me")
        #expect(parsed.url?.absoluteString == "https://letterboxd.com/film/past-lives/")
    }

    @Test func deepLinkRejectsOtherActions() {
        #expect(CaptureRequest(deepLink: URL(string: "shelf://open?id=1")!) == nil)
        #expect(CaptureRequest(deepLink: URL(string: "https://add?url=x")!) == nil)
        #expect(CaptureRequest(deepLink: URL(string: "shelf://add")!) == nil)
    }

    @Test func looseText() {
        #expect(CaptureRequest(text: " https://example.com/x ").url?.absoluteString == "https://example.com/x")
        let question = CaptureRequest(text: "why do cats purr")
        #expect(question.url == nil)
        #expect(question.title == "why do cats purr")
    }

    @Test func httpParsing() throws {
        let body = #"{"url":"https://example.com"}"#
        let raw = "POST /v1/items?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Shelf-Token: abc\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard case .complete(let req) = LocalAPI.parse(Data(raw.utf8)) else { Issue.record("expected complete"); return }
        #expect(req.method == "POST")
        #expect(req.path == "/v1/items")
        #expect(req.headers["x-shelf-token"] == "abc")
        let capture = try JSONDecoder().decode(CaptureRequest.self, from: req.body)
        #expect(capture.url?.absoluteString == "https://example.com")

        let partial = "POST /v1/items HTTP/1.1\r\nContent-Length: 50\r\n\r\n{\"url\""
        guard case .needMoreData = LocalAPI.parse(Data(partial.utf8)) else { Issue.record("expected needMoreData"); return }
    }

    @Test func tokens() {
        let token = LocalAPI.makeToken()
        #expect(token.count == 23)
        #expect(LocalAPI.tokensMatch(token, token))
        #expect(!LocalAPI.tokensMatch("nope", token))
        #expect(!LocalAPI.tokensMatch(nil, token))
    }

    @Test func archiveRoundTrip() throws {
        let record = ItemRecord(kind: .book, status: .done, title: "Dune", creator: "Frank Herbert", rating: 5, tags: ["sci-fi"])
        let data = try ShelfArchive.encoder.encode(ShelfArchive(items: [record]))
        let decoded = try ShelfArchive.decoder.decode(ShelfArchive.self, from: data)
        #expect(decoded.items.first?.title == "Dune")
        #expect(decoded.items.first?.rating == 5)
        #expect(decoded.version == ShelfArchive.currentVersion)
    }

    @Test func interleaveDedupes() {
        let a = [Metadata(kind: .book, title: "Dune", year: 1965, provider: "A"),
                 Metadata(kind: .book, title: "Dune Messiah", year: 1969, provider: "A")]
        let b = [Metadata(kind: .book, title: "Dune", creator: "Frank Herbert", year: 1965, provider: "B")]
        let merged = MetadataService.interleave([a, b])
        #expect(merged.map(\.title) == ["Dune", "Dune Messiah"])
        #expect(merged.first?.creator == "Frank Herbert")
    }
}
