import Foundation
import Observation
import ShelfCore

enum SidebarSelection: Hashable {
    case home
    case status(ItemStatus)
    case favorites
    case kind(ItemKind)
    case tag(String)
    case exhibit(Exhibit)
    /// Find people, friend requests, the people you follow.
    case people
    /// Someone's shared shelf, by username.
    case person(String)

    var title: String {
        switch self {
        case .home: "Home"
        case .status(let s): s.title
        case .favorites: "Favorites"
        case .kind(let k): k.pluralTitle
        case .tag(let t): t
        case .exhibit(let e): e.title
        case .people: "People"
        case .person(let name): "@\(name)"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .status(let s): s.symbol
        case .favorites: "heart"
        case .kind(let k): k.symbol
        case .tag: "number"
        case .exhibit(let e): e.symbol
        case .people: "person.2"
        case .person: "person.crop.circle"
        }
    }
}

/// Rooms in the Museum: curated things to wander through, apart from your shelf.
enum Exhibit: String, CaseIterable, Hashable {
    case flags
    case currencies

    var title: String {
        switch self {
        case .flags: "Flags & Anthems"
        case .currencies: "World Currencies"
        }
    }

    var symbol: String {
        switch self {
        case .flags: "flag"
        case .currencies: "banknote"
        }
    }
}

/// App-wide navigation state, shared by the window, menus and shortcuts.
@MainActor
@Observable
final class Router {
    static let shared = Router()
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
