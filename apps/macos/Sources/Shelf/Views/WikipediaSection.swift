import SwiftUI
import WebKit
import ShelfCore

/// Wikipedia articles related to what's on your shelf. Fresh picks each
/// launch, or on request; kept while the app is open so Home stays calm.
@Observable @MainActor
final class WikipediaPicks {
    static let shared = WikipediaPicks()

    struct Pick: Identifiable, Hashable {
        let article: WikiArticle
        /// What on your shelf led here.
        let because: String
        /// The article it was reached through, when it's a step further out.
        var via: String?
        var id: String { article.id }
    }

    private(set) var picks: [Pick] = []
    private(set) var loading = false
    private var loaded = false

    /// Articles already shown, so each refresh finds new ground.
    private static let seenKey = "wikipedia.seen"
    private var seen: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(600)), forKey: Self.seenKey) }
    }

    func loadIfNeeded(from items: [Item]) {
        guard !loaded else { return }
        loaded = true
        Task { await load(from: items) }
    }

    func shuffle(from items: [Item]) {
        Task { await load(from: items) }
    }

    private func load(from items: [Item]) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        // Anything on the shelf can start a walk; what you're into right now a bit more often.
        let pool = items.filter { [.book, .film, .show, .paper].contains($0.kind) && $0.status != .dropped }
        let current = pool.filter { $0.status == .inProgress || $0.isFavorite }.shuffled().prefix(Int.random(in: 0...2))
        let rest = pool.filter { !current.contains($0) }.shuffled().prefix(6 - current.count)
        let seeds = (Array(current) + Array(rest)).shuffled()

        let avoiding = Set(items.map { $0.title.lowercased() } + seen.map { $0.lowercased() })
        let feed = WikipediaFeed()
        let found = await withTaskGroup(of: (Int, [Pick]).self) { group in
            for (i, item) in seeds.enumerated() {
                let title = item.title, creator = item.creator, kind = item.kind
                // Mostly wander further out; sometimes stay close.
                let route: WikipediaFeed.Route = [.near, .hop, .hop, .links, .links].randomElement()!
                group.addTask {
                    let found = await feed.wander(fromTitle: title, creator: creator, kind: kind,
                                                  route: route, limit: 2, avoiding: avoiding)
                    return (i, found.map { Pick(article: $0.article, because: title, via: $0.via) })
                }
            }
            var out: [(Int, [Pick])] = []
            for await result in group { out.append(result) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }

        // Interleave so one seed doesn't fill the row.
        var ids = Set<String>()
        var result: [Pick] = []
        for round in 0..<2 {
            for picks in found where round < picks.count {
                let pick = picks[round]
                guard ids.insert(pick.id).inserted else { continue }
                result.append(pick)
            }
        }
        if !result.isEmpty {
            let shown = Array(result.prefix(10))
            seen += shown.map(\.article.title)
            withAnimation(.shelf) { picks = shown }
        } else if !seen.isEmpty {
            // Walked everywhere nearby: forget the oldest half and try again later.
            seen = Array(seen.dropFirst(seen.count / 2))
        }
    }
}

struct WikipediaSection: View {
    let items: [Item]
    @State private var model = WikipediaPicks.shared
    @State private var reading: WikiArticle?

    var body: some View {
        if !model.picks.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Wander").font(.sectionTitle).foregroundStyle(Color.ink)
                    Image(systemName: "w.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.inkFaint)
                        .accessibilityHidden(true)
                    Text("From Wikipedia, around what you love").font(.system(size: 12)).foregroundStyle(Color.inkFaint)
                    Spacer()
                    Button {
                        model.shuffle(from: items)
                    } label: {
                        Label(model.loading ? "Finding…" : "New Topics", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Wiki.subtle)
                    .disabled(model.loading)
                    .help("Show different articles")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(model.picks) { pick in
                            WikiCard(pick: pick) { reading = pick.article }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, -4)
            }
            .sheet(item: $reading) { article in
                WikiReader(article: article) { reading = nil }
            }
        } else {
            Color.clear.frame(height: 0)
                .onAppear { model.loadIfNeeded(from: items) }
        }
    }
}

