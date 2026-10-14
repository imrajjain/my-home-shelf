import AppKit
import SwiftUI
import CoreImage
import ShelfCore

/// Two calm colors taken from a cover (its top and bottom), for backdrops
/// in the spirit of Music and TV: the artwork tints the room, softly.
@MainActor
enum ArtworkPalette {
    private static var cache: [Int: [NSColor]] = [:]
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func colors(for item: Item) -> [NSColor] {
        if let data = item.imageData, let colors = colors(from: data) { return colors }
        return [item.kind.baseColor(top: true), item.kind.baseColor(top: false)]
    }

    static func colors(from data: Data) -> [NSColor]? {
        // Cheap, stable key: size plus a sample of bytes.
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(256))
        hasher.combine(data.suffix(256))
        let key = hasher.finalize()
        if let hit = cache[key] { return hit }

        guard let image = CIImage(data: data) else { return nil }
        let extent = image.extent
        let half = extent.height / 2
        // Core Image's origin is bottom-left: the top half has the larger y.
        let regions = [
            CGRect(x: extent.minX, y: extent.minY + half, width: extent.width, height: half),
            CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: half),
        ]
        let colors = regions.compactMap { average(image, in: $0) }.map(soften)
        guard colors.count == 2 else { return nil }
        cache[key] = colors
        return colors
    }

    private static func average(_ image: CIImage, in rect: CGRect) -> NSColor? {
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect),
        ]), let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }

    /// Keep the hue, tame saturation and brightness so nothing shouts.
    /// Warm tones (orange, brown, beige, yellow) go neutral grey instead:
    /// muted, they turn muddy.
    private static func soften(_ color: NSColor) -> NSColor {
        guard let c = color.usingColorSpace(.sRGB) else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let brightness = min(max(b, 0.32), 0.72)
        let isWarm = (0.02...0.18).contains(h)
        if isWarm || s < 0.12 { return NSColor(white: brightness * 0.85, alpha: 1) }
        return NSColor(hue: h, saturation: min(s, 0.5) * 0.9, brightness: brightness, alpha: 1)
    }
}

extension ItemKind {
    /// A muted hue per shelf, used only where there's no artwork.
    var hue: CGFloat? {
        switch self {
        case .book: 0.60        // slate blue
        case .film: 0.93        // plum
        case .show: 0.68        // indigo
        case .video: 0.98       // crimson
        case .podcast: 0.78     // violet
        case .music: 0.50       // teal
        case .place: 0.40       // green
        case .curiosity: 0.87   // magenta
        case .paper, .article: nil   // white sheet
        }
    }

    func baseColor(top: Bool) -> NSColor {
        guard let hue else {
            return top ? NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)
                       : NSColor(srgbRed: 0.88, green: 0.89, blue: 0.91, alpha: 1)
        }
        return top ? NSColor(hue: hue, saturation: 0.30, brightness: 0.62, alpha: 1)
                   : NSColor(hue: hue, saturation: 0.42, brightness: 0.36, alpha: 1)
    }
}

/// The artwork's colors as a soft wash from the top, fading into the
/// content background. Stronger in dark mode, where it reads as light.
struct ArtworkBackdrop: View {
    let colors: [NSColor]
    var height: CGFloat = 520
    var intensity: Double = 1
    @Environment(\.colorScheme) private var scheme

    private var isNeutral: Bool {
        colors.allSatisfy { color in
            guard let c = color.usingColorSpace(.sRGB) else { return true }
            return c.saturationComponent < 0.08 || c.alphaComponent < 0.05
        }
    }

    var body: some View {
        let strength = (scheme == .dark ? 0.55 : 0.30) * intensity
        ZStack(alignment: .top) {
            Color.paper
            // A faint accent glow from the top corner gives every page a
            // little light of its own, artwork or not.
            GeometryReader { geo in
                let peak = (scheme == .dark ? 0.15 : 0.085) * intensity
                let reach = max(geo.size.width, height) * 1.15
                // Wide and eased: centered just above the top edge, past
                // the right side, so it reads as light falling in rather
                // than a spot in the corner.
                RadialGradient(
                    stops: [
                        .init(color: Color.accent.opacity(peak), location: 0),
                        .init(color: Color.accent.opacity(peak * 0.62), location: 0.28),
                        .init(color: Color.accent.opacity(peak * 0.30), location: 0.55),
                        .init(color: Color.accent.opacity(peak * 0.10), location: 0.80),
                        .init(color: Color.accent.opacity(0), location: 1),
                    ],
                    center: UnitPoint(x: 0.92, y: -0.25),
                    startRadius: 0, endRadius: reach
                )
            }
            .frame(height: height * 1.4)
            // Always dissolve fully before the frame ends: no visible edge.
            .mask(LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.55), location: 0.45),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom))
            // The artwork's own tint, only when it has one: neutral covers
            // (grey, cream, white) would just lay a pale haze over the page.
            if !isNeutral {
                LinearGradient(
                    stops: [
                        .init(color: Color(nsColor: colors[0]).opacity(strength), location: 0),
                        .init(color: Color(nsColor: colors[1]).opacity(strength * 0.55), location: 0.45),
                        .init(color: Color(nsColor: colors[1]).opacity(0), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: height)
                // Fade out fully toward the right, where the accent glow lives.
                .mask(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.5), location: 0.5),
                    .init(color: .clear, location: 0.9),
                ], startPoint: .leading, endPoint: .trailing))
            }
            bloom
        }
        .ignoresSafeArea()
    }

    /// The chosen line art, sprouting from the same corner as the glow.
    private var bloom: some View {
        BackdropArtLayer(art: Appearance.shared.art, intensity: intensity)
            .frame(height: height * 1.2)
    }
}
