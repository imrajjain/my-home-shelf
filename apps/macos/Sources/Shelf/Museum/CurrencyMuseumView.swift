import SwiftUI
import ShelfCore

/// The World Currencies room: one note at a time on a lit wall, its story
/// beside it, and the rest of the collection in a drawer below.
struct CurrencyMuseumView: View {
    @AppStorage("museum.currencies.current") private var currentID = ""
    @State private var angle: Double = 0

    private let notes = Banknotes.all

    private var current: Banknote? {
        notes.first { $0.id == currentID } ?? notes.first
    }

    var body: some View {
        ZStack {
            Gallery.wall.ignoresSafeArea()
            if let current {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        BanknoteStage(note: current, angle: $angle)
                            .id(current.id)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
                            .overlay(alignment: .bottom) { turnHint }
                        Placard(note: current, showingFront: cos(angle * .pi / 180) >= 0)
                            .frame(width: 330)
                            .padding(.trailing, 24)
                            .padding(.vertical, 24)
                    }
                    drawer(current)
                }
            } else {
                ContentUnavailableView("The collection is on its way", systemImage: "banknote",
                                       description: Text("Shelf couldn’t find its banknote collection."))
            }
        }
        .background(KeyCatcher(left: { step(-1) }, right: { step(1) }, space: { flip() }))
        .onChange(of: currentID) { _, _ in angle = 0 }
    }

    // MARK: Pieces

    private var turnHint: some View {
        HStack(spacing: 14) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous note (←)")
            Button { flip() } label: { Label("Turn Over", systemImage: "rotate.3d") }
                .help("Turn over (Space). You can also drag the note.")
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .help("Next note (→)")
        }
        .buttonStyle(.pillGlass)
        .padding(.bottom, 18)
    }

    private func drawer(_ current: Banknote) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                CurrencyPicker(current: current) { id in
                    if let note = notes.first(where: { $0.id == id }) { select(note) }
                }
                Text("\(notes.count) notes · \(Banknotes.currencies.count) currencies")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Gallery.faint)
            }
            .frame(width: 200, alignment: .leading)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(visible) { note in
                            DrawerNote(note: note, selected: note.id == current.id) { select(note) }
                                .id(note.id)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                .frame(height: 96)
                .onAppear { proxy.scrollTo(current.id, anchor: .center) }
                .onChange(of: currentID) { _, id in withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Gallery.drawer)
        .overlay(alignment: .top) { Rectangle().fill(Gallery.rule).frame(height: 1) }
    }

    /// The current currency's notes, smallest to largest.
    private var visible: [Banknote] {
        guard let key = current?.currencyKey else { return [] }
        return notes.filter { $0.currencyKey == key }
    }

    // MARK: Moving around

    private func select(_ note: Banknote) {
        withAnimation(.smooth(duration: 0.45)) { currentID = note.id }
    }

    /// Through every note in the collection, currency after currency.
    private func step(_ delta: Int) {
        let list = notes
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == current?.id } ?? 0
        select(list[(index + delta + list.count) % list.count])
    }

    private func flip() {
        angle += 180
    }
}

/// Every currency in the collection, by region, with a search field.
private struct CurrencyPicker: View {
    let current: Banknote
    let choose: (Banknote.ID) -> Void
    @State private var open = false
    @State private var query = ""

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Text(current.flag).font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text(current.currency).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Gallery.ink)
                    Text(current.country).font(.system(size: 11)).foregroundStyle(Gallery.soft)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Gallery.faint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Gallery.chip, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Choose a currency")
        .popover(isPresented: $open, arrowEdge: .top) { list }
    }

    private var list: some View {
        VStack(spacing: 0) {
            TextField("Country or currency", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(regions, id: \.self) { region in
                        Section {
                            ForEach(matches.filter { $0.region == region }) { c in row(c) }
                        } header: {
                            Text(region.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .kerning(0.8)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(.bar)
                        }
                    }
                }
            }
        }
        .frame(width: 300, height: 420)
    }

    private func row(_ c: Banknotes.Currency) -> some View {
        Button {
            choose(c.first)
            open = false
        } label: {
            HStack(spacing: 10) {
                Text(c.flag).font(.system(size: 15))
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).font(.system(size: 12.5, weight: .medium))
                    Text(c.country).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer()
                Text("\(c.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(c.id == current.currencyKey ? Color.accentColor.opacity(0.12) : .clear)
        }
        .buttonStyle(.plain)
    }

    private var matches: [Banknotes.Currency] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Banknotes.currencies }
        return Banknotes.currencies.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.country.localizedCaseInsensitiveContains(q)
        }
    }

    private var regions: [String] {
        var seen = Set<String>()
        return matches.map(\.region).filter { seen.insert($0).inserted }
    }
}

