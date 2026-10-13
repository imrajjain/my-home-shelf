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

    func open(_ item: Item) {
        selectedItemID = item.id
        showingInspector = true
    }
}
