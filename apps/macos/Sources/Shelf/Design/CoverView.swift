import SwiftUI
import AppKit
import ShelfCore

/// The face of an item: cached art, then remote art, then a typeset cover
/// generated from the title — so nothing on the shelf ever looks broken.
struct CoverView: View {
    let kind: ItemKind
    let title: String
    var creator: String?
    var imageData: Data?
    var imageURL: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .aspectRatio(kind.coverAspect, contentMode: .fit)
            .overlay { art }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // A whisper of an edge, like light catching a dust jacket.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
            .overlay(alignment: .leading) {
                if kind == .book {
                    // Spine crease.
                    LinearGradient(colors: [.black.opacity(0.18), .white.opacity(0.08), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 7)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: cornerRadius))
                }
            }
    }

    @ViewBuilder private var art: some View {
        if let imageData, let image = NSImage(data: imageData) {
            Image(nsImage: image).resizable().scaledToFill()
        } else if let imageURL {
            AsyncImage(url: imageURL, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .empty: GeneratedCover(kind: kind, title: title, creator: creator).opacity(0.6)
                default: GeneratedCover(kind: kind, title: title, creator: creator)
                }
            }
        } else {
            GeneratedCover(kind: kind, title: title, creator: creator)
        }
    }
}

/// A cover designed on the fly: gradient cloth, a fine rule, serif title.
struct GeneratedCover: View {
    let kind: ItemKind
    let title: String
    var creator: String?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let ink: Color = kind.coverPrefersDarkText ? Color(hex: 0x2A2420) : .white
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: kind.coverGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                // Subtle paper grain via a radial bloom.
                RadialGradient(colors: [.white.opacity(0.22), .clear], center: .topLeading,
                               startRadius: 0, endRadius: w * 1.2)
                VStack(alignment: .leading, spacing: w * 0.05) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: max(9, w * 0.09), weight: .medium))
                        .opacity(0.75)
                    Rectangle().fill(ink.opacity(0.35)).frame(width: w * 0.22, height: 1)
                    Spacer(minLength: 0)
                    Text(title)
                        .font(.display(max(10, w * 0.12), weight: .semibold))
                        .lineLimit(kind.coverAspect < 1 ? 5 : 3)
                        .minimumScaleFactor(0.6)
                    if let creator, !creator.isEmpty {
                        Text(creator)
                            .font(.system(size: max(8, w * 0.065), weight: .medium))
                            .opacity(0.75)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(ink)
                .padding(w * 0.11)
            }
        }
    }
}

extension CoverView {
    init(item: Item, cornerRadius: CGFloat = 8) {
        self.init(kind: item.kind, title: item.title, creator: item.creator,
                  imageData: item.imageData, imageURL: item.imageURL, cornerRadius: cornerRadius)
    }

    init(metadata m: Metadata, cornerRadius: CGFloat = 6) {
        self.init(kind: m.kind, title: m.title, creator: m.creator, imageURL: m.imageURL, cornerRadius: cornerRadius)
    }
}
