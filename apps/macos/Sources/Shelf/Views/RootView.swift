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
            ZStack {
                Color.paper.ignoresSafeArea()
                detail
            }
            .inspector(isPresented: $router.showingInspector) {
                inspector
                    .inspectorColumnWidth(min: 320, ideal: 360, max: 460)
            }
        }
        .searchable(text: $router.searchText, placement: .sidebar, prompt: "Search your shelf")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.showingCapture = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add to Shelf (⌘N)")
            }
        }
        .sheet(isPresented: $router.showingCapture) {
            CaptureView(presentation: .sheet) { router.showingCapture = false }
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
        case let scope:
            LibraryView(items: items, scope: scope)
        }
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
}
