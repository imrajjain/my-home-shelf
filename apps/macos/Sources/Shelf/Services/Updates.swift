import SwiftUI
import Sparkle

/// Automatic updates via Sparkle. Shelf checks a signed feed on GitHub
/// Releases in the background, downloads new versions quietly and installs
/// them on the next restart. Updates are verified with Shelf's own EdDSA
/// key (SUPublicEDKey in Info.plist), so no Apple developer account is needed.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false

    private init() {
        // A build without a signing key (local development) never starts the
        // updater, so it can't install anything unverified.
        let configured = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
            .map { !$0.isEmpty && !$0.hasPrefix("$(") } ?? false
        controller = SPUStandardUpdaterController(startingUpdater: configured, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func checkNow() { controller.checkForUpdates(nil) }
}

/// "Check for Updates…" in the Shelf menu.
struct CheckForUpdatesCommand: View {
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        Button("Check for Updates…") { updates.checkNow() }
            .disabled(!updates.canCheck)
    }
}
