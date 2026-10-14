import SwiftUI
import ShelfCore

/// A cover on the shelf. Lifts toward you on hover; click to inspect,
/// double-click to open.
struct ItemCard: View {
    let item: Item
    var width: CGFloat = 150
    /// Height of the cover area, shared by a whole row so mixed shapes
    /// (posters, video stills, square albums) sit on one shelf line.
    var coverHeight: CGFloat?
    @Environment(Router.self) private var router
    @State private var hovering = false

    private var isSelected: Bool { router.selectedItemID == item.id && router.showingInspector }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            CoverView(item: item)
                .frame(width: width)
                .overlay(alignment: .topTrailing) { badges }
                .overlay(alignment: .bottom) { progressBar }
                .overlay {
                    if item.isEnriching { Shimmer().clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)) }
                }
                .overlay { if hovering { hoverControls.transition(.opacity) } }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.glow, lineWidth: isSelected ? 2 : 0)
                        .padding(-4)
                }
                .paperShadow(lifted: hovering)
                .scaleEffect(hovering ? 1.015 : 1, anchor: .bottom)
                .frame(width: width, height: coverHeight, alignment: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.cardTitle)
                    .foregroundStyle(Color.ink)
                    // Reserve both lines so covers in a row stay level.
                    .lineLimit(2, reservesSpace: true)
                Text(item.byline.isEmpty ? (item.host ?? item.kind.title) : item.byline)
                    .font(.cardDetail)
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.lift) { hovering = inside } }
        .onTapGesture(count: 2) { if let url = item.url { NSWorkspace.shared.open(url) } }
        .onTapGesture { withAnimation(.shelf) { router.open(item) } }
        .contextMenu { ItemContextMenu(item: item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.kind.title), \(item.statusLabel)")
        .accessibilityAddTraits(.isButton)
    }

    /// Apple Music-style: on hover, a soft shade and two glass buttons —
    /// the natural next step, and everything else.
    private var hoverControls: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.38)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            HStack {
                if let next = nextStep {
                    Button(next.title, systemImage: next.symbol) {
                        withAnimation(.shelf) { item.status = next.status }
                        Haptics.tap()
                    }
                    .buttonStyle(.iconGlass)
                    .help(next.title)
                }
                Spacer()
                Menu {
                    ItemContextMenu(item: item)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.iconGlass)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var nextStep: (status: ItemStatus, title: String, symbol: String)? {
        switch item.status {
        case .want: (.inProgress, item.kind.label(for: .inProgress), "play.fill")
        case .inProgress: (.done, "Mark as \(item.kind.label(for: .done).lowercased())", "checkmark")
        case .done, .dropped: nil
        }
    }

    @ViewBuilder private var badges: some View {
        // Only "finished" earns a mark on the cover; favorites live in details.
        if item.status == .done {
            Image(systemName: "checkmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.black.opacity(0.45), in: Circle())
                .padding(6)
        }
    }

    @ViewBuilder private var progressBar: some View {
        if item.status == .inProgress, item.progress > 0, item.progress < 1 {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.25))
                    Capsule().fill(.white).frame(width: geo.size.width * item.progress)
                }
            }
            .frame(height: 3)
            .padding(8)
        }
    }
}

/// A line in a reading list — best for papers and articles.
struct ItemRow: View {
    let item: Item
    @Environment(Router.self) private var router
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CoverView(item: item, cornerRadius: 4)
                .frame(width: 38)
                .paperShadow()
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text([item.byline, item.extra["venue"] ?? item.host ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(item.createdAt, format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(Color.inkFaint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(router.selectedItemID == item.id && router.showingInspector
                      ? Color.accentWashStrong
                      : (hovering ? Color.accentWash.opacity(0.6) : Color.clear))
        }
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.lift) { hovering = inside } }
        .onTapGesture(count: 2) { if let url = item.url { NSWorkspace.shared.open(url) } }
        .onTapGesture { withAnimation(.shelf) { router.open(item) } }
        .contextMenu { ItemContextMenu(item: item) }
    }
}

struct ItemContextMenu: View {
    let item: Item
    @Environment(Router.self) private var router

    var body: some View {
        if let url = item.url {
            Button("Open Link") { NSWorkspace.shared.open(url) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            Divider()
        }
        ForEach(ItemStatus.allCases) { status in
            Button {
                withAnimation(.shelf) { item.status = status }
            } label: {
                if item.status == status {
                    Label(item.kind.label(for: status), systemImage: "checkmark")
                } else {
                    Text(item.kind.label(for: status))
                }
            }
        }
        Divider()
        Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            withAnimation(.shelf) { item.isFavorite.toggle(); item.touch() }
        }
        Menu("Move to Shelf") {
            ForEach(ItemKind.allCases) { kind in
                Button(kind.pluralTitle) { withAnimation(.shelf) { item.kind = kind } }
            }
        }
        Button("Refresh Details") { CaptureCoordinator.shared.refresh(item) }
        Divider()
        Button("Remove from Shelf", role: .destructive) { ItemActions.delete(item, router: router) }
    }
}

/// Soft moving sheen while metadata is on its way.
struct Shimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.6)
                .offset(x: phase * geo.size.width * 1.6)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}