/// The museum label: where it's from, then its story.
private struct Placard: View {
    let note: Banknote
    let showingFront: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(note.flag)  \(note.country.uppercased())")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1.2)
                        .foregroundStyle(Gallery.faint)
                    Text(note.denomination)
                        .font(.display(30, weight: .regular))
                        .foregroundStyle(Gallery.ink)
                    Text([note.currency, note.series, note.issued].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Gallery.soft)
                    if let others = note.alsoUsedIn, !others.isEmpty {
                        Text("Also used in \(ListFormatter.localizedString(byJoining: others))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Gallery.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // What's on the side you're looking at.
                VStack(alignment: .leading, spacing: 8) {
                    sideLine("Front", note.front.subject, active: showingFront)
                    sideLine("Back", note.back.subject, active: !showingFront)
                }
                .padding(12)
                .background(Gallery.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                section("History", note.history)
                section("Design", note.design)

                VStack(alignment: .leading, spacing: 4) {
                    Link("Read more on Wikipedia", destination: note.source)
                    Text("Images: \(note.front.credit)")
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Link("Front scan", destination: note.front.page)
                        Link("Back scan", destination: note.back.page)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Gallery.faint)
                .tint(Gallery.soft)
            }
            .padding(22)
        }
        .scrollIndicators(.never)
        .tint(Gallery.ink)
        // Wikipedia links open in Shelf's reader; anything else in the browser.
        .opensWikipediaInReader()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Gallery.rule))
        .animation(.smooth, value: showingFront)
    }

    private func sideLine(_ label: String, _ subject: String?, active: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(active ? Gallery.ink : Gallery.faint)
                .frame(width: 38, alignment: .leading)
            Text(subject.map(WikiLinks.attributed) ?? "—")
                .font(.system(size: 12.5))
                .foregroundStyle(active ? Gallery.ink : Gallery.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Gallery.faint)
            Text(WikiLinks.attributed(text))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(Gallery.ink.opacity(0.88))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DrawerNote: View {
    let note: Banknote
    let selected: Bool
    let select: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(Gallery.chip)
                    if let image {
                        Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
                    }
                }
                .frame(width: 112, height: 56)
                .shadow(color: .black.opacity(hovering || selected ? 0.25 : 0.12), radius: hovering ? 6 : 3, y: 2)
                .offset(y: hovering && !selected ? -2 : 0)
                Text(note.denomination)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Gallery.ink : Gallery.soft)
                    .lineLimit(1)
                    .frame(width: 112, alignment: .leading)
            }
            .padding(6)
            .background(selected ? Gallery.chip : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.lift) { hovering = inside } }
        .help("\(note.country) · \(note.currency)")
        .task { image = await BanknoteImages.shared.image(note.front.thumb ?? note.front.image) }
    }
}

/// Arrow keys and Space for the room, without stealing them from text.
struct KeyCatcher: NSViewRepresentable {
    let left: () -> Void
    let right: () -> Void
    let space: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard view.window?.isKeyWindow == true,
                  !(view.window?.firstResponder is NSTextView) else { return event }
            switch event.keyCode {
            case 123: context.coordinator.parent.left(); return nil
            case 124: context.coordinator.parent.right(); return nil
            case 49: context.coordinator.parent.space(); return nil
            default: return event
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.parent = self }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }

    final class Coordinator {
        var parent: KeyCatcher
        var monitor: Any?
        init(parent: KeyCatcher) { self.parent = parent }
    }
}

/// Placard text keeps Wikipedia's own link markup, `[[Red Fort]]` or
/// `[[Mohandas Karamchand Gandhi|Mahatma Gandhi]]`; here it becomes the
/// label, linked to its article.
enum WikiLinks {
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(text)
        while let open = rest.range(of: "[["), let close = rest.range(of: "]]", range: open.upperBound..<rest.endIndex) {
            result += AttributedString(String(rest[..<open.lowerBound]))
            let inner = rest[open.upperBound..<close.lowerBound]
            let parts = inner.split(separator: "|", maxSplits: 1).map(String.init)
            let target = parts.first ?? ""
            var label = AttributedString(parts.count > 1 ? parts[1] : target)
            let path = target.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            if let url = URL(string: "https://en.wikipedia.org/wiki/" + path) {
                label.link = url
                label.underlineStyle = .single
            }
            result += label
            rest = rest[close.upperBound...]
        }
        result += AttributedString(String(rest))
        return result
    }
}

extension View {
    /// Wikipedia links open in Shelf's reader; anything else in the browser.
    func opensWikipediaInReader() -> some View { modifier(WikipediaReaderLinks()) }
}

private struct WikipediaReaderLinks: ViewModifier {
    @State private var reading: WikiArticle?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard url.host()?.hasSuffix("wikipedia.org") == true, url.pathComponents.count > 2,
                      url.pathComponents[1] == "wiki" else { return .systemAction }
                let title = url.pathComponents[2...].joined(separator: "/").replacingOccurrences(of: "_", with: " ")
                reading = WikiArticle(title: title)
                return .handled
            })
            .sheet(item: $reading) { article in
                WikiReader(article: article) { reading = nil }
            }
    }
}

/// A gallery wall: soft gray by day, near-black by night, lit from above.
enum Gallery {
    static let wallTop = Color(light: NSColor(hex: 0xF4F4F5), dark: NSColor(hex: 0x1C1C1F))
    static let wallBottom = Color(light: NSColor(hex: 0xDCDCDF), dark: NSColor(hex: 0x0B0B0C))
    static let drawer = Color(light: NSColor(hex: 0xEDEDEF, alpha: 0.9), dark: NSColor(hex: 0x111113, alpha: 0.9))
    static let chip = Color(light: NSColor(hex: 0x000000, alpha: 0.06), dark: NSColor(hex: 0xFFFFFF, alpha: 0.08))
    static let rule = Color(light: NSColor(hex: 0x000000, alpha: 0.08), dark: NSColor(hex: 0xFFFFFF, alpha: 0.08))
    static let ink = Color(light: NSColor(hex: 0x1D1D1F), dark: NSColor(hex: 0xF5F5F7))
    static let soft = Color(light: NSColor(hex: 0x55555A), dark: NSColor(hex: 0xB0B0B5))
    static let faint = Color(light: NSColor(hex: 0x86868B), dark: NSColor(hex: 0x7C7C82))

    static var wall: some View {
        ZStack {
            LinearGradient(colors: [wallTop, wallBottom], startPoint: .top, endPoint: .bottom)
            // A spotlight on the note.
            RadialGradient(colors: [Color.white.opacity(0.10), .clear], center: UnitPoint(x: 0.36, y: 0.38),
                           startRadius: 10, endRadius: 520)
                .blendMode(.plusLighter)
        }
    }
}
