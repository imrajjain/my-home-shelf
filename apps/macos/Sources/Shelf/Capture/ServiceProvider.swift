import AppKit
import ShelfCore

/// Services menu: select text or a link in any app → right-click →
/// Services → "Add to Shelf". Declared in Info.plist (NSServices).
final class ServiceProvider: NSObject {
    @objc func addToShelf(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pboard.string(forType: .URL) ?? pboard.string(forType: .string) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Nothing to add." as NSString
            return
        }
        let request = CaptureRequest(text: text)
        Task { @MainActor in
            QuickCaptureController.shared.show(prefill: request)
        }
    }
}
