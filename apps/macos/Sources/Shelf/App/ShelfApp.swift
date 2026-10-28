import SwiftUI
import SwiftData
import ShelfCore

@main
struct ShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = Router.shared

    var body: some Scene {
        Window("Shelf", id: "main") {
            RootView()
                .environment(router)
                .frame(minWidth: 940, minHeight: 600)
        }
        .modelContainer(Persistence.container)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1240, height: 820)
        .commands { ShelfCommands(router: router) }

        Settings {
            SettingsView()
                .modelContainer(Persistence.container)
        }

        MenuBarExtra("Shelf", systemImage: "books.vertical") {
            MenuBarContent()
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Quick Add…") { QuickCaptureController.shared.show(prefill: nil) }
        Button("Open Shelf") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if GoodreadsSync.shared.source != nil {
            Button("Sync with Goodreads") { Task { await GoodreadsSync.shared.sync() } }
        }
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Quit Shelf") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct ShelfCommands: Commands {
    let router: Router

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesCommand()
        }
        CommandGroup(replacing: .newItem) {
            Button("Add to Shelf…") { router.showingCapture = true }
                .keyboardShortcut("n")
            Button("Quick Capture Panel") { QuickCaptureController.shared.show(prefill: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Export Shelf…") { ArchiveService.exportWithPanel() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Import Shelf…") { ArchiveService.importWithPanel() }
            Divider()
            Button("Sync with Goodreads") { Task { await GoodreadsSync.shared.sync() } }
                .keyboardShortcut("r")
                .disabled(GoodreadsSync.shared.source == nil || GoodreadsSync.shared.state == .syncing)
        }
        CommandMenu("Go") {
            Button("Home") { router.selection = .home }.keyboardShortcut("1")
            Button("Up Next") { router.selection = .status(.want) }.keyboardShortcut("2")
            Button("In Progress") { router.selection = .status(.inProgress) }.keyboardShortcut("3")
            Button("Finished") { router.selection = .status(.done) }.keyboardShortcut("4")
            Button("Favorites") { router.selection = .favorites }.keyboardShortcut("5")
            Button("Flags & Anthems") { router.selection = .exhibit(.flags) }.keyboardShortcut("6")
            Button("World Currencies") { router.selection = .exhibit(.currencies) }.keyboardShortcut("7")
            Divider()
            ForEach(Array(ItemKind.allCases.enumerated()), id: \.element) { index, kind in
                if index < 9 {
                    Button(kind.pluralTitle) { router.selection = .kind(kind) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
                } else {
                    Button(kind.pluralTitle) { router.selection = .kind(kind) }
                }
            }
        }
        CommandGroup(after: .sidebar) {
            Button(router.showingInspector ? "Hide Details" : "Show Details") {
                router.showingInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
