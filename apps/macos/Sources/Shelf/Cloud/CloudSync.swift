import Foundation
import SwiftData
import Observation
import ShelfCore

/// Backs the shelf up to Shelf's cloud and brings changes from your other
/// Macs back. The local store stays the source of truth for the app; the
/// newest edit wins per item, and deletions travel as tombstones.
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    enum Status: Equatable { case idle, syncing, synced(Date), failed(String) }
    private(set) var status: Status = .idle

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var pending: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    /// Server time of the last change we've received.
    private var cursor: Double {
        get { defaults.double(forKey: "cloud.cursor") }
        set { defaults.set(newValue, forKey: "cloud.cursor") }
    }
    /// Local edits after this moment haven't been sent yet.
    private var sentUpTo: Date {
        get { defaults.object(forKey: "cloud.sentUpTo") as? Date ?? .distantPast }
        set { defaults.set(newValue, forKey: "cloud.sentUpTo") }
    }

    private init() {}

    /// Called once signed in: sync now, after edits, and every ten minutes.
    func start() {
        guard timer == nil else { soon(); return }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in await CloudSync.shared.run() }
        }
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            Task { @MainActor in CloudSync.shared.soon() }
        }
        Task { await run() }
    }

    /// A sync a few seconds from now, so a burst of edits goes up together.
    func soon() {
        guard Account.shared.isSignedIn else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await run()
        }
    }

    /// Sends everything again (after a shelf's sharing default changes).
    func resendAll() {
        sentUpTo = .distantPast
        soon()
    }

    /// Forget sync progress (on sign-out), so the next account starts clean.
    func reset() {
        timer?.invalidate(); timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        pending?.cancel()
        defaults.removeObject(forKey: "cloud.cursor")
        defaults.removeObject(forKey: "cloud.sentUpTo")
        status = .idle
    }

    func run() async {
        guard Account.shared.isSignedIn, status != .syncing else { return }
        status = .syncing
        let context = Persistence.context
        let startedAt = Date()
        do {
            let since = sentUpTo
            let all = try context.fetch(FetchDescriptor<Item>())
            let outgoing = all.filter { $0.updatedAt > since }.map {
                CloudChange(record: $0.record, visibility: Sharing.visibility(of: $0))
            }
            // At most 500 changes per call; the first call also brings remote changes.
            var batches = stride(from: 0, to: outgoing.count, by: 500).map { Array(outgoing[$0..<min($0 + 500, outgoing.count)]) }
            if batches.isEmpty { batches = [[]] }
            var incoming: [CloudChange] = []
            var newCursor = cursor
            for batch in batches {
                let result = try await CloudAPI.sync(since: cursor, changes: batch)
                incoming += result.changes
                newCursor = max(newCursor, result.cursor)
            }
            apply(incoming, to: all, in: context)
            try context.save()
            cursor = newCursor
            sentUpTo = startedAt
            status = .synced(.now)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func apply(_ changes: [CloudChange], to items: [Item], in context: ModelContext) {
        var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for change in changes {
            let record = change.record
            if let local = byID[record.id] {
                guard record.updatedAt > local.updatedAt else { continue }
                let cover = local.imageData
                let sameArt = local.imageURLString == record.imageURL?.absoluteString
                local.update(from: record)
                if sameArt { local.imageData = cover }
            } else if record.deletedAt == nil {
                let item = Item(record: record)
                context.insert(item)
                byID[item.id] = item
                if let url = record.imageURL {
                    Task { if let data = await ImageCache.download(url) { item.imageData = data } }
                }
            }
        }
    }
}
