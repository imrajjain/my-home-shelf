import SwiftUI
import ShelfCore

/// The happy place: a greeting, what you're in the middle of, what's
/// next, and a small celebration of what you've already loved.
struct HomeView: View {
    let items: [Item]
    @Environment(Router.self) private var router
    @AppStorage(SettingsKey.name) private var storedName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                if items.isEmpty {
                    WelcomeView()
                } else {
                    if !inProgress.isEmpty { continueSection }
                    if !upNextVisual.isEmpty {
                        shelfRow("Up next", items: upNextVisual, see: .status(.want))
                    }
                    if !readingList.isEmpty { readingListSection }
                    if !recentlyFinished.isEmpty {
                        shelfRow("Recently finished", items: recentlyFinished, see: .status(.done), note: yearNote)
                    }
                    WikipediaSection(items: items)
                    if let memory { memorySection(memory) }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 28)
            .padding(.bottom, 56)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity)
            // The thing you're in the middle of quietly tints the top of Home.
            .background(alignment: .top) {
                ArtworkBackdrop(
                    colors: (inProgress.first ?? dailyPick).map(ArtworkPalette.colors(for:)) ?? [.clear, .clear],
                    height: 420, intensity: 0.7
                )
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.inkFaint)
            Text(greeting)
                .font(.display(30, weight: .regular))
                .foregroundStyle(Color.ink)
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.inkSoft)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        let name = storedName.isEmpty ? AppSettings.displayName : storedName
        return name.isEmpty ? "\(part)." : "\(part), \(name)."
    }

    private var subtitle: String {
        if items.isEmpty { return "A quiet place for what you want to read, watch and remember." }
        if let current = inProgress.first { return "You’re in the middle of \(current.title)." }
        if let pick = dailyPick { return "\(pick.title) is here whenever you’re ready." }
        return "Everything you’ve finished, kept in one place."
    }

    // MARK: Sections

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Continue", action: inProgress.count > 3 ? { router.selection = .status(.inProgress) } : nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(inProgress.prefix(8)) { item in
                        ContinueCard(item: item)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, -4)
        }
    }

    private func shelfRow(_ title: String, items: [Item], see: SidebarSelection, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: title, note: note, action: items.count > 6 ? { router.selection = see } : nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(items.prefix(16)) { item in
                        ItemCard(item: item, width: item.kind.coverAspect >= 1 ? 168 : 116, coverHeight: 174)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, -4)
        }
    }

    private var yearNote: String? {
        let count = finishedThisYear.count
        guard count > 0 else { return nil }
        return "\(count) this year"
    }

    private var readingListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Reading list", action: readingList.count > 5 ? { router.selection = .kind(.article) } : nil)
            VStack(spacing: 2) {
                ForEach(readingList.prefix(5)) { item in ItemRow(item: item) }
            }
        }
    }

    private func memorySection(_ item: Item) -> some View {
        HStack(alignment: .center, spacing: 22) {
            CoverView(item: item, cornerRadius: 6)
                .frame(width: 76)
                .paperShadow()
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("From your archive")
                Text(item.title)
                    .font(.display(19))
                    .foregroundStyle(Color.ink)
                if let finished = item.finishedAt {
                    Text("You finished it \(finished.formatted(.relative(presentation: .named))).\(item.rating >= 4 ? " You loved it." : "")")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.inkSoft)
                }
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.display(14, weight: .regular).italic())
                        .foregroundStyle(Color.inkSoft)
                        .lineLimit(3)
                }
                Button("Revisit") { router.open(item) }
                    .buttonStyle(.pillCompact)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .padding(20)
        .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.hairline))
    }

    // MARK: Data

    private var inProgress: [Item] {
        items.filter { $0.status == .inProgress }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var upNextVisual: [Item] {
        items.filter { $0.status == .want && $0.kind.isVisual }
    }

    private var readingList: [Item] {
        items.filter { $0.status != .done && $0.status != .dropped && ($0.kind == .paper || $0.kind == .article) }
    }

    private var recentlyFinished: [Item] {
        items.filter { $0.status == .done }.sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    private var finishedThisYear: [Item] {
        let year = Calendar.current.component(.year, from: .now)
        return items.filter { item in
            guard item.status == .done, let f = item.finishedAt else { return false }
            return Calendar.current.component(.year, from: f) == year
        }
    }

    /// Stable "pick of the day" from the up-next pile.
    private var dailyPick: Item? {
        let pool = items.filter { $0.status == .want }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return pool[day % pool.count]
    }

    /// Something finished over a month ago, favourites first.
    private var memory: Item? {
        let monthAgo = Date.now.addingTimeInterval(-30 * 86_400)
        let pool = items.filter { $0.status == .done && ($0.finishedAt ?? .now) < monthAgo }
            .sorted { ($0.isFavorite ? 1 : 0, $0.rating) > ($1.isFavorite ? 1 : 0, $1.rating) }
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return pool[day % min(pool.count, 5)]
    }
}

struct SectionHeader: View {
    let title: String
    var note: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.sectionTitle).foregroundStyle(Color.ink)
            if let note {
                Text(note).font(.system(size: 12)).foregroundStyle(Color.inkFaint)
            }
            Spacer()
            if let action {
                Button("See All", action: action)
                    .buttonStyle(.pillCompact)
            }
        }
    }
}

private struct ContinueCard: View {
    let item: Item
    @Environment(Router.self) private var router
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            CoverView(item: item, cornerRadius: 4)
                .frame(width: 52)
                .paperShadow()
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text(item.byline)
                    .font(.cardDetail)
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ProgressLine(value: item.progress)
                    Text("\(Int(item.progress * 100))%")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                }
            }
        }
        .padding(12)
        .frame(width: 300, height: 102)
        .background(hovering ? Color.paperRaised : Color.paperRaised.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline))
        .onHover { inside in withAnimation(.lift) { hovering = inside } }
        .onTapGesture { withAnimation(.shelf) { router.open(item) } }
        .contextMenu { ItemContextMenu(item: item) }
    }
}

/// A hairline of progress in the one accent color.
struct ProgressLine: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.washStrong)
                Capsule().fill(Color.glow).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

/// First-run: three gentle ways in.
private struct WelcomeView: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                tip(symbol: "keyboard", title: "Capture from anywhere",
                    body: "Press \(HotKeyPreset.current.title) in any app. If you’re in a browser, the page is already waiting for you.")
                tip(symbol: "puzzlepiece.extension", title: "Add the browser extension",
                    body: "One click — or ⌥⇧S — saves the page you’re on. Pair it in Settings.")
                tip(symbol: "text.cursor", title: "Or right here",
                    body: "Press ⌘N and type a title. Books, films, papers and places come back with covers.")
            }
            Button("Add Something", systemImage: "plus") { router.showingCapture = true }
                .buttonStyle(.pillPrimary)
        }
    }

    private func tip(symbol: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.inkSoft)
                .frame(height: 24)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
            Text(body).font(.system(size: 12.5)).foregroundStyle(Color.inkSoft).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline))
    }
}
