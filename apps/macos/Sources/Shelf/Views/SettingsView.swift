import SwiftUI
import SwiftData
import ShelfCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            CaptureSettings().tabItem { Label("Capture", systemImage: "sparkles") }
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
            TextField("Your name", text: $name, prompt: Text(AppSettings.displayName))
            Text("Used for the greeting on Home.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(height: 160)
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
