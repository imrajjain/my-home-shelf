import Foundation
import SwiftData
import Observation
import ShelfCore

/// Keeps the Books shelf following a Goodreads profile, one way
/// (Goodreads → Shelf). Goodreads has no write API, so the other direction
/// is a button that opens the book there; the next sync links it up.
///
/// Changes on Goodreads win, but only when they *are* changes: status and
/// rating are compared with what Goodreads said last time, so an edit made
/// in Shelf isn't overwritten every twenty minutes.
@MainActor
@Observable
final class GoodreadsSync {
    static let shared = GoodreadsSync()

    enum State: Equatable {
        case idle
        case syncing
        case synced(count: Int, at: Date)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var timer: Timer?
    private var lastAttempt: Date?
    private static let interval: TimeInterval = 20 * 60

    // Bookkeeping kept on each item.
    private enum Key {
        static let id = "goodreadsID"
        static let status = "goodreadsStatus"      // what Goodreads said last time
        static let rating = "goodreadsRating"
        static let added = "goodreadsAdded"        // "1" when the sync created it
        static let shelves = "goodreadsShelves"    // your Goodreads shelves last time, as tags
    }

    var source: GoodreadsFeed.Source? {
        UserDefaults.standard.string(forKey: SettingsKey.goodreads).flatMap(GoodreadsFeed.source(from:))
    }

    /// Call on launch and whenever the profile setting changes.
    func start() {
        timer?.invalidate()
        guard source != nil else { state = .idle; return }
        if let last = UserDefaults.standard.object(forKey: SettingsKey.goodreadsLastSync) as? Date {
            state = .synced(count: UserDefaults.standard.integer(forKey: SettingsKey.goodreadsCount), at: last)
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in await GoodreadsSync.shared.sync() }
        }
        Task { await sync() }
    }

    /// When you come back to Shelf: check now unless we just did.
    func syncIfStale(olderThan interval: TimeInterval = 120) {
        guard source != nil, state != .syncing,
              Date().timeIntervalSince(lastAttempt ?? .distantPast) > interval else { return }
        Task { await sync() }
    }

    func sync() async {
        guard let source, state != .syncing else { return }
        lastAttempt = .now
        state = .syncing
        do {
            // Debug runs can read a saved feed instead of the network.
            let books: [GoodreadsBook]
            if let fixture = ProcessInfo.processInfo.environment["SHELF_GOODREADS_FIXTURE"] {
                books = GoodreadsFeed.parse(try Data(contentsOf: URL(filePath: fixture)))
            } else {
                books = try await GoodreadsFeed.fetchAll(source)
            }
            let added = apply(books)
            let now = Date()
            UserDefaults.standard.set(now, forKey: SettingsKey.goodreadsLastSync)
            UserDefaults.standard.set(books.count, forKey: SettingsKey.goodreadsCount)
            state = .synced(count: books.count, at: now)
            await cacheCovers(for: added)
        } catch {
            state = .failed("Couldn’t reach Goodreads. Shelf will try again shortly.")
        }
    }

    // MARK: - Applying

