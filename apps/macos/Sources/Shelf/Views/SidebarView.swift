import SwiftUI
import ShelfCore

struct SidebarView: View {
    let items: [Item]
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        List(selection: $router.selection) {
            Section {
                row(.home, count: nil)
                row(.status(.want), count: items.tally { $0.status == .want })
                row(.status(.inProgress), count: items.tally { $0.status == .inProgress })
                row(.status(.done), count: items.tally { $0.status == .done })
                row(.favorites, count: items.tally { $0.isFavorite })
            }

            Section("Shelves") {
                ForEach(ItemKind.allCases) { kind in
                    let count = items.tally { $0.kind == kind }
                    if count > 0 || [.book, .film, .show, .paper, .article].contains(kind) {
                        row(.kind(kind), count: count, tint: kind.tint)
                    }
                }
            }

            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags.prefix(16), id: \.0) { tag, count in
                        row(.tag(tag), count: count)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { captureHint }
    }

    private func row(_ selection: SidebarSelection, count: Int?, tint: Color? = nil) -> some View {
        Label {
            HStack {
                Text(selection.title)
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: selection.symbol)
                .foregroundStyle(tint ?? Color.inkSoft)
        }
        .tag(selection)
    }

    private var tags: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items { for tag in item.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    }

    private var captureHint: some View {
        Button {
            QuickCaptureController.shared.show(prefill: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.glow)
                Text("Capture from anywhere")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.inkSoft)
                Spacer()
                if HotKeyPreset.current != .off { KeyCap(HotKeyPreset.current.title) }
            }
            .padding(10)
            .background(Color.paperRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(10)
    }
}

extension Sequence {
    func tally(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
