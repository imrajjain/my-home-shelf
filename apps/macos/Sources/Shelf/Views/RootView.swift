import SwiftUI
import SwiftData
import ShelfCore

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Item> { $0.deletedAt == nil }, sort: \Item.createdAt, order: .reverse)
    private var items: [Item]

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            SidebarView(items: items)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 280)
        } detail: {
            // A plain side column rather than `.inspector`: on macOS 27 the system
            // inspector drew its content a toolbar-height below where it took
            // the mouse, so hover and clicks landed about an inch too high.
            HStack(spacing: 0) {
                ZStack {
                    Color.paper.ignoresSafeArea()
                    detail
                }
                if router.showingInspector {
                    Rectangle().fill(Color.hairline).frame(width: 1).ignoresSafeArea()
                    inspector
                        .frame(width: 360)
                        .overlay(alignment: .topTrailing) { closeInspectorButton }
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.shelf, value: router.showingInspector)
        }
        .searchable(text: $router.searchText, placement: .sidebar, prompt: "Search your shelf")
        .tint(Color.accent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.showingCapture = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add to Shelf (⌘N)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.showingInspector.toggle()
                } label: {
                    Label("Details", systemImage: "sidebar.right")
                }
                .help(router.showingInspector ? "Hide details (⌥⌘I)" : "Show details (⌥⌘I)")
            }
        }
        .sheet(isPresented: $router.showingCapture) {
            CaptureView(presentation: .sheet, initialKind: router.currentKind, initialStatus: router.currentStatus) {
                router.showingCapture = false
            }
        }
        .onChange(of: router.searchText) { _, text in
            // Searching shows results across the whole shelf.
            if !text.isEmpty, router.selection == .home { router.selection = .status(.want) }
        }
        .onDeleteCommand {
            if let id = router.selectedItemID, let item = items.first(where: { $0.id == id }) {
                ItemActions.delete(item, router: router)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch router.selection ?? .home {
        case .home:
            if router.searchText.isEmpty {
                HomeView(items: items)
            } else {
                LibraryView(items: items, scope: .status(.want))
            }
        case .exhibit(let exhibit):
            switch exhibit {
            case .flags: FlagsMuseumView()
            case .currencies: CurrencyMuseumView()
            }
        case .people:
            PeopleView()
        case .person(let name):
            PersonShelfView(username: name, mine: items)
                .id(name)
        case let scope:
            LibraryView(items: items, scope: scope)
        }
    }

    private var closeInspectorButton: some View {
        Button("Close", systemImage: "xmark") {
            router.showingInspector = false
        }
        .buttonStyle(.iconGlass)
        .keyboardShortcut(.cancelAction)
        .help("Close details (Esc)")
        .padding(12)
    }

    @ViewBuilder private var inspector: some View {
        if let id = router.selectedItemID, let item = items.first(where: { $0.id == id }) {
            ItemDetailView(item: item)
                .id(item.id)
        } else {
            EmptyShelf(symbol: "hand.point.up.left", title: "Pick something",
                       message: "Select anything on your shelf to see its details, notes and rating here.")
                .background(Color.paper)
        }
    }
}

enum ItemActions {
    @MainActor
    static func delete(_ item: Item, router: Router) {
        withAnimation(.shelf) {
            // Tombstone instead of hard delete so sync can propagate it later.
            item.deletedAt = .now
            item.touch()
            if router.selectedItemID == item.id { router.selectedItemID = nil }
        }
        try? item.modelContext?.save()
    }

    /// Double-click: straight to something readable. arXiv papers open their
    /// HTML version, or the PDF when arXiv has no HTML; everything else opens
    /// the saved link.
    @MainActor
    static func read(_ item: Item) {
        guard let id = item.extra["arxiv"] ?? item.url.flatMap(LinkClassifier.arxivID) else {
            if let url = item.url { NSWorkspace.shared.open(url) }
            return
        }
        Task {
            NSWorkspace.shared.open(await arxivReadingURL(id))
        }
    }

    private static func arxivReadingURL(_ id: String) async -> URL {
        let html = URL(string: "https://arxiv.org/html/\(id)")!
        var request = URLRequest(url: html, timeoutInterval: 4)
        request.httpMethod = "HEAD"
        request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) {
            return html
        }
        return URL(string: "https://arxiv.org/pdf/\(id)")!
    }
}