private struct WikiCard: View {
    let pick: WikipediaPicks.Pick
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) { card }
            .buttonStyle(.plain)
            .onHover { inside in withAnimation(.lift) { hovering = inside } }
            .contextMenu {
                Button("Read") { open() }
                Button("Open in Browser") { NSWorkspace.shared.open(pick.article.url) }
                Button("Save to Shelf") { WikiReader.save(pick.article) }
            }
            .help(pick.article.extract ?? pick.article.title)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
                .frame(width: 240, height: 120)
                .clipped()
                .overlay(alignment: .bottom) { Rectangle().fill(Wiki.rule).frame(height: 1) }
            VStack(alignment: .leading, spacing: 0) {
                Text(pick.article.title)
                    .font(Wiki.serif(17))
                    .foregroundStyle(Wiki.text)
                    .lineLimit(1)
                    .padding(.bottom, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Wikipedia's heading rule, edge to edge.
                    .overlay(alignment: .bottom) { Rectangle().fill(Wiki.rule).frame(height: 1) }
                if let description = pick.article.description {
                    Text(description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Wiki.subtle)
                        .lineLimit(2)
                        .padding(.top, 7)
                }
                Spacer(minLength: 0)
                Text(pick.via.map { "From \(pick.because), by way of \($0)" } ?? "Because of \(pick.because)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Wiki.faint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 11)
            .frame(width: 240, height: 112, alignment: .topLeading)
        }
        .background(hovering ? Wiki.pageHover : Wiki.page)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Wiki.border))
        .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder private var thumbnail: some View {
        if let url = pick.article.thumbnail {
            ZStack {
                Wiki.well
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
            }
            .allowsHitTesting(false)
        } else {
            placeholder
        }
    }

    /// No picture: the opening line, set like the lead of an article.
    private var placeholder: some View {
        ZStack(alignment: .topLeading) {
            Wiki.well
            Text(pick.article.extract ?? "")
                .font(Wiki.serif(12.5))
                .foregroundStyle(Wiki.subtle)
                .lineSpacing(1.5)
                .lineLimit(4)
                .padding(14)
        }
    }
}

/// Wikipedia's own palette: white or near-black pages, gray rules, serif headings.
enum Wiki {
    static let page = Color(light: .white, dark: NSColor(hex: 0x101418))
    static let pageHover = Color(light: NSColor(hex: 0xFCFCFD), dark: NSColor(hex: 0x161A1F))
    static let well = Color(light: NSColor(hex: 0xF8F9FA), dark: NSColor(hex: 0x1B1F24))
    static let border = Color(light: NSColor(hex: 0xC8CCD1), dark: NSColor(hex: 0x3A3F46))
    static let rule = Color(light: NSColor(hex: 0xEAECF0), dark: NSColor(hex: 0x2A2F35))
    static let text = Color(light: NSColor(hex: 0x202122), dark: NSColor(hex: 0xEAECF0))
    static let subtle = Color(light: NSColor(hex: 0x54595D), dark: NSColor(hex: 0xA2A9B1))
    static let faint = Color(light: NSColor(hex: 0x72777D), dark: NSColor(hex: 0x7C838B))

    /// Wikipedia sets headings in Linux Libertine; Georgia is the stand-in it names.
    static func serif(_ size: CGFloat) -> Font {
        if NSFont(name: "Linux Libertine", size: size) != nil { return .custom("Linux Libertine", size: size) }
        return .custom("Georgia", size: size)
    }
}

/// Reads an article inside Shelf; links off Wikipedia go to your browser.
struct WikiReader: View {
    let article: WikiArticle
    let close: () -> Void
    @State private var failed = false
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(article.title)
                    .font(.display(16))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Spacer()
                Button(saved ? "Saved" : "Save to Shelf", systemImage: saved ? "checkmark" : "plus") {
                    Self.save(article)
                    withAnimation(.lift) { saved = true }
                }
                .buttonStyle(.pillCompact)
                .disabled(saved)
                Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(article.url) }
                    .buttonStyle(.icon)
                    .help("Open in your browser")
                Button("Done", action: close)
                    .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Rectangle().fill(Color.hairline).frame(height: 1)
            WikiWebView(url: article.readerURL) {
                // Couldn't load in the app: hand it to the browser instead.
                NSWorkspace.shared.open(article.url)
                close()
            }
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 760)
        .background(Color.paper)
    }

    static func save(_ article: WikiArticle) {
        CaptureCoordinator.shared.add(CaptureRequest(url: article.url, title: article.title))
    }
}

private struct WikiWebView: NSViewRepresentable {
    let url: URL
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Follow the system's light/dark setting and drop Wikipedia's own
        // chrome, which duplicates ours.
        let script = """
        document.documentElement.classList.add('skin-theme-clientpref-os');
        document.documentElement.classList.remove('skin-theme-clientpref-day');
        const style = document.createElement('style');
        style.textContent = '.header-container, .minerva-footer, .page-actions-menu, .banner-container, .vector-header-container, .mw-footer-container { display: none !important; }';
        document.documentElement.appendChild(style);
        """
        config.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        // Wikipedia only serves its clean mobile layout to phones.
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        web.underPageBackgroundColor = .textBackgroundColor
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onFailure: () -> Void
        private var loadedOnce = false

        init(onFailure: @escaping () -> Void) { self.onFailure = onFailure }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            // Stay on Wikipedia in here; anything else opens in the browser.
            if action.navigationType == .linkActivated, let url = action.request.url,
               !(url.host ?? "").hasSuffix("wikipedia.org") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loadedOnce = true }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if !loadedOnce { onFailure() }
        }
    }
}
