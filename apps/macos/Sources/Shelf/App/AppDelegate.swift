import AppKit
import ShelfCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private var defaultsObserver: NSObjectProtocol?
    private var currentPreset: HotKeyPreset?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched via `swift run` there's no bundle; still be a real app.
        if Bundle.main.bundleIdentifier == nil {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()

        registerHotKey()
        configureLocalAPI()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.registerHotKey()
                self?.configureLocalAPI()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // Shelf lives in the menu bar so the hotkey keeps working.
    }

    /// `shelf://add?url=…` adds silently; `shelf://capture?…` opens the panel.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let request = CaptureRequest(deepLink: url) else { continue }
            if url.host == "capture" {
                QuickCaptureController.shared.show(prefill: request)
            } else {
                CaptureCoordinator.shared.add(request)
            }
        }
    }

    private func registerHotKey() {
        let preset = HotKeyPreset.current
        guard preset != currentPreset else { return }
        currentPreset = preset
        hotKey = nil
        guard preset != .off else { return }
        hotKey = HotKey(keyCode: preset.keyCode, modifiers: preset.modifiers) {
            QuickCaptureController.shared.toggle()
        }
        if hotKey == nil { NSLog("Shelf: \(preset.title) is taken by another app") }
    }

    private func configureLocalAPI() {
        if AppSettings.apiEnabled {
            LocalServer.shared.start()
        } else {
            LocalServer.shared.stop()
        }
    }
}
