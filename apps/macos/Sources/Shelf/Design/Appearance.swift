import SwiftUI
import AppKit
import Observation

/// The accent the user picked in Settings (blue unless they choose).
/// Views read `Color.accent`, which Observation tracks, so a change in
/// Settings recolors the whole app at once.
enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, indigo, purple, pink, red, orange, green, teal, graphite

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .green: .systemGreen
        case .teal: .systemTeal
        case .graphite: .systemGray
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

@MainActor
@Observable
final class Appearance {
    static let shared = Appearance()

    var accent: AccentChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: SettingsKey.accent) }
    }

    /// The line art sprouting from each page's corner.
    var art: BackdropArt {
        didSet { UserDefaults.standard.set(art.rawValue, forKey: SettingsKey.backdropArt) }
    }

    /// Something new each time Shelf opens: a fresh accent and/or art,
    /// never the same as last time.
    var shuffleAccent: Bool {
        didSet { UserDefaults.standard.set(shuffleAccent, forKey: SettingsKey.shuffleAccent) }
    }
    var shuffleArt: Bool {
        didSet { UserDefaults.standard.set(shuffleArt, forKey: SettingsKey.shuffleArt) }
    }

    private init() {
        let defaults = UserDefaults.standard
        let lastAccent = defaults.string(forKey: SettingsKey.accent).flatMap(AccentChoice.init(rawValue:)) ?? .blue
        let lastArt = defaults.string(forKey: SettingsKey.backdropArt).flatMap(BackdropArt.init(rawValue:)) ?? .warli
        let shufflingAccent = defaults.bool(forKey: SettingsKey.shuffleAccent)
        let shufflingArt = defaults.bool(forKey: SettingsKey.shuffleArt)
        shuffleAccent = shufflingAccent
        shuffleArt = shufflingArt
        // Graphite and "None" aren't much of a surprise, so shuffle skips them.
        accent = shufflingAccent
            ? AccentChoice.allCases.filter { $0 != lastAccent && $0 != .graphite }.randomElement() ?? lastAccent
            : lastAccent
        art = shufflingArt
            ? BackdropArt.allCases.filter { $0 != lastArt && $0 != .none }.randomElement() ?? lastArt
            : lastArt
        // Remember today's pick, so tomorrow's is different again.
        defaults.set(accent.rawValue, forKey: SettingsKey.accent)
        defaults.set(art.rawValue, forKey: SettingsKey.backdropArt)
    }

    /// Choosing a specific color or style turns shuffling off for it.
    func choose(_ choice: AccentChoice) { accent = choice; shuffleAccent = false }
    func choose(_ choice: BackdropArt) { art = choice; shuffleArt = false }
}

extension Color {
    /// The app's accent. Use this, not `Color.accentColor` (the system's).
    @MainActor static var accent: Color { Appearance.shared.accent.color }
}
