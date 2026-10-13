import AppKit
import ShelfCore

enum ImageCache {
    /// Downloads cover art and stores a right-sized JPEG.
    static func download(_ url: URL) async -> Data? {
        guard let data = try? await HTTP.shared.data(url, accept: "image/*").0,
              let image = NSImage(data: data) else { return nil }
        // Some catalogues return a 1×1 placeholder when they have no cover.
        guard image.size.width > 8, image.size.height > 8 else { return nil }
        return jpeg(image, maxDimension: 900) ?? data
    }

    static func jpeg(_ image: NSImage, maxDimension: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxDimension / max(w, h))
        let size = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cg, size: NSSize(width: w, height: h)).draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
    }
}
