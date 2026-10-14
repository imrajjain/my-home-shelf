import Foundation
import Observation
import ShelfCore

enum SidebarSelection: Hashable {
    case home
    case status(ItemStatus)
    case favorites
    case kind(ItemKind)
    case tag(String)

    var title: String {
        switch self {
        case .home: "Home"
        case .status(let s): s.title
        case .favorites: "Favorites"
        case .kind(let k): k.pluralTitle
        case .tag(let t): "#\(t)"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .status(let s): s.symbol
        case .favorites: "heart"
        case .kind(let k): k.symbol
        case .tag: "number"
        }
    }
}

/// App-wide navigation state, shared by the window, menus and shortcuts.
@MainActor
@Observable
final class Router {
    var selection: SidebarSelection? = .home
    var selectedItemID: UUID?
    var showingCapture = false
    var showingInspector = false
    var searchText = ""

    /// The shelf being browsed, so new things land there by default.
    var currentKind: ItemKind? {
        if case .kind(let kind) = selection { return kind }
        return nil
    }

    /// Adding from "Finished" means it's already finished.
    var currentStatus: ItemStatus? {
        if case .status(let status) = selection, status != .dropped { return status }
        return nil
    }

    func open(_ item: Item) {
        selectedItemID = item.id
        showingInspector = true
    }
}