    /// Returns the items that need cover art.
    private func apply(_ books: [GoodreadsBook]) -> [Item] {
        let context = Persistence.context
        let items = (try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        // Known links first: an ID we stored, or one read exactly from a
        // goodreads.com/book/show/<id> link the user saved.
        var byID: [String: Item] = [:]
        for item in items {
            if let id = item.extra[Key.id] ?? Self.bookID(in: item.urlString) { byID[id] = item }
        }
        var claimed = Set(byID.values.map(\.id))
        var needsCover: [Item] = []

        for book in books {
            let item = byID[book.bookID]
                ?? match(book, in: items.filter { !claimed.contains($0.id) })
                ?? create(book, in: context)
            byID[book.bookID] = item
            claimed.insert(item.id)
            update(item, from: book)
            if item.imageData == nil { needsCover.append(item) }
        }

        // Gone from Goodreads → gone from Shelf, but only books the sync
        // brought in, and never on an empty (possibly failed) fetch. A book
        // you've made your own here (notes, a favorite, progress, your own
        // status or rating) stays, just no longer linked to Goodreads.
        if !books.isEmpty {
            let current = Set(books.map(\.bookID))
            for item in items where item.extra[Key.added] == "1" {
                guard let id = item.extra[Key.id], !current.contains(id) else { continue }
                if hasYourTouch(item) {
                    for key in [Key.id, Key.added, Key.status, Key.rating, Key.shelves] { item.extra[key] = nil }
                } else {
                    item.deletedAt = .now
                    item.touch()
                }
            }
        }
        try? context.save()
        return needsCover
    }

    /// Something only you could have put there.
    private func hasYourTouch(_ item: Item) -> Bool {
        !item.notes.isEmpty
            || item.isFavorite
            || (item.status == .inProgress && item.progress > 0)
            || item.extra[Key.status] != item.status.rawValue
            || (item.rating > 0 && item.extra[Key.rating] != String(item.rating))
    }

    /// want < reading < read (dropped counts as a decision, like read).
    private static func rank(_ status: ItemStatus) -> Int {
        switch status {
        case .want: 0
        case .inProgress: 1
        case .done, .dropped: 2
        }
    }

    /// A book already on the shelf with the same title and author.
    private func match(_ book: GoodreadsBook, in items: [Item]) -> Item? {
        items.first { item in
            item.kind == .book && item.extra[Key.id] == nil
                && MetadataService.sameWords(item.title, book.title)
                && (book.author == nil || item.creator == nil || MetadataService.sameWords(item.creator ?? "", book.author ?? ""))
        }
    }

    /// "…/book/show/18373.Flowers_for_Algernon" → "18373" (exactly; a
    /// substring test would let book 1837 claim it).
    static func bookID(in url: String?) -> String? {
        guard let url, url.contains("goodreads.com"),
              let r = url.range(of: #"/book/show/\d+"#, options: .regularExpression) else { return nil }
        return String(url[r].dropFirst("/book/show/".count))
    }

    private func create(_ book: GoodreadsBook, in context: ModelContext) -> Item {
        let item = Item(kind: .book, status: book.status, title: book.title)
        item.apply(book.metadata, overwriteTitle: true)
        if let added = book.dateAdded { item.createdAt = added }
        item.extra[Key.added] = "1"
        context.insert(item)
        return item
    }

    private func update(_ item: Item, from book: GoodreadsBook) {
        if item.extra[Key.id] != book.bookID { item.extra[Key.id] = book.bookID }
        if item.urlString == nil { item.urlString = book.url.absoluteString }
        // Fill gaps only, never overwrite — and leave untouched items alone
        // so "recently touched" keeps meaning something.
        if item.creator == nil || item.year == nil || item.summary == nil || item.imageURLString == nil {
            item.apply(book.metadata)
        }

        // The cover of *your* edition on Goodreads wins over a catalogue's
        // guess (and follows you if you switch editions there).
        if let cover = book.imageURL?.absoluteString, item.imageURLString != cover {
            item.imageURLString = cover
            item.imageData = nil
        }

        // Linking a book you added yourself: your status stays when it's
        // further along than Goodreads', and your rating when you set one.
        let firstLink = item.extra[Key.status] == nil && item.extra[Key.added] != "1"

        let status = book.status.rawValue
        var markedBySync = false
        if item.extra[Key.status] != status {
            if !firstLink || Self.rank(book.status) >= Self.rank(item.status) {
                markedBySync = item.status != book.status
                item.status = book.status
            }
            item.extra[Key.status] = status
        }

        // The finished date is Goodreads' "date read" whenever it has one;
        // when it has none, a book the sync marked read gets no date rather
        // than the moment the sync happened to run. Marking a book read
        // stamps both dates with "now", so a start date equal to that stamp
        // goes too.
        if book.status == .done, item.status == .done,
           book.readAt != nil || item.extra[Key.added] == "1" || markedBySync || item.finishedAt == nil,
           item.finishedAt != book.readAt {
            if item.startedAt == item.finishedAt { item.startedAt = nil }
            item.finishedAt = book.readAt
        }
        let rating = String(book.rating)
        if item.extra[Key.rating] != rating {
            if book.rating > 0 && !(firstLink && item.rating > 0) { item.rating = book.rating }
            item.extra[Key.rating] = rating
        }
        // Your own Goodreads shelves become tags and follow Goodreads both
        // ways: a shelf you remove there drops its tag here. Tags you added
        // in Shelf are never touched.
        let shelves = book.customShelves
        let previous = item.extra[Key.shelves].map { Set($0.split(separator: ",").map(String.init)) } ?? []
        var tags = item.tags.filter { !previous.contains($0) || shelves.contains($0) }
        tags += shelves.filter { !tags.contains($0) }
        if tags != item.tags { item.tags = tags }
        let joined = shelves.joined(separator: ",")
        if item.extra[Key.shelves] != joined { item.extra[Key.shelves] = joined }
    }

    /// One at a time: a first sync can bring in hundreds of covers.
    private func cacheCovers(for items: [Item]) async {
        for item in items where item.imageData == nil {
            guard let url = item.imageURL, let data = await ImageCache.download(url) else { continue }
            item.imageData = data
        }
        try? Persistence.context.save()
    }
}
