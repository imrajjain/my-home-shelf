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
            VStack(alignment: .leading, spacing: 44) {
                header
                if items.isEmpty {
                    WelcomeView()
                } else {
                    if !inProgress.isEmpty { continueSection }
                    if !upNextVisual.isEmpty {
                        shelfRow("Up next", subtitle: "Waiting patiently for you", items: upNextVisual, see: .status(.want))
                    }
                    if !readingList.isEmpty { readingListSection }
                    if !finishedThisYear.isEmpty { yearSection }
                    if !recentlyFinished.isEmpty {
                        shelfRow("Recently finished", subtitle: "Still glowing", items: recentlyFinished, see: .status(.done))
                    }
                    if let memory { memorySection(memory) }
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .padding(.bottom, 60)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            Text(greeting)
                .font(.display(42, weight: .medium))
                .foregroundStyle(Color.ink)
            Text(subtitle)
                .font(.display(17, weight: .regular).italic())
                .foregroundStyle(Color.inkSoft)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello, night owl"
        }
        let name = storedName.isEmpty ? AppSettings.displayName : storedName
        return name.isEmpty ? "\(part)." : "\(part), \(name)."
    }

    private var subtitle: String {
        if items.isEmpty { return "Your shelf is empty — let’s fill it with things you love." }
        if let current = inProgress.first {
            return "Shall we pick up \(current.title) where you left off?"
        }
        let waiting = items.tally { $0.status == .want }
        if let pick = dailyPick {
            return "\(waiting) things are waiting. Maybe today is the day for \(pick.title)."
        }
        return "\(items.tally { $0.status == .done }) things read, watched and wondered about. Lovely."
    }

    // MARK: Sections

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Continue", subtitle: "In the middle of things", action: { router.selection = .status(.inProgress) })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(inProgress.prefix(8)) { item in
                        ContinueCard(item: item)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, -4)
        }
    }

    private func shelfRow(_ title: String, subtitle: String, items: [Item], see: SidebarSelection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle, action: { router.selection = see })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 26) {
                    ForEach(items.prefix(16)) { item in
                        ItemCard(item: item, width: item.kind.coverAspect >= 1 ? 160 : 132)
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, -4)
            // The shelf itself: a soft plank under the covers.
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(LinearGradient(colors: [Color.hairline, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 10)
                    .offset(y: -50)
            }
        }
    }

    private var readingListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "On the reading table", subtitle: "Papers, essays and posts you saved",
                          action: { router.selection = .kind(.paper) })
            VStack(spacing: 4) {
                ForEach(readingList.prefix(5)) { item in ItemRow(item: item) }
            }
        }
    }

    private var yearSection: some View {
        let year = Calendar.current.component(.year, from: .now)
        let grouped = Dictionary(grouping: finishedThisYear, by: \.kind)
            .sorted { $0.value.count > $1.value.count }
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Your \(String(year))", subtitle: "\(finishedThisYear.count) things finished so far", action: nil)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(grouped, id: \.key) { kind, list in
                    StatTile(kind: kind, count: list.count)
                }
            }
        }
    }

    private func memorySection(_ item: Item) -> some View {
        HStack(alignment: .center, spacing: 28) {
            CoverView(item: item)
                .frame(width: 120)
                .paperShadow(lifted: true)
                .rotationEffect(.degrees(-3))
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("From the archive", color: item.kind.tint)
                Text("Remember \(item.title)?")
                    .font(.display(24))
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
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
            }
            Spacer()
        }
        .padding(28)
        .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .paperShadow()
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
    let subtitle: String
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.display(22)).foregroundStyle(Color.ink)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Color.inkFaint)
            }
            Spacer()
            if let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text("See all")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkSoft)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ContinueCard: View {
    let item: Item
    @Environment(Router.self) private var router
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            CoverView(item: item, cornerRadius: 6)
                .frame(width: 74)
                .paperShadow()
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(item.statusLabel, color: item.kind.tint)
                Text(item.title)
                    .font(.display(16))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text(item.byline)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .tint(item.kind.tint)
                    Text("\(Int(item.progress * 100))%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                }
            }
        }
        .padding(16)
        .frame(width: 330, height: 150)
        .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .paperShadow(lifted: hovering)
        .scaleEffect(hovering ? 1.015 : 1)
        .onHover { inside in withAnimation(.lift) { hovering = inside } }
        .onTapGesture { withAnimation(.shelf) { router.open(item) } }
        .contextMenu { ItemContextMenu(item: item) }
    }
}

private struct StatTile: View {
    let kind: ItemKind
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(kind.tint)
                .frame(width: 38, height: 38)
                .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.display(24, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
                Text(count == 1 ? kind.title.lowercased() : kind.pluralTitle.lowercased())
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .paperShadow()
    }
}

/// First-run: three gentle ways in.
private struct WelcomeView: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                tip(symbol: "keyboard", tint: ItemKind.book.tint, title: "Capture from anywhere",
                    body: "Press \(HotKeyPreset.current.title) in any app. If you’re in a browser, the page is already waiting for you.")
                tip(symbol: "puzzlepiece.extension", tint: ItemKind.show.tint, title: "Add the browser extension",
                    body: "One click — or ⌥⇧S — saves the page you’re on. Pair it in Settings.")
                tip(symbol: "text.cursor", tint: ItemKind.paper.tint, title: "Or right here",
                    body: "Press ⌘N and type a title. Books, films, papers and places come back with covers.")
            }
            Button {
                router.showingCapture = true
            } label: {
                Label("Add your first thing", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(Color.ink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func tip(symbol: String, tint: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title).font(.display(17)).foregroundStyle(Color.ink)
            Text(body).font(.system(size: 12.5)).foregroundStyle(Color.inkSoft).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .paperShadow()
    }
}
