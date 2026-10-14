import Foundation

/// Where a snippet came from: a web page, a document, or just an app.
public struct SnippetSource: Codable, Hashable, Sendable {
    public var url: URL?
    /// Page or window title.
    public var title: String?
    /// The app it was copied from ("Safari", "Preview").
    public var app: String?

    public init(url: URL? = nil, title: String? = nil, app: String? = nil) {
        self.url = url; self.title = title; self.app = app
    }

    public var isEmpty: Bool {
        url == nil && (title ?? "").trimmed.isEmpty && (app ?? "").trimmed.isEmpty
    }

    /// "nytimes.com", "Notes.pdf" or "Preview": the shortest honest label.
    public var label: String? {
        if let url {
            if url.isFileURL { return url.lastPathComponent }
            if let host = url.host?.lowercased() { return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
        }
        return title?.nilIfEmpty ?? app?.nilIfEmpty
    }
}

/// The portable shape of a note. A note with a `quote` is a snippet:
/// text you selected somewhere, kept with where it came from.
public struct NoteRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    /// The selected text, verbatim, for snippets.
    public var quote: String?
    public var source: SnippetSource?
    public var tags: [String]
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), title: String = "", body: String = "", quote: String? = nil,
        source: SnippetSource? = nil, tags: [String] = [], isPinned: Bool = false,
        createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil
    ) {
        self.id = id; self.title = title; self.body = body; self.quote = quote
        self.source = source; self.tags = tags; self.isPinned = isPinned
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

/// The portable shape of a reminder, optionally about something on the shelf.
public struct ReminderRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var dueAt: Date?
    public var isDone: Bool
    public var completedAt: Date?
    /// The shelf item this is about, if any.
    public var itemID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), title: String, notes: String = "", dueAt: Date? = nil, isDone: Bool = false,
        completedAt: Date? = nil, itemID: UUID? = nil, createdAt: Date = .now, updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id; self.title = title; self.notes = notes; self.dueAt = dueAt; self.isDone = isDone
        self.completedAt = completedAt; self.itemID = itemID
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

/// How the Reminders page groups things.
public enum ReminderBucket: String, CaseIterable, Sendable {
    case overdue, today, upcoming, someday, done

    public var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .someday: "Someday"
        case .done: "Completed"
        }
    }

    public static func bucket(dueAt: Date?, isDone: Bool, now: Date = .now, calendar: Calendar = .current) -> ReminderBucket {
        if isDone { return .done }
        guard let dueAt else { return .someday }
        if dueAt < now { return .overdue }
        return calendar.isDate(dueAt, inSameDayAs: now) ? .today : .upcoming
    }
}
