import SwiftUI
import AppKit
import ShelfCore

// MARK: - Palette
//
// Warm paper and ink, not grey chrome. Every color adapts to dark mode,
// where the shelf becomes a lamp-lit study rather than an inverted page.

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? dark : light
        })
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    static let paper = Color(light: NSColor(hex: 0xF7F2EA), dark: NSColor(hex: 0x1B1917))
    static let paperRaised = Color(light: NSColor(hex: 0xFFFCF7), dark: NSColor(hex: 0x252220))
    static let paperSunken = Color(light: NSColor(hex: 0xEFE8DC), dark: NSColor(hex: 0x151312))
    static let ink = Color(light: NSColor(hex: 0x2A2420), dark: NSColor(hex: 0xEFE7DA))
    static let inkSoft = Color(light: NSColor(hex: 0x6E6359), dark: NSColor(hex: 0xA89C8E))
    static let inkFaint = Color(light: NSColor(hex: 0xA79A8C), dark: NSColor(hex: 0x6F655B))
    static let hairline = Color(light: NSColor(hex: 0x2A2420, alpha: 0.08), dark: NSColor(hex: 0xEFE7DA, alpha: 0.08))
    static let glow = Color(light: NSColor(hex: 0xE8A35C), dark: NSColor(hex: 0xF0B370))
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
    /// Each shelf has its own quiet accent.
    var tint: Color {
        switch self {
        case .book: Color(hex: 0xC4643F)       // terracotta
        case .film: Color(hex: 0x8E4A6B)       // plum
        case .show: Color(hex: 0x4F5BA6)       // indigo
        case .paper: Color(hex: 0x5E8A6E)      // sage
        case .article: Color(hex: 0xC48A2C)    // amber
        case .video: Color(hex: 0xC2493F)      // vermilion
        case .podcast: Color(hex: 0x7A5BB0)    // violet
        case .music: Color(hex: 0x2F8C8C)      // teal
        case .place: Color(hex: 0x3F7FA6)      // lake
        case .curiosity: Color(hex: 0xC2577E)  // rose
        }
    }

    /// Two-tone gradient used for generated covers when no art exists.
    var coverGradient: [Color] {
        switch self {
        case .book: [Color(hex: 0xD9825A), Color(hex: 0x9E4529)]
        case .film: [Color(hex: 0xA6627F), Color(hex: 0x5E2C45)]
        case .show: [Color(hex: 0x6C78C2), Color(hex: 0x323C7D)]
        case .paper: [Color(hex: 0xEDE8DC), Color(hex: 0xD8D0BF)]
        case .article: [Color(hex: 0xF3E4C3), Color(hex: 0xDDC394)]
        case .video: [Color(hex: 0xD96B5F), Color(hex: 0x8F2E26)]
        case .podcast: [Color(hex: 0x9479C7), Color(hex: 0x4E3880)]
        case .music: [Color(hex: 0x4DAAA6), Color(hex: 0x1D5E5E)]
        case .place: [Color(hex: 0x6BA6C9), Color(hex: 0x2B5C7D)]
        case .curiosity: [Color(hex: 0xE08AA8), Color(hex: 0x9A3A60)]
        }
    }

    /// Generated covers on light paper (papers, articles) use ink type.
    var coverPrefersDarkText: Bool { self == .paper || self == .article }
}

// MARK: - Type

extension Font {
    /// Editorial serif (New York) for titles and moments that matter.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let eyebrow = Font.system(size: 10.5, weight: .semibold).width(.expanded)
}

struct Eyebrow: View {
    let text: String
    var color: Color = .inkFaint

    init(_ text: String, color: Color = .inkFaint) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.eyebrow)
            .tracking(1.4)
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
            .shadow(color: .black.opacity(lifted ? 0.10 : 0.06), radius: lifted ? 2 : 1, y: 1)
            .shadow(color: .black.opacity(lifted ? 0.18 : 0.10), radius: lifted ? 18 : 8, y: lifted ? 14 : 5)
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
