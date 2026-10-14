import SwiftUI
import ShelfCore

/// Five quiet stars. Click the current rating again to clear it.
struct RatingView: View {
    @Binding var rating: Int
    var size: CGFloat = 14
    var tint: Color = Color.accent
    @State private var hovered: Int?

    private let spacing: CGFloat = 3
    private var cell: CGFloat { (size * 1.3).rounded() }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { star in
                let lit = star <= (hovered ?? rating)
                Image(systemName: lit ? "star.fill" : "star")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(lit ? tint : Color.inkFaint.opacity(0.6))
                    .scaleEffect(hovered == star ? 1.18 : 1)
                    .frame(width: cell, height: cell)
            }
        }
        // One hover/tap region for the row; the star comes from the x position.
        // (Per-star hover areas overlapped once a star scaled up, so the
        // highlight stuck on the wrong star.)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let star = star(at: point.x)
                if hovered != star { withAnimation(.lift) { hovered = star } }
            case .ended:
                withAnimation(.lift) { hovered = nil }
            }
        }
        .gesture(SpatialTapGesture().onEnded { tap in
            let star = star(at: tap.location.x)
            withAnimation(.lift) { rating = (rating == star) ? 0 : star }
            Haptics.tap()
        })
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating) of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(0, rating - 1)
            @unknown default: break
            }
        }
    }

    private func star(at x: CGFloat) -> Int {
        min(5, max(1, Int(x / (cell + spacing)) + 1))
    }
}

/// Status in the item's own words ("Want to read · Reading · Read").
struct StatusPicker: View {
    let kind: ItemKind
    @Binding var status: ItemStatus
    var includeDropped = false
    var compact = false

    var body: some View {
        PillPicker(
            selection: $status,
            options: ItemStatus.allCases
                .filter { includeDropped || $0 != .dropped || status == .dropped }
                .map { .init(value: $0, title: kind.label(for: $0)) },
            compact: compact
        )
    }
}

/// Tags as soft chips, with an inline field to add more.
struct TagEditor: View {
    @Binding var tags: [String]
    @State private var draft = ""

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text("#\(tag)").font(.system(size: 11.5, weight: .medium))
                    Button {
                        withAnimation(.shelf) { tags.removeAll { $0 == tag } }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.inkFaint)
                }
                .foregroundStyle(Color.inkSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.wash, in: Capsule())
            }
            TextField("Add tag", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .frame(width: 80)
                .onSubmit(commit)
        }
    }

    private func commit() {
        let tag = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "#", with: "")
        draft = ""
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        withAnimation(.shelf) { tags.append(tag) }
    }
}

/// Wraps children onto new lines, like words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A calm empty state: one symbol, one line of help, at most one action.
struct EmptyShelf: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.accent.opacity(0.8))
                .padding(.bottom, 6)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, systemImage: "plus", action: action)
                    .buttonStyle(.pillPrimary)
                    .padding(.top, 10)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A keycap, for teaching shortcuts in place.
struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.inkSoft)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.hairline))
    }
}
