import SwiftUI
import ShelfCore

/// Navigation only: no counts, no colors, nothing asking for attention.
/// Shelves appear once something is on them; tags stay folded away.
struct SidebarView: View {
    let items: [Item]
    @Environment(Router.self) private var router
    @AppStorage("sidebar.tagsExpanded") private var tagsExpanded = false

    var body: some View {
        // Selection is drawn here rather than by List: macOS always paints
        // sidebar selection in the system accent, and Shelf has its own.
        List {
            Section {
                row(.home)
                row(.status(.want))
                row(.status(.inProgress))
                row(.status(.done))
                if items.contains(where: \.isFavorite) { row(.favorites) }
            }

            Section("Shelves") {
                ForEach(shelves) { kind in row(.kind(kind)) }
            }

            if Account.shared.isSignedIn {
                Section("People") {
                    row(.people)
                    ForEach(FriendsList.shared.people) { person in row(.person(person.username)) }
                }
            }

            Section("Museum") {
                ForEach(Exhibit.allCases, id: \.self) { exhibit in row(.exhibit(exhibit)) }
            }

            if !tags.isEmpty {
                Section("Tags", isExpanded: $tagsExpanded) {
                    ForEach(tags.prefix(12), id: \.self) { tag in row(.tag(tag)) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { SidebarFooter() }
    }

    private func row(_ selection: SidebarSelection) -> some View {
        SidebarRow(selection: selection, isSelected: (router.selection ?? .home) == selection) {
            router.selection = selection
        }
    }

    /// Shelves in use, in their natural order. A brand-new shelf shows the
    /// common ones so there is somewhere to start.
    private var shelves: [ItemKind] {
        let used = Set(items.map(\.kind))
        if used.isEmpty { return [.book, .film, .show, .paper, .article] }
        return ItemKind.allCases.filter(used.contains)
    }

    /// Most-used first.
    private var tags: [String] {
        var counts: [String: Int] = [:]
        for item in items { for tag in item.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }
}

extension Sequence {
    func tally(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}

/// A sidebar row with the selection in Shelf's accent: solid when the
/// window is key, a quiet wash when it isn't — as native selection does.
private struct SidebarRow: View {
    let selection: SidebarSelection
    let isSelected: Bool
    let select: () -> Void
    @Environment(\.controlActiveState) private var activeState
    @State private var hovering = false

    private var isActive: Bool { activeState == .key || activeState == .active }

    var body: some View {
        Label {
            Text(selection.title)
                .foregroundStyle(isSelected && isActive ? Color.white : Color.ink)
        } icon: {
            Image(systemName: selection.symbol)
                .foregroundStyle(isSelected && isActive ? Color.white : (isSelected ? Color.accent : Color.inkSoft))
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
                .padding(.horizontal, 10)
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var background: Color {
        if isSelected { return isActive ? Color.accent : Color.washStrong }
        return hovering ? Color.wash : .clear
    }
}

/// Settings within reach, and a quiet word on the Goodreads sync.
private struct SidebarFooter: View {
    private var sync: GoodreadsSync { .shared }

    var body: some View {
        HStack(spacing: 6) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.icon)
            .help("Settings (⌘,)")

            if sync.source != nil {
                Button {
                    Task { await sync.sync() }
                } label: {
                    HStack(spacing: 5) {
                        if sync.state == .syncing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(status).lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkFaint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(sync.state == .syncing)
                .help("Sync with Goodreads now (⌘R)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var status: String {
        switch sync.state {
        case .syncing: "Syncing…"
        case .synced(_, let at): "Goodreads · \(at.formatted(.relative(presentation: .named)))"
        case .failed: "Goodreads · couldn’t sync"
        case .idle: "Goodreads"
        }
    }
}
