import SwiftUI
import AppKit
import ShelfCore

// MARK: - Palette
//
// Native macOS colors throughout, so Shelf sits naturally beside Apple's own
// apps in light and dark, with the user's chosen accent. Color comes from
// the artwork itself (see ArtworkPalette), never from the chrome.
// The old names (paper, ink…) are kept as semantic aliases.

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? dark : light
        })
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    /// Content background (white / near-black, like Music and Notes).
    static let paper = Color(nsColor: .textBackgroundColor)
    /// Cards and fields sitting on the content background.
    static let paperRaised = Color(nsColor: .quaternarySystemFill)
    static let paperSunken = Color(nsColor: .windowBackgroundColor)
    static let ink = Color(nsColor: .labelColor)
    static let inkSoft = Color(nsColor: .secondaryLabelColor)
    static let inkFaint = Color(nsColor: .tertiaryLabelColor)
    static let hairline = Color(nsColor: .separatorColor)
    /// The chosen accent, for the little that should stand out.
    @MainActor static var glow: Color { .accent }
    /// Light accent tints: hover and selection, pills, icon buttons.
    @MainActor static var accentWash: Color { Color.accent.opacity(0.10) }
    @MainActor static var accentWashStrong: Color { Color.accent.opacity(0.17) }
    /// Neutral washes for tracks and fields.
    static let wash = Color(nsColor: .quaternarySystemFill)
    static let washStrong = Color(nsColor: .tertiarySystemFill)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension ItemKind {
    /// Generated covers: a quiet two-tone cloth in the shelf's muted hue.
    var coverGradient: [Color] {
        [Color(nsColor: baseColor(top: true)), Color(nsColor: baseColor(top: false))]
    }

    /// Generated covers on light paper (papers, articles) use ink type.
    var coverPrefersDarkText: Bool { self == .paper || self == .article }
}

// MARK: - Type

extension Font {
    /// Editorial serif (New York), kept for the few moments that matter:
    /// the greeting, page titles and an item's own title.
    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Everything else is SF Pro at a small, consistent scale.
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let cardTitle = Font.system(size: 12.5, weight: .medium)
    static let cardDetail = Font.system(size: 11.5)
    static let label = Font.system(size: 11.5, weight: .semibold)
}

/// Small section label. Sentence case and quiet, never shouty small caps.
struct Eyebrow: View {
    let text: String
    var color: Color = .inkFaint

    init(_ text: String, color: Color = .inkFaint) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.label)
            .foregroundStyle(color)
    }
}

// MARK: - Motion

extension Animation {
    static let shelf = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let lift = Animation.spring(response: 0.28, dampingFraction: 0.7)
}

/// Soft, layered shadow — closer to a real object on a real surface.
struct PaperShadow: ViewModifier {
    var lifted = false

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(lifted ? 0.10 : 0.07), radius: lifted ? 1.5 : 1, y: 1)
            .shadow(color: .black.opacity(lifted ? 0.14 : 0.08), radius: lifted ? 14 : 6, y: lifted ? 8 : 3)
    }
}

extension View {
    func paperShadow(lifted: Bool = false) -> some View { modifier(PaperShadow(lifted: lifted)) }

    func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) -> some View {
        simultaneousGesture(TapGesture().onEnded {
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        })
    }
}

enum Haptics {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
