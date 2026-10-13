import AppKit
import ShelfCore

/// Reads the current tab of the browser you were just looking at, so the
/// quick-capture panel opens already holding the page.
///
/// Uses Apple Events; macOS asks once per browser for permission.
enum FrontmostBrowser {
    struct Page {
        let url: URL
        let title: String?
    }

    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]
    private static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]

    /// Bundle id of the frontmost app *before* we show our panel.
    static func capture(from app: NSRunningApplication?) -> Page? {
        guard AppSettings.readsBrowser, let id = app?.bundleIdentifier else { return nil }
        let source: String
        if safari.contains(id) {
            source = """
            tell application id "\(id)"
                if (count of documents) is 0 then return ""
                return (URL of front document) & linefeed & (name of front document)
            end tell
            """
        } else if chromium.contains(id) {
            source = """
            tell application id "\(id)"
                if (count of windows) is 0 then return ""
                set t to active tab of front window
                return (URL of t) & linefeed & (title of t)
            end tell
            """
        } else {
            return nil
        }
        var error: NSDictionary?
        guard let output = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else { return nil }
        let lines = output.components(separatedBy: "\n")
        guard let first = lines.first, let url = URL(string: first),
              ["http", "https"].contains(url.scheme ?? "") else { return nil }
        let title = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return Page(url: url, title: title.isEmpty ? nil : title)
    }

    /// A link sitting on the clipboard, if any.
    static func clipboardURL() -> URL? {
        let pb = NSPasteboard.general
        if let s = pb.string(forType: .URL) ?? pb.string(forType: .string), LinkClassifier.isBareURL(s) {
            return LinkClassifier.firstURL(in: s)
        }
        return nil
    }
}
