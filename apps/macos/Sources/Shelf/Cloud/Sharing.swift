import Foundation
import ShelfCore

/// Who can see what you've shared. Each shelf has a default (Only me until
/// you change it), and any item can override its shelf's setting. The
/// override travels in the item's `extra`, which the server never shows to
/// anyone but you.
@MainActor
enum Sharing {
    private static let defaultsKey = "cloud.shelfVisibility"
    static let overrideKey = "visibility"

    static func shelfDefault(_ kind: ItemKind) -> Visibility {
        let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]
        return stored?[kind.rawValue].flatMap(Visibility.init(rawValue:)) ?? .private
    }

    static func setShelfDefault(_ visibility: Visibility, for kind: ItemKind) {
        var stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        stored[kind.rawValue] = visibility.rawValue
        UserDefaults.standard.set(stored, forKey: defaultsKey)
        // Every item on that shelf needs its new setting sent.
        CloudSync.shared.resendAll()
    }

    static func visibility(of item: Item) -> Visibility {
        item.extra[overrideKey].flatMap(Visibility.init(rawValue:)) ?? shelfDefault(item.kind)
    }

    /// nil follows the shelf's default.
    static func override(of item: Item) -> Visibility? {
        item.extra[overrideKey].flatMap(Visibility.init(rawValue:))
    }

    static func setOverride(_ visibility: Visibility?, for item: Item) {
        item.extra[overrideKey] = visibility?.rawValue
        item.touch()
        CloudSync.shared.soon()
    }
}
