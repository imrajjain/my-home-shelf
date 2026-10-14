import SwiftUI
import ShelfCore

/// One field to capture anything: paste a link, or type a few words and
/// pick from what comes back. Used by the floating panel and ⌘N.
struct CaptureView: View {
    enum Presentation { case panel, sheet }

    var presentation: Presentation = .panel
    var prefill: CaptureRequest?
    var frontmostApp: NSRunningApplication?
    /// Where the add starts: the shelf (and status) the user is looking at.
    var initialKind: ItemKind?
    var initialStatus: ItemStatus?
    var onClose: () -> Void

    @State private var model = CaptureModel()
    @FocusState private var fieldFocused: Bool
    @State private var showNote = false

    var body: some View {
        ZStack {
            if let added = model.added {
                AddedConfirmation(item: added)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                content.transition(.opacity)
            }
        }
        .frame(width: 640, height: 460)
        .background { background }
        .clipShape(RoundedRectangle(cornerRadius: presentation == .panel ? 22 : 0, style: .continuous))
        .overlay {
            if presentation == .panel {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            }
        }
        .task {
            if let initialKind { model.kind = initialKind }
            if let initialStatus { model.status = initialStatus }
            model.loadContext(prefill: prefill, frontmostApp: frontmostApp)
            try? await Task.sleep(for: .milliseconds(40))
            fieldFocused = true
        }
        .onChange(of: model.added) { _, item in
            guard item != nil else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(850))
                onClose()
            }
        }
    }

    @ViewBuilder private var background: some View {
        if presentation == .panel {
            ZStack {
                VisualEffectBackground(material: .popover)
                Color.paper.opacity(0.72)
            }
        } else {
            Color.paper
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            field
            kindStrip
            Rectangle().fill(Color.hairline).frame(height: 1)
            resultsList
            if showNote { noteField }
            footer
        }
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isLink ? "link" : "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(model.isLink ? model.effectiveKind.tint : Color.inkFaint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22)
            TextField("", text: $model.query, prompt: Text(prompt).foregroundStyle(Color.inkFaint))
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(Color.ink)
                .focused($fieldFocused)
                .onSubmit { model.commit() }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.tab) { model.cycleKind(1); return .handled }
                .onKeyPress(.escape) { onClose(); return .handled }
            if model.isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var prompt: String {
        "Search \(model.kind.pluralTitle.lowercased()), or paste a link…"
    }

    private var kindStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ItemKind.allCases) { kind in
                    let selected = kind == model.kind
                    Button {
                        withAnimation(.shelf) { model.kind = kind }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: kind.symbol).font(.system(size: 10.5, weight: .semibold))
                            Text(kind.pluralTitle.components(separatedBy: " ").first ?? kind.pluralTitle)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                        }
                        .foregroundStyle(selected ? Color.white : Color.inkSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selected ? kind.tint : Color.paperSunken.opacity(0.8), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    let rows = model.rows
                    if rows.isEmpty {
                        hints
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        CaptureRowView(row: row, model: model, isHighlighted: index == model.highlighted)
                            .id(row.id)
                            .onTapGesture(count: 2) { model.highlighted = index; model.commit() }
                            .onTapGesture { withAnimation(.lift) { model.highlighted = index } }
                    }
                }
                .padding(10)
            }
            .onChange(of: model.highlighted) { _, index in
                let rows = model.rows
                guard rows.indices.contains(index) else { return }
                withAnimation(.lift) { proxy.scrollTo(rows[index].id, anchor: .center) }
            }
        }
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Try")
            hintRow("text.magnifyingglass", "Type a title — “The Remains of the Day”, “Past Lives”")
            hintRow("link", "Paste a link from Goodreads, Letterboxd, arXiv, YouTube, anywhere")
            hintRow("sparkle.magnifyingglass", "Or just a question you can’t stop wondering about")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
    }

    private func hintRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.inkFaint).frame(width: 18)
            Text(text).font(.system(size: 13)).foregroundStyle(Color.inkSoft)
        }
    }

    private var noteField: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.quote").foregroundStyle(Color.inkFaint)
            TextField("Why does this belong on your shelf?", text: $model.note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.paperSunken.opacity(0.5))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            StatusPicker(kind: model.effectiveKind, status: $model.status)
            Button {
                withAnimation(.shelf) { showNote.toggle() }
            } label: {
                Image(systemName: showNote ? "text.quote" : "plus.bubble")
                    .foregroundStyle(showNote ? model.effectiveKind.tint : Color.inkSoft)
            }
            .buttonStyle(.plain)
            .help("Add a note")
            Spacer()
            HStack(spacing: 5) {
                KeyCap("↩"); Text("add").font(.system(size: 11)).foregroundStyle(Color.inkFaint)
                KeyCap("⌘↩"); Text("finished").font(.system(size: 11)).foregroundStyle(Color.inkFaint)
                KeyCap("⇥"); Text("shelf").font(.system(size: 11)).foregroundStyle(Color.inkFaint)
            }
            // Invisible buttons carry the extra shortcuts.
            Button("") { model.commit(status: .done) }
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
            Button("") { onClose() }
                .keyboardShortcut(.cancelAction)
                .opacity(0).frame(width: 0, height: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.paperSunken.opacity(0.35))
    }
}

