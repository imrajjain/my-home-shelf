import SwiftUI
import ShelfCore

/// A cover on the shelf. Lifts toward you on hover; click to inspect,
/// double-click to open.
struct ItemCard: View {
    let item: Item
    var width: CGFloat = 150
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
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(item.kind.tint, lineWidth: isSelected ? 2.5 : 0)
                        .padding(-3)
                }
                .paperShadow(lifted: hovering)
                .scaleEffect(hovering ? 1.035 : 1, anchor: .bottom)
                .rotation3DEffect(.degrees(hovering ? -2 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.display(13.5, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    // Reserve both lines so covers in a row stay level.
                    .lineLimit(2, reservesSpace: true)
                Text(item.byline.isEmpty ? (item.host ?? item.kind.title) : item.byline)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.inkSoft)
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

    @ViewBuilder private var badges: some View {
        HStack(spacing: 4) {
            if item.status == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(item.kind.tint, in: Circle())
            }
            if item.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color(hex: 0xD9536F), in: Circle())
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        .padding(7)
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
        HStack(alignment: .top, spacing: 14) {
            CoverView(item: item, cornerRadius: 5)
                .frame(width: 46)
                .paperShadow()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    KindBadge(kind: item.kind, compact: true)
                    if let venue = item.extra["venue"] ?? item.host {
                        Text(venue).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.inkFaint).lineLimit(1)
                    }
                }
                Text(item.title)
                    .font(.display(15.5, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if !item.byline.isEmpty {
                    Text(item.byline).font(.system(size: 12)).foregroundStyle(Color.inkSoft).lineLimit(1)
                }
                if let summary = item.summary, hovering || router.selectedItemID == item.id {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSoft)
                        .lineLimit(2)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Text(item.statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(item.status == .done ? item.kind.tint : Color.inkSoft)
                Text(item.createdAt, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkFaint)
                if item.isFavorite {
                    Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(Color(hex: 0xD9536F))
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(router.selectedItemID == item.id && router.showingInspector
                      ? item.kind.tint.opacity(0.10)
                      : (hovering ? Color.paperRaised : Color.clear))
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
