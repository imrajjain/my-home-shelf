import Foundation
import Testing
@testable import ShelfCore

struct HTMLMetadataParserTests {
    @Test func openGraphAndEntities() {
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
        #expect(m.title == "The Art of Noticing — A Field Guide")
        #expect(m.imageURL?.absoluteString == "https://example.com/img/cover.jpg")
        #expect(m.summary == "A small essay.")
        #expect(m.url?.absoluteString == "https://example.com/noticing")
        #expect(m.provider == "Example")
    }

    @Test func papersWithCodeTasksAndMethods() {
        let html = """
        <html><head>
        <title>Agent Harness | Papers with Code</title>
        <meta name="citation_title" content="Self-Improving Agent Harnesses">
        <meta name="citation_arxiv_id" content="2610.11959">
        </head><body>
        <nav><a href="/papers/recent">Recent</a></nav>
        <section aria-label="Tasks and methods">
        <div><h3>Tasks</h3><ul><li><a href="/tasks/agents">Agents</a></li></ul></div>
        <div><h3>Methods</h3><ul><li><a href="/methods/agent-harness">Agent Harness</a></li>
        <li><a href="/methods/llm">Large language model (LLM)</a></li>
        <li><a href="/methods/rsi"><span>Recursive Self&#8209;Improvement</span></a></li>
        <li><a href="/methods/agent-harness">Agent Harness</a></li></ul></div>
        </section></body></html>
        """
        let url = URL(string: "https://paperswithcode.co/paper/2610.11959")!
        let m = HTMLMetadataParser().parse(html, baseURL: url).metadata(for: url, guessedKind: .paper)
        #expect(m.title == "Self-Improving Agent Harnesses")
        #expect(m.tags == ["Agents", "Agent Harness", "Large language model (LLM)", "Recursive Self\u{2011}Improvement"])
        #expect(m.extra["arxiv"] == "2610.11959")

        // Other sites' /tasks/ links are navigation, not topics.
        let other = URL(string: "https://example.com/paper")!
        #expect(HTMLMetadataParser().parse(html, baseURL: other).topics.isEmpty)
    }

    @Test func letterboxdStyleJSONLD() {
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
        #expect(m.kind == .film)
        #expect(m.title == "Past Lives")
        #expect(m.creator == "Celine Song")
        #expect(m.year == 2023)
        #expect(m.imageURL?.absoluteString == "https://a.ltrbxd.com/poster.jpg")
        #expect(m.tags == ["Drama", "Romance"])
    }

    @Test func goodreadsStyleBook() {
        let html = """
        <head><script type="application/ld+json">{"@context":"https://schema.org","@type":"Book",
        "name":"Dune","image":"https://images.gr-assets.com/dune.jpg","numberOfPages":658,
        "author":[{"@type":"Person","name":"Frank Herbert"}]}</script></head>
        """
        let url = URL(string: "https://www.goodreads.com/book/show/44767458-dune")!
        let m = HTMLMetadataParser().parse(html, baseURL: url).metadata(for: url, guessedKind: .book)
        #expect(m.kind == .book)
        #expect(m.title == "Dune")
        #expect(m.creator == "Frank Herbert")
        #expect(m.extra["pages"] == "658")
    }

    @Test func citationTagsMakeAPaper() {
        let html = """
        <head><meta name="citation_title" content="Deep learning">
        <meta name="citation_author" content="LeCun, Yann"><meta name="citation_doi" content="10.1038/nature14539">
        <meta name="citation_journal_title" content="Nature"><meta name="citation_publication_date" content="2015/05/28"></head>
        """
        let url = URL(string: "https://www.nature.com/articles/nature14539")!
        let m = HTMLMetadataParser().parse(html, baseURL: url).metadata(for: url, guessedKind: .paper)
        #expect(m.kind == .paper)
        #expect(m.title == "Deep learning")
        #expect(m.extra["doi"] == "10.1038/nature14539")
        #expect(m.extra["venue"] == "Nature")
        #expect(m.year == 2015)
    }
}
