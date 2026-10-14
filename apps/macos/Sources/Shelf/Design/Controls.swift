import SwiftUI
import AppKit
import ShelfCore

// MARK: - Buttons
//
// A small, consistent set in the spirit of Airbnb and Apple Music:
// one solid ink pill for the action that matters on a screen, soft pills
// for everything else, round icon buttons that only fill in on hover, and
// frosted glass for controls that sit on artwork. Everything gives under
// the pointer and the press.

extension Color {
    /// The raised thumb of a pill picker: white on light, lifted grey on dark.
    static let pillThumb = Color(light: .white, dark: NSColor(white: 1, alpha: 0.17))
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, glass }
    var kind: Kind = .secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, kind: kind, compact: compact)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PillButtonStyle.Kind
    let compact: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .labelStyle(PillLabelStyle())
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 11 : 16)
            .padding(.vertical, compact ? 5 : 8)
            .background { background }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: Color.accent
        case .glass: .ink
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            // Accent with a soft sheen from the top, like light on a pill.
            Capsule().fill(Color.accent)
                .overlay(Capsule().fill(LinearGradient(
                    colors: [.white.opacity(hovering ? 0.30 : 0.22), .clear],
                    startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: Color.accent.opacity(hovering ? 0.45 : 0.28), radius: hovering ? 10 : 5, y: 2)
        case .secondary:
            Capsule().fill(hovering ? Color.accentWashStrong : Color.accentWash)
        case .glass:
            Capsule().fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
    }
}

/// Icon and title close together, icon a touch lighter.
private struct PillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 11.5, weight: .bold))
            configuration.title
        }
    }
}

/// A round icon button. `.plain` fills in on hover; `.glass` floats on artwork.
struct IconButtonStyle: ButtonStyle {
    enum Kind { case plain, glass }
    var kind: Kind = .plain
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, kind: kind, size: size)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: IconButtonStyle.Kind
    let size: CGFloat
    @State private var hovering = false

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(kind == .glass ? Color.ink : (hovering ? Color.accent : Color.inkSoft))
            .frame(width: size, height: size)
            .background {
                switch kind {
                case .plain:
                    Circle().fill(hovering ? Color.accentWash : Color.clear)
                case .glass:
                    Circle().fill(.regularMaterial)
                        .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
                }
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : (hovering && kind == .glass ? 1.06 : 1))
            .onHover { hovering = $0 }
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pillPrimary: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var pill: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var pillCompact: PillButtonStyle { PillButtonStyle(kind: .secondary, compact: true) }
    static var pillGlass: PillButtonStyle { PillButtonStyle(kind: .glass, compact: true) }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
    static var iconGlass: IconButtonStyle { IconButtonStyle(kind: .glass, size: 30) }
}

// MARK: - Pill picker

/// A capsule track with a raised thumb that glides between options —
/// for status, filters and layout. Options can be words or symbols.
struct PillPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        var symbol: String?
    }

    @Binding var selection: Value
    let options: [Option]
    var compact = false
    @Namespace private var ns
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = option.value }
                } label: {
                    Group {
                        if let symbol = option.symbol {
                            Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold))
                                .frame(width: 18)
                        } else {
                            Text(option.title)
                                .font(.system(size: compact ? 11.5 : 12.5, weight: selected ? .semibold : .medium))
                        }
                    }
                    .foregroundStyle(selected ? Color.accent : (hovered == option.value ? Color.ink : Color.inkSoft))
                    .padding(.horizontal, option.symbol == nil ? (compact ? 10 : 13) : 7)
                    .padding(.vertical, compact ? 4 : 6)
                    .background {
                        if selected {
                            Capsule().fill(Color.pillThumb)
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .onHover { inside in
                    withAnimation(.easeOut(duration: 0.12)) {
                        hovered = inside ? option.value : (hovered == option.value ? nil : hovered)
                    }
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.wash))
        .fixedSize()
    }
}

// MARK: - Category strip

/// Airbnb-style categories: a symbol over a short label, the chosen one in
/// full ink with a fine underline that slides along.
struct CategoryStrip<Value: Hashable>: View {
    struct Category {
        let value: Value
        let title: String
        let symbol: String
    }

    @Binding var selection: Value
    let categories: [Category]
    @Namespace private var ns
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(categories, id: \.value) { category in
                let selected = category.value == selection
                let lit = selected || hovered == category.value
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selection = category.value }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(selected ? Color.accent : (lit ? Color.ink : Color.inkFaint))
                            .frame(height: 20)
                        Text(category.title)
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 2)
                            if selected {
                                Capsule().fill(Color.accent).frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: ns)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .foregroundStyle(lit ? Color.ink : Color.inkFaint)
                    .frame(width: 62)
                    .padding(.top, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .onHover { inside in
                    withAnimation(.easeOut(duration: 0.12)) {
                        hovered = inside ? category.value : (hovered == category.value ? nil : hovered)
                    }
                }
            }
        }
    }
}
