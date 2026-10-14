import SwiftUI
import ShelfCore

struct LibraryView: View {
    let items: [Item]
    let scope: SidebarSelection
    @Environment(Router.self) private var router

    enum Layout: String { case grid, list }
    enum Sort: String, CaseIterable, Identifiable {
        case added, updated, title, rating, year
        var id: String { rawValue }
        var title: String {
            switch self {
            case .added: "Date added"
            case .updated: "Recently touched"
            case .title: "Title"
            case .rating: "Rating"
            case .year: "Year"
            }
        }
    }

    @State private var statusFilter: ItemStatus?
    @AppStorage("library.sort") private var sort: Sort = .added
    @AppStorage("library.layout.visual") private var visualLayout: Layout = .grid
    @AppStorage("library.layout.text") private var textLayout: Layout = .list

    private var prefersList: Bool {
        switch scope {
        case .kind(let k): !k.isVisual
        default: false
        }
    }

    private var layout: Layout {
        get { prefersList ? textLayout : visualLayout }
    }

    private func setLayout(_ l: Layout) {
        if prefersList { textLayout = l } else { visualLayout = l }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if filtered.isEmpty {
                    emptyState.frame(minHeight: 380)
                } else if layout == .grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 168), spacing: 24, alignment: .top)],
                              alignment: .leading, spacing: 28) {
                        ForEach(filtered) { item in
                            ItemCard(item: item, width: 128, coverHeight: 192)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { item in
                            ItemRow(item: item)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 30)
            .padding(.bottom, 60)
            .animation(.shelf, value: filtered.map(\.id))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .top) {
                ArtworkBackdrop(colors: [.clear, .clear], height: 380, intensity: 0.7)
            }
        }
        .onChange(of: scope) { _, _ in statusFilter = nil }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(router.searchText.isEmpty ? scope.title : "“\(router.searchText)”")
                    .font(.display(28, weight: .regular))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Spacer(minLength: 12)
                // An empty shelf offers one way forward, in the middle.
                if !scoped.isEmpty { addButton }
            }
            if !filtered.isEmpty || !scoped.isEmpty {
                HStack {
                    if showsStatusFilter && !scoped.isEmpty { statusBar }
                    Spacer()
                    controls
                }
            }
        }
    }

    private var showsStatusFilter: Bool {
        switch scope {
        case .status: false
        default: true
        }
    }

    private var statusBar: some View {
        PillPicker(
            selection: $statusFilter,
            options: [.init(value: nil, title: "All")] + ItemStatus.allCases
                .filter { $0 != .dropped || scoped.contains { $0.status == .dropped } }
                .map { .init(value: $0, title: labelFor($0)) }
        )
    }

    private func labelFor(_ status: ItemStatus) -> String {
        if case .kind(let k) = scope { return k.label(for: status) }
        return status.title
    }

    private var addLabel: String {
        if let kind = router.currentKind { return "Add \(kind.title.lowercased())" }
        return "Add"
    }

    private var addButton: some View {
        Button(addLabel, systemImage: "plus") { router.showingCapture = true }
            .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
            .help("\(addLabel) (⌘N)")
            .fixedSize()
    }

    private var controls: some View {
        HStack(spacing: 8) {

            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .buttonStyle(.icon)
            .menuIndicator(.hidden)
            .help("Sort by \(sort.title.lowercased())")
            .fixedSize()

            PillPicker(
                selection: Binding(get: { layout }, set: { setLayout($0) }),
                options: [
                    .init(value: Layout.grid, title: "Grid", symbol: "square.grid.2x2"),
                    .init(value: Layout.list, title: "List", symbol: "list.bullet"),
                ]
            )
            .fixedSize()
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !router.searchText.isEmpty {
            EmptyShelf(symbol: "magnifyingglass", title: "Nothing by that name",
                       message: "Nothing on your shelf matches “\(router.searchText)”.",
                       actionTitle: "Find It…", action: { router.showingCapture = true })
        } else if case .kind(let kind) = scope {
            EmptyShelf(symbol: kind.symbol, title: "No \(kind.pluralTitle.lowercased()) yet",
                       message: emptyMessage(for: kind),
                       actionTitle: "\(addLabel)…", action: { router.showingCapture = true })
        } else {
            EmptyShelf(symbol: scope.symbol, title: "Nothing here yet",
                       message: "Things gather here as you add them.")
        }
    }

    private func emptyMessage(for kind: ItemKind) -> String {
        switch kind {
        case .book: "Paste a Goodreads link or just type a title — covers come from Open Library and Google Books."
        case .film, .show: "Paste a Letterboxd or IMDb link, or search by title. Posters included."
        case .paper: "Drop an arXiv link, a DOI, or search by title — authors and abstracts come along."
        case .article: "Save essays and blog posts from your browser with the extension."
        case .place: "Search Apple Maps for the café, city or trail you keep meaning to visit."
        case .curiosity: "Everything you Googled and couldn’t let go of. Type a question to start."
        default: "Search or paste a link to add one."
        }
    }

    // MARK: Data

    /// Items within the sidebar scope (before status filter and search).
    private var scoped: [Item] {
        items.filter { item in
            switch scope {
            case .home: true
            case .status(let s): item.status == s
            case .favorites: item.isFavorite
            case .kind(let k): item.kind == k
            case .tag(let t): item.tags.contains(t)
            }
        }
    }

    private var filtered: [Item] {
        let query = router.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let base: [Item]
        if !query.isEmpty {
            // Search spans the whole shelf, not just the current scope.
            base = items.filter { item in
                [item.title, item.creator ?? "", item.subtitle ?? "", item.notes, item.tags.joined(separator: " "),
                 item.extra["venue"] ?? "", item.host ?? ""]
                    .contains { $0.lowercased().contains(query) }
            }
        } else {
            base = scoped.filter { statusFilter == nil || $0.status == statusFilter }
        }
        return base.sorted(by: sortOrder)
    }

    private func sortOrder(_ a: Item, _ b: Item) -> Bool {
        switch sort {
        case .added: a.createdAt > b.createdAt
        case .updated: a.updatedAt > b.updatedAt
        case .title: a.title.localizedStandardCompare(b.title) == .orderedAscending
        case .rating: a.rating == b.rating ? a.createdAt > b.createdAt : a.rating > b.rating
        case .year: (a.year ?? 0) == (b.year ?? 0) ? a.createdAt > b.createdAt : (a.year ?? 0) > (b.year ?? 0)
        }
    }
}
