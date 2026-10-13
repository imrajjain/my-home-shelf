import AppKit
import SwiftUI
import Observation
import ShelfCore

/// State behind the capture field: debounced search, link previews,
/// keyboard highlight, and committing the chosen row.
@MainActor
@Observable
final class CaptureModel {
    enum Row: Identifiable, Equatable {
        case suggestion(source: String, url: URL, title: String?)
        case link(URL)
        case result(Metadata)
        case plain(String)

        var id: String {
            switch self {
            case .suggestion(_, let url, _): "s:\(url.absoluteString)"
            case .link(let url): "l:\(url.absoluteString)"
            case .result(let m): "r:\(m.id)"
            case .plain(let text): "p:\(text)"
            }
        }
    }

    var query = "" { didSet { if query != oldValue { queryChanged() } } }
    var kind: ItemKind = .book { didSet { if kind != oldValue, !isLink { scheduleSearch(immediately: true) } } }
    var status: ItemStatus = .want
    var note = ""
    var highlighted = 0

    private(set) var results: [Metadata] = []
    private(set) var linkPreviews: [URL: Metadata] = [:]
    private(set) var suggestions: [Row] = []
    private(set) var isSearching = false
    private(set) var added: Item?

    private var searchTask: Task<Void, Never>?
    private var previewTasks: [URL: Task<Void, Never>] = [:]

    var isLink: Bool { LinkClassifier.isBareURL(query) }

    var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return suggestions }
        if isLink, let url = LinkClassifier.firstURL(in: q) { return [.link(url)] }
        return results.map(Row.result) + [.plain(q)]
    }

    /// The kind the highlighted row will be filed under.
    var effectiveKind: ItemKind {
        guard rows.indices.contains(highlighted) else { return kind }
        switch rows[highlighted] {
        case .suggestion(_, let url, _), .link(let url):
            return linkPreviews[url]?.kind ?? LinkClassifier.kind(for: url)
        case .result(let m): return m.kind
        case .plain: return kind
        }
    }

    // MARK: - Context

    /// Offers the current browser tab and any link on the clipboard.
    func loadContext(prefill: CaptureRequest?, frontmostApp: NSRunningApplication?) {
        if let prefill {
            if let url = prefill.url {
                suggestions = [.suggestion(source: "Selected", url: url, title: prefill.title)]
                preview(url)
            } else if let title = prefill.title {
                query = title
            } else if let selection = prefill.selection {
                query = String(selection.prefix(120))
                note = selection
            }
            return
        }
        var rows: [Row] = []
        if let page = FrontmostBrowser.capture(from: frontmostApp) {
            rows.append(.suggestion(source: frontmostApp?.localizedName ?? "Browser", url: page.url, title: page.title))
            preview(page.url)
        }
        if let clip = FrontmostBrowser.clipboardURL(), !rows.contains(where: {
            if case .suggestion(_, let url, _) = $0 { return url == clip } else { return false }
        }) {
            rows.append(.suggestion(source: "Clipboard", url: clip, title: nil))
            preview(clip)
        }
        suggestions = rows
        highlighted = 0
    }

    // MARK: - Search

    private func queryChanged() {
        highlighted = 0
        if isLink, let url = LinkClassifier.firstURL(in: query) {
            searchTask?.cancel()
            isSearching = false
            preview(url)
        } else {
            scheduleSearch()
        }
    }

    private func scheduleSearch(immediately: Bool = false) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        let kind = self.kind
        searchTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(320)) }
            guard !Task.isCancelled else { return }
            let found = await AppSettings.metadata.search(q, kind: kind)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.shelf) {
                self.results = Array(found.prefix(12))
                self.isSearching = false
            }
        }
    }

    private func preview(_ url: URL) {
        guard linkPreviews[url] == nil, previewTasks[url] == nil else { return }
        previewTasks[url] = Task { [weak self] in
            let m = await AppSettings.metadata.resolve(url)
            guard let self else { return }
            withAnimation(.shelf) { self.linkPreviews[url] = m }
            self.previewTasks[url] = nil
        }
    }

    // MARK: - Keyboard

    func move(_ delta: Int) {
        let count = rows.count
        guard count > 0 else { return }
        withAnimation(.lift) { highlighted = (highlighted + delta + count) % count }
    }

    func cycleKind(_ delta: Int = 1) {
        let all = ItemKind.allCases
        let i = all.firstIndex(of: kind) ?? 0
        withAnimation(.shelf) { kind = all[(i + delta + all.count) % all.count] }
    }

    // MARK: - Commit

    /// Adds the highlighted row (or `row`). Returns false if nothing to add.
    @discardableResult
    func commit(_ row: Row? = nil, status overrideStatus: ItemStatus? = nil) -> Bool {
        let rows = self.rows
        guard let row = row ?? (rows.indices.contains(highlighted) ? rows[highlighted] : nil) else { return false }
        let status = overrideStatus ?? self.status
        let note = self.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let coordinator = CaptureCoordinator.shared

        var result: Item?
        switch row {
        case .suggestion(_, let url, let title):
            result = addLink(url, title: title, status: status, note: note, coordinator: coordinator)
        case .link(let url):
            result = addLink(url, title: nil, status: status, note: note, coordinator: coordinator)
        case .result(let m):
            result = coordinator.add(m, status: status, note: note)
        case .plain(let text):
            result = coordinator.add(CaptureRequest(title: text, note: note.isEmpty ? nil : note, kind: kind, status: status))
        }
        guard let result else { return false }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        withAnimation(.shelf) { added = result }
        return true
    }

    private func addLink(_ url: URL, title: String?, status: ItemStatus, note: String, coordinator: CaptureCoordinator) -> Item? {
        if var m = linkPreviews[url] {
            if m.url == nil { m.url = url }
            return coordinator.add(m, status: status, note: note)
        }
        return coordinator.add(CaptureRequest(url: url, title: title, note: note.isEmpty ? nil : note, status: status))
    }
}
