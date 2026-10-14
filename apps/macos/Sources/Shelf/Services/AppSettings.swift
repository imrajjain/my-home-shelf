import Foundation
import ShelfCore

/// UserDefaults keys, shared by `@AppStorage` in views and plain code.
enum SettingsKey {
    static let tmdbAPIKey = "tmdbAPIKey"
    static let hotKey = "hotKeyPreset"
    static let apiToken = "localAPIToken"
    static let apiEnabled = "localAPIEnabled"
    static let name = "displayName"
    static let readsBrowser = "captureReadsFrontmostBrowser"
    static let accent = "accentColor"
    static let backdropArt = "backdropArt"
    static let shuffleAccent = "shuffleAccent"
    static let shuffleArt = "shuffleArt"
    static let goodreads = "goodreadsProfile"
    static let goodreadsLastSync = "goodreadsLastSync"
    static let goodreadsCount = "goodreadsCount"
}

enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    static var tmdbAPIKey: String? { defaults.string(forKey: SettingsKey.tmdbAPIKey) }

    static var displayName: String {
        let stored = defaults.string(forKey: SettingsKey.name)?.trimmingCharacters(in: .whitespaces) ?? ""
        if !stored.isEmpty { return stored }
        return NSFullUserName().components(separatedBy: " ").first ?? ""
    }

    static var apiEnabled: Bool {
        defaults.object(forKey: SettingsKey.apiEnabled) as? Bool ?? true
    }

    static var readsBrowser: Bool {
        defaults.object(forKey: SettingsKey.readsBrowser) as? Bool ?? true
    }

    /// Pairing token for the browser extension; created on first use.
    static var apiToken: String {
        if let token = defaults.string(forKey: SettingsKey.apiToken), !token.isEmpty { return token }
        let token = LocalAPI.makeToken()
        defaults.set(token, forKey: SettingsKey.apiToken)
        return token
    }

    static func regenerateToken() {
        defaults.set(LocalAPI.makeToken(), forKey: SettingsKey.apiToken)
    }

    static var metadata: MetadataService {
        MetadataService.standard(tmdbAPIKey: tmdbAPIKey, extraProviders: [PlaceSearchProvider()])
    }
}