/// A single result line: cover, title, byline, source.
private struct CaptureRowView: View {
    let row: CaptureModel.Row
    let model: CaptureModel
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            thumbnail
                .frame(width: 44, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow { Eyebrow(eyebrow, color: tint) }
                Text(title)
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let provider {
                Text(provider)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
            }
            if isHighlighted {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHighlighted ? tint.opacity(0.12) : Color.clear)
        }
        .contentShape(Rectangle())
    }

    private var metadata: Metadata? {
        switch row {
        case .suggestion(_, let url, _), .link(let url): model.linkPreviews[url]
        case .result(let m): m
        case .plain: nil
        }
    }

    private var kind: ItemKind {
        switch row {
        case .suggestion(_, let url, _), .link(let url): metadata?.kind ?? LinkClassifier.kind(for: url)
        case .result(let m): m.kind
        case .plain: model.kind
        }
    }

    private var tint: Color { kind.tint }

    private var title: String {
        switch row {
        case .suggestion(_, let url, let t): metadata?.title ?? t ?? url.absoluteString
        case .link(let url): metadata?.title ?? url.absoluteString
        case .result(let m): m.title
        case .plain(let text): "“\(text)”"
        }
    }

    private var eyebrow: String? {
        switch row {
        case .suggestion(let source, _, _): "From \(source) · \(kind.title)"
        case .link: metadata == nil ? "Reading link…" : kind.title
        case .result: nil
        case .plain: "Add as \(model.kind.title.lowercased())"
        }
    }

    private var detail: String? {
        switch row {
        case .plain:
            return model.kind == .curiosity ? "We’ll look it up on Wikipedia" : "Just the title — fill in the rest later"
        default:
            if let m = metadata {
                let byline = m.byline
                return byline.isEmpty ? (m.subtitle ?? m.url?.host) : byline
            }
            if case .suggestion(_, let url, _) = row { return url.host }
            return nil
        }
    }

    private var provider: String? {
        if case .result(let m) = row { return m.provider }
        return nil
    }

    @ViewBuilder private var thumbnail: some View {
        if case .plain = row {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(model.kind.tint.opacity(0.14))
                .overlay(Image(systemName: "plus").foregroundStyle(model.kind.tint))
        } else if let m = metadata {
            CoverView(metadata: m, cornerRadius: 5)
                .frame(maxWidth: 44, maxHeight: 56)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.paperSunken)
                .overlay(ProgressView().controlSize(.small))
        }
    }
}

/// The little moment after adding: cover drops onto the shelf.
private struct AddedConfirmation: View {
    let item: Item
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            CoverView(item: item, cornerRadius: 8)
                .frame(height: 170)
                .paperShadow(lifted: true)
                .scaleEffect(appeared ? 1 : 0.85)
                .offset(y: appeared ? 0 : -16)
            VStack(spacing: 6) {
                Label("On your shelf", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
                    .symbolEffect(.bounce, value: appeared)
                Text(item.title)
                    .font(.display(20))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("\(item.kind.pluralTitle) · \(item.statusLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { appeared = true } }
    }
}

/// Real behind-window blur (SwiftUI materials blur within the window only).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
