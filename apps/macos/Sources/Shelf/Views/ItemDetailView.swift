import SwiftUI
import MapKit
import ShelfCore

/// Everything about one thing: big cover, how you feel about it, notes.
/// Edits save as you go.
struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(Router.self) private var router
    @State private var celebrate = 0
    @State private var editingTitle = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                statusSection
                if item.status == .inProgress { progressSection }
                ratingRow
                if let summary = item.summary, !summary.isEmpty { summarySection(summary) }
                if item.kind == .place, let coordinate { mapSection(coordinate) }
                notesSection
                tagsSection
                factsSection
                actions
            }
            .padding(22)
        }
        .background(Color.paper)
        .onChange(of: item.rating) { _, _ in item.touch() }
        .onChange(of: item.notes) { _, _ in item.touch() }
        .onChange(of: item.tags) { _, _ in item.touch() }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .center, spacing: 16) {
            CoverView(item: item, cornerRadius: 10)
                .frame(maxWidth: item.kind.coverAspect >= 1 ? 230 : 190)
                .paperShadow(lifted: true)
                .overlay(alignment: .topTrailing) {
                    if item.status == .done {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, item.kind.tint)
                            .symbolEffect(.bounce, value: celebrate)
                            .offset(x: 10, y: -10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity)
                .onTapGesture(count: 2) { if let url = item.url { NSWorkspace.shared.open(url) } }

            VStack(alignment: .center, spacing: 6) {
                KindBadge(kind: item.kind)
                if editingTitle {
                    TextField("Title", text: $item.title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.display(22))
                        .multilineTextAlignment(.center)
                        .onSubmit { editingTitle = false; item.touch() }
                } else {
                    Text(item.title)
                        .font(.display(22))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .onTapGesture(count: 2) { editingTitle = true }
                }
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.display(14, weight: .regular).italic())
                        .foregroundStyle(Color.inkSoft)
                        .multilineTextAlignment(.center)
                }
                if !item.byline.isEmpty {
                    Text(item.byline)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.inkSoft)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Status & progress

    private var statusSection: some View {
        HStack {
            Spacer()
            StatusPicker(kind: item.kind, status: Binding(
                get: { item.status },
                set: { newValue in
                    withAnimation(.shelf) { item.status = newValue }
                    if newValue == .done { celebrate += 1 }
                }
            ))
            Spacer()
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Eyebrow("Progress")
                Spacer()
                Text("\(Int(item.progress * 100))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.inkSoft)
            }
            Slider(value: Binding(get: { item.progress }, set: { item.progress = $0; item.touch() }), in: 0...1)
                .tint(item.kind.tint)
                .controlSize(.small)
        }
    }

    private var ratingRow: some View {
        HStack {
            RatingView(rating: $item.rating, size: 17)
            Spacer()
            Button {
                withAnimation(.lift) { item.isFavorite.toggle(); item.touch() }
                Haptics.tap()
            } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(item.isFavorite ? Color(hex: 0xD9536F) : Color.inkFaint)
                    .symbolEffect(.bounce, value: item.isFavorite)
            }
            .buttonStyle(.plain)
            .help(item.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 2)
    }

    // MARK: Content

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(item.kind == .paper ? "Abstract" : "About")
            ExpandableText(text: summary)
        }
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = item.extra["latitude"].flatMap(Double.init),
              let lon = item.extra["longitude"].flatMap(Double.init) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func mapSection(_ c: CLLocationCoordinate2D) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 1500, longitudinalMeters: 1500))) {
            Marker(item.title, coordinate: c).tint(item.kind.tint)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Your notes")
            TextEditor(text: $item.notes)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90)
                .padding(8)
                .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if item.notes.isEmpty {
                        Text("What stayed with you? Who recommended it?")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.inkFaint)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Tags")
            TagEditor(tags: $item.tags)
        }
    }

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Details")
            VStack(spacing: 0) {
                fact("Shelf", item.kind.pluralTitle)
                fact("Added", item.createdAt.formatted(date: .abbreviated, time: .omitted))
                if let started = item.startedAt { fact("Started", started.formatted(date: .abbreviated, time: .omitted)) }
                if let finished = item.finishedAt { fact("Finished", finished.formatted(date: .abbreviated, time: .omitted)) }
                if let pages = item.extra["pages"] { fact("Pages", pages) }
                if let runtime = item.extra["runtime"] { fact("Runtime", runtime) }
                if let venue = item.extra["venue"] { fact("Venue", venue) }
                if let doi = item.extra["doi"] { fact("DOI", doi) }
                if let community = item.extra["communityRating"] { fact("Community", community) }
                if let provider = item.provider { fact("Source", provider) }
            }
            .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12)).foregroundStyle(Color.inkFaint)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ink)
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 12) }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if let url = item.url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(openLabel, systemImage: "arrow.up.right")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(item.kind.tint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if let pdf = item.extra["pdf"].flatMap(URL.init(string:)) {
                Button { NSWorkspace.shared.open(pdf) } label: {
                    Label("PDF", systemImage: "doc.richtext")
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.paperSunken, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Menu {
                Button("Refresh Details") { CaptureCoordinator.shared.refresh(item) }
                Button("Edit Title") { editingTitle = true }
                Menu("Move to Shelf") {
                    ForEach(ItemKind.allCases) { kind in
                        Button(kind.pluralTitle) { withAnimation(.shelf) { item.kind = kind } }
                    }
                }
                Divider()
                Button("Remove from Shelf", role: .destructive) { ItemActions.delete(item, router: router) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 16))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.top, 4)
    }

    private var openLabel: String {
        if let host = item.host {
            if host.contains("goodreads") { return "Goodreads" }
            if host.contains("letterboxd") { return "Letterboxd" }
            if host.contains("arxiv") { return "arXiv" }
            if host.contains("youtube") || host == "youtu.be" { return "YouTube" }
            if host.contains("wikipedia") { return "Wikipedia" }
        }
        switch item.kind {
        case .paper, .article: return "Read"
        case .film, .show, .video: return "Watch"
        case .podcast, .music: return "Listen"
        case .place: return "Maps"
        default: return "Open"
        }
    }
}

/// Long text that opens up on request.
private struct ExpandableText: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(Color.ink.opacity(0.85))
                .lineLimit(expanded ? nil : 6)
                .textSelection(.enabled)
            if text.count > 320 {
                Button(expanded ? "Less" : "More") { withAnimation(.shelf) { expanded.toggle() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkSoft)
            }
        }
    }
}
