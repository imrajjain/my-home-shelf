import Foundation
import SwiftData

/// One container for the whole app, shared by the main window, the
/// quick-capture panel and the browser-extension API.
@MainActor
enum Persistence {
    static let container: ModelContainer = {
        // SHELF_STORE_DIR points debug runs (snapshots) at a copy of the shelf.
        let folder = ProcessInfo.processInfo.environment["SHELF_STORE_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL.applicationSupportDirectory.appending(path: "Shelf", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = ModelConfiguration("Shelf", url: folder.appending(path: "Shelf.store"))
        do {
            return try ModelContainer(for: Item.self, configurations: config)
        } catch {
            // Never lose the user's shelf silently: keep the old store aside.
            let stamp = Int(Date().timeIntervalSince1970)
            let broken = folder.appending(path: "Shelf.store")
            try? FileManager.default.moveItem(at: broken, to: folder.appending(path: "Shelf-unreadable-\(stamp).store"))
            return try! ModelContainer(for: Item.self, configurations: config)
        }
    }()

    static var context: ModelContext { container.mainContext }
}
