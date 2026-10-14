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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 28, alignment: .bottom)],
                              alignment: .leading, spacing: 34) {
                        ForEach(filtered) { item in
                            ItemCard(item: item, width: 140)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                } else {
                    LazyVStack(spacing: 4) {
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
        }
        .onChange(of: scope) { _, _ in statusFilter = nil }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if case .kind(let kind) = scope {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(kind.tint)
                }
                Text(router.searchText.isEmpty ? scope.title : "“\(router.searchText)”")
                    .font(.display(34, weight: .medium))
                    .foregroundStyle(Color.ink)
                Text("\(filtered.count)")
                    .font(.display(20, weight: .regular))
                    .foregroundStyle(Color.inkFaint)
                    .contentTransition(.numericText())
                Spacer()
                controls
            }
            if showsStatusFilter { statusBar }
        }
    }

    private var showsStatusFilter: Bool {
        switch scope {
        case .status: false
        default: true
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            filterChip(nil, label: "All", count: scoped.count)
            ForEach(ItemStatus.allCases) { status in
                let count = scoped.tally { $0.status == status }
                if count > 0 || status != .dropped {
                    filterChip(status, label: labelFor(status), count: count)
                }
            }
        }
    }

    private func labelFor(_ status: ItemStatus) -> String {
        if case .kind(let k) = scope { return k.label(for: status) }
        return status.title
    }

    private func filterChip(_ status: ItemStatus?, label: String, count: Int) -> some View {
        let selected = statusFilter == status
        let tint: Color = {
            if case .kind(let k) = scope { return k.tint }
            return .ink
        }()
        return Button {
            withAnimation(.shelf) { statusFilter = status }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                Text("\(count)").foregroundStyle(selected ? Color.white.opacity(0.7) : Color.inkFaint)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.white : Color.inkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? tint : Color.paperSunken, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var addLabel: String {
        if let kind = router.currentKind { return "Add \(kind.title.lowercased())" }
        return "Add"
    }

    private var addButton: some View {
        let tint = router.currentKind?.tint ?? Color.ink
        return Button {
            router.showingCapture = true
        } label: {
            Label(addLabel, systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(tint, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(addLabel) (⌘N)")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            addButton

            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(sort.title, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Picker("Layout", selection: Binding(get: { layout }, set: { setLayout($0) })) {
                Image(systemName: "square.grid.2x2").tag(Layout.grid)
                Image(systemName: "list.bullet").tag(Layout.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 84)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !router.searchText.isEmpty {
            EmptyShelf(symbol: "magnifyingglass", title: "Nothing by that name",
                       message: "Nothing on your shelf matches “\(router.searchText)”. Press ⌘N to go find it.")
        } else if case .kind(let kind) = scope {
            EmptyShelf(symbol: kind.symbol, title: "No \(kind.pluralTitle.lowercased()) yet",
                       message: emptyMessage(for: kind), tint: kind.tint)
        } else {
            EmptyShelf(symbol: scope.symbol, title: "Nothing here yet",
                       message: "Things will gather here as you add them. Press ⌘N, or \(HotKeyPreset.current.title) from anywhere.")
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
