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

    private init() {
        accent = UserDefaults.standard.string(forKey: SettingsKey.accent).flatMap(AccentChoice.init(rawValue:)) ?? .blue
        art = UserDefaults.standard.string(forKey: SettingsKey.backdropArt).flatMap(BackdropArt.init(rawValue:)) ?? .warli
    }
}

extension Color {
    /// The app's accent. Use this, not `Color.accentColor` (the system's).
    @MainActor static var accent: Color { Appearance.shared.accent.color }
}
