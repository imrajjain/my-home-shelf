import Foundation
import Testing
@testable import ShelfCore

struct LinkClassifierTests {
    private func kind(_ s: String) -> ItemKind { LinkClassifier.kind(for: URL(string: s)!) }

    @Test func kinds() {
        #expect(kind("https://www.goodreads.com/book/show/44767458-dune") == .book)
        #expect(kind("https://letterboxd.com/film/past-lives/") == .film)
        #expect(kind("https://www.imdb.com/title/tt11280740/") == .film)
        #expect(kind("https://www.themoviedb.org/tv/95396-severance") == .show)
        #expect(kind("https://arxiv.org/abs/1706.03762") == .paper)
        #expect(kind("https://example.com/files/paper.pdf") == .paper)
        #expect(kind("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == .video)
        #expect(kind("https://podcasts.apple.com/us/podcast/x/id123") == .podcast)
        #expect(kind("https://open.spotify.com/album/abc") == .music)
        #expect(kind("https://www.google.com/maps/place/Blue+Bottle") == .place)
        #expect(kind("https://www.google.com/search?q=why+is+the+sky+blue") == .curiosity)
        #expect(kind("https://en.wikipedia.org/wiki/Rayleigh_scattering") == .curiosity)
        #expect(kind("https://paulgraham.com/greatwork.html") == .article)
    }

    @Test func googleQuery() {
        let url = URL(string: "https://www.google.com/search?q=why+is+the+sky+blue&oq=why")!
        #expect(LinkClassifier.googleSearchQuery(url) == "why is the sky blue")
        #expect(LinkClassifier.googleSearchQuery(URL(string: "https://www.google.com/maps")!) == nil)
    }

    @Test func arxivID() {
        #expect(LinkClassifier.arxivID(URL(string: "https://arxiv.org/abs/1706.03762v7")!) == "1706.03762")
        #expect(LinkClassifier.arxivID(URL(string: "https://arxiv.org/pdf/2303.08774")!) == "2303.08774")
        #expect(LinkClassifier.arxivID(URL(string: "https://example.com/abs/1706.03762")!) == nil)
    }

    @Test func doi() {
        #expect(LinkClassifier.doi(in: "https://doi.org/10.1038/nature14539") == "10.1038/nature14539")
        #expect(LinkClassifier.doi(in: "see (10.1145/3290605.3300233).") == "10.1145/3290605.3300233")
    }

    @Test func youTubeID() {
        #expect(LinkClassifier.youtubeID(URL(string: "https://youtu.be/abc123")!) == "abc123")
        #expect(LinkClassifier.youtubeID(URL(string: "https://www.youtube.com/shorts/xyz")!) == "xyz")
    }

    @Test func firstURL() {
        #expect(LinkClassifier.firstURL(in: "  https://example.com/a  ")?.absoluteString == "https://example.com/a")
        #expect(LinkClassifier.isBareURL("https://example.com"))
        #expect(!LinkClassifier.isBareURL("read this https://example.com"))
        #expect(!LinkClassifier.isBareURL("dune"))
    }

    @Test func fallbackTitles() {
        func title(_ s: String) -> String { MetadataService.fallback(for: URL(string: s)!, kind: .book).title }
        #expect(title("https://www.goodreads.com/book/show/18373.Flowers_for_Algernon") == "Flowers for Algernon")
        #expect(title("https://www.goodreads.com/book/show/44767458-dune") == "Dune")
        #expect(title("https://example.com/blog/the-art-of-noticing.html") == "The Art Of Noticing")
        #expect(title("https://www.imdb.com/title/tt11280740/") == "imdb.com")
    }

    @Test func imdbID() {
        #expect(IMDbResolver.imdbID(URL(string: "https://www.imdb.com/title/tt11280740/")!) == "tt11280740")
        #expect(IMDbResolver.imdbID(URL(string: "https://m.imdb.com/title/tt0816692/reviews")!) == "tt0816692")
        #expect(IMDbResolver.imdbID(URL(string: "https://www.imdb.com/name/nm0000138/")!) == nil)
    }

    @Test func looseTitleMatching() {
        #expect(MetadataService.sameWords("Flowers for Algernon", "flowers of algernon"))
        #expect(MetadataService.sameWords("The Matrix", "matrix"))
        #expect(!MetadataService.sameWords("Algernon, Charlie and I, A Writer's Journey", "flowers of algernon"))
        #expect(!MetadataService.sameWords("The Matrix Reloaded", "the matrix"))
    }
}
