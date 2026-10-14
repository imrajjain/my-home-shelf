import SwiftUI
import SwiftData
import ShelfCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            CaptureSettings().tabItem { Label("Capture", systemImage: "sparkles") }
            GoodreadsSettings().tabItem { Label("Goodreads", systemImage: "book") }
            SourceSettings().tabItem { Label("Sources", systemImage: "books.vertical") }
            DataSettings().tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 520)
        .padding(.vertical, 8)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.name) private var name = ""

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $name, prompt: Text(AppSettings.displayName))
                Text("Used for the greeting on Home.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Accent color") { AccentPicker() }
            }
            Section {
                ArtPicker()
            } header: {
                Text("Background art")
            } footer: {
                Text("Drawn in fine lines from the top corner of each page, in your accent color. Shuffle picks a new one each time Shelf opens.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 580)
    }
}

private struct CaptureSettings: View {
    @AppStorage(SettingsKey.hotKey) private var hotKey: HotKeyPreset = .shiftCommandSpace
    @AppStorage(SettingsKey.readsBrowser) private var readsBrowser = true
    @AppStorage(SettingsKey.apiEnabled) private var apiEnabled = true
    @AppStorage(SettingsKey.apiToken) private var token = ""
    @State private var copied = false

    var body: some View {
        Form {
            Section("Quick capture") {
                Picker("Shortcut", selection: $hotKey) {
                    ForEach(HotKeyPreset.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Offer the current browser tab", isOn: $readsBrowser)
                Text("Works with Safari, Chrome, Arc, Brave, Edge and Vivaldi. macOS asks once per browser.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Browser extension") {
                Toggle("Allow the extension to add items", isOn: $apiEnabled)
                LabeledContent("Pairing code") {
                    HStack {
                        Text(token.isEmpty ? AppSettings.apiToken : token)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AppSettings.apiToken, forType: .string)
                            copied = true
                        }
                    }
                }
                HStack {
                    Text("Paste this into the extension’s settings once. Listening on 127.0.0.1:\(String(LocalAPI.defaultPort)).")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("New Code") { AppSettings.regenerateToken(); token = AppSettings.apiToken; copied = false }
                        .controlSize(.small)
                }
            }
            Section("Services menu") {
                Text("Select text or a link in any app, then right-click → Services → Add to Shelf.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 440)
        .onAppear { if token.isEmpty { token = AppSettings.apiToken } }
    }
}

private struct SourceSettings: View {
    @AppStorage(SettingsKey.tmdbAPIKey) private var tmdbKey = ""

    var body: some View {
        Form {
            Section("Built in — no setup") {
                source("Open Library & Google Books", "Books, covers, authors, page counts")
                source("Wikipedia & TVmaze", "Films and shows, with posters")
                source("Apple", "Podcasts and albums")
                source("arXiv & Crossref", "Papers, abstracts, authors, DOIs")
                source("Wikipedia", "Curiosities, places, anything")
                source("Apple Maps", "Places you want to go")
                source("Any web page", "Goodreads, Letterboxd, IMDb, Substack… via page metadata")
            }
            Section("Optional") {
                SecureField("TMDB API key", text: $tmdbKey)
                Text("A free key from themoviedb.org gives richer film & TV results.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
    }

    private func source(_ name: String, _ detail: String) -> some View {
        LabeledContent(name) { Text(detail).foregroundStyle(.secondary) }
    }
}

private struct DataSettings: View {
    @Query(filter: #Predicate<Item> { $0.deletedAt == nil }) private var items: [Item]

    var body: some View {
        Form {
            Section("Your shelf") {
                LabeledContent("Items", value: "\(items.count)")
                LabeledContent("Stored at") {
                    Text("~/Library/Application Support/Shelf").font(.caption).textSelection(.enabled)
                }
            }
            Section("Backup") {
                HStack {
                    Button("Export as JSON…") { ArchiveService.exportWithPanel() }
                    Button("Import JSON…") { ArchiveService.importWithPanel() }
                }
                Text("Exports use the same format the upcoming web app will sync, so nothing is ever locked in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

/// A row of swatches; the chosen one gets a ring in its own color.
private struct AccentPicker: View {
    private var appearance: Appearance { .shared }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AccentChoice.allCases) { choice in
                let selected = appearance.accent == choice && !appearance.shuffleAccent
                Button {
                    withAnimation(.snappy(duration: 0.2)) { appearance.choose(choice) }
                } label: {
                    Circle()
                        .fill(choice.color.gradient)
                        .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? choice.color : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(choice.title)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Divider().frame(height: 16).padding(.horizontal, 2)
            // Shuffle: a rainbow swatch with the shuffle glyph.
            Button {
                withAnimation(.snappy(duration: 0.2)) { appearance.shuffleAccent = true }
            } label: {
                Circle()
                    .fill(AngularGradient(colors: AccentChoice.allCases.filter { $0 != .graphite }.map(\.color)
                                            + [AccentChoice.blue.color], center: .center))
                    .overlay(Image(systemName: "shuffle").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.white))
                    .frame(width: 16, height: 16)
                    .padding(3)
                    .overlay(Circle().strokeBorder(appearance.shuffleAccent ? Color.accent : .clear, lineWidth: 2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Shuffle: a new color each time Shelf opens")
            .accessibilityLabel("Shuffle colors")
            .accessibilityAddTraits(appearance.shuffleAccent ? .isSelected : [])
        }
    }
}

private struct GoodreadsSettings: View {
    @AppStorage(SettingsKey.goodreads) private var profile = ""
    @State private var draft = ""
    private var sync: GoodreadsSync { .shared }

    var body: some View {
        Form {
            Section {
                TextField("Profile", text: $draft, prompt: Text("goodreads.com/user/show/12345678"))
                    .onSubmit(connect)
                HStack {
                    status
                    Spacer()
                    if profile.isEmpty {
                        Button("Connect", action: connect).disabled(GoodreadsFeed.source(from: draft) == nil)
                    } else {
                        Button("Disconnect") { profile = ""; draft = ""; sync.start() }
                        Button("Sync Now") { Task { await sync.sync() } }
                            .disabled(sync.state == .syncing)
                    }
                }
            } header: {
                Text("Follow your Goodreads shelves")
            } footer: {
                Text("Want to Read, Currently Reading and Read stay in step with Books here, with your ratings, read dates and own shelves as tags. Shelf checks every 20 minutes. Goodreads doesn’t let apps write back, so books added here get an “Add on Goodreads” button instead. For a private profile, paste the RSS link from the bottom of any of your shelves.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(height: 280)
        .onAppear { draft = profile }
    }

    @ViewBuilder private var status: some View {
        switch sync.state {
        case .idle:
            Text(profile.isEmpty ? "Not connected" : "Waiting to sync").foregroundStyle(.secondary)
        case .syncing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Syncing…") }.foregroundStyle(.secondary)
        case .synced(let count, let at):
            Text("\(count) books · synced \(at.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    private func connect() {
        guard GoodreadsFeed.source(from: draft) != nil else { return }
        profile = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        sync.start()
    }
}

/// A grid of live previews, each drawn exactly as it appears on a page.
private struct ArtPicker: View {
    private var appearance: Appearance { .shared }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
            ForEach(BackdropArt.allCases) { art in
                let selected = appearance.art == art && !appearance.shuffleArt
                Button {
                    withAnimation(.snappy(duration: 0.2)) { appearance.choose(art) }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                            BackdropArtLayer(art: art, intensity: 2.4, reach: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            if art == .none {
                                Image(systemName: "circle.slash").foregroundStyle(.tertiary)
                            }
                        }
                        .frame(height: 70)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? Color.accent : Color.hairline, lineWidth: selected ? 2 : 1)
                        )
                        Text(art.title)
                            .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.accent : Color.inkSoft)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(art.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            shuffleTile
        }
        .padding(.vertical, 4)
    }

    /// Shuffle: today's art, faintly, under the shuffle glyph.
    private var shuffleTile: some View {
        let selected = appearance.shuffleArt
        return Button {
            withAnimation(.snappy(duration: 0.2)) { appearance.shuffleArt = true }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                    BackdropArtLayer(art: appearance.art, intensity: 1.0, reach: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Image(systemName: "shuffle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accent)
                }
                .frame(height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accent : Color.hairline, lineWidth: selected ? 2 : 1)
                )
                Text("Shuffle")
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accent : Color.inkSoft)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("A new style each time Shelf opens")
        .accessibilityLabel("Shuffle styles")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
