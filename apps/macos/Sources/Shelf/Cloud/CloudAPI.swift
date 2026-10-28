import Foundation
import ShelfCore

/// Who someone is, as others see them.
struct PublicProfile: Codable, Hashable, Identifiable {
    var username: String
    var displayName: String
    var bio: String?
    var avatarURL: String?
    var id: String { username }
}

/// Your own profile.
struct MyProfile: Codable, Hashable {
    var id: String
    var username: String
    var displayName: String
    var bio: String?
}

/// Someone's shelf, as you're allowed to see it.
struct PersonShelf: Codable {
    var profile: PublicProfile
    var relation: String
    var following: Bool
    /// none, requested (you asked), incoming (they asked), friends.
    var friend: String
    var items: [ItemRecord]
}

struct FeedEntry: Codable, Identifiable {
    var person: PublicProfile
    var item: ItemRecord
    var id: String { person.username + item.id.uuidString }
}

/// One item as it travels to and from the cloud.
struct CloudChange: Codable {
    var record: ItemRecord
    var visibility: Visibility?
}

enum Visibility: String, Codable, CaseIterable, Identifiable {
    case `private`, friends, `public`
    var id: String { rawValue }
    var title: String {
        switch self {
        case .private: "Only me"
        case .friends: "Friends"
        case .public: "Everyone"
        }
    }
    var symbol: String {
        switch self {
        case .private: "lock"
        case .friends: "person.2"
        case .public: "globe"
        }
    }
}

private struct ErrorMessage: Decodable { let error: String }

/// Shelf's cloud API: backup and the social side.
enum CloudAPI {
    enum Failure: LocalizedError {
        case signedOut, status(Int, String)
        var errorDescription: String? {
            switch self {
            case .signedOut: "Sign in to use this."
            case .status(_, let message): message
            }
        }
        var code: Int? { if case .status(let c, _) = self { c } else { nil } }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // Fractional seconds, so the newest edit wins even within a second.
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(isoFormatter.string(from: date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let text = try c.decode(String.self)
            if let date = isoFormatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unreadable date \(text)")
        }
        return d
    }()

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    @MainActor
    static func send<T: Decodable>(_ method: String, _ path: String, body: (some Encodable)? = Optional<Int>.none,
                                   query: [String: String] = [:], signedIn: Bool = true) async throws -> T {
        var url = URLComponents(url: CloudConfig.api.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: url.url!, timeoutInterval: 30)
        request.httpMethod = method
        if signedIn {
            guard let token = try await Auth.shared.token() else { throw Failure.signedOut }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorMessage.self, from: data))?.error ?? "Shelf's cloud didn't answer (\(status))."
            throw Failure.status(status, message)
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: Calls

    @MainActor static func me() async throws -> MyProfile { try await send("GET", "me") }

    @MainActor static func updateMe(username: String? = nil, displayName: String? = nil, bio: String? = nil) async throws -> MyProfile {
        struct Body: Encodable { var username: String?; var displayName: String?; var bio: String? }
        return try await send("PUT", "me", body: Body(username: username, displayName: displayName, bio: bio))
    }

    struct SyncResult: Decodable { var applied: Int; var changes: [CloudChange]; var cursor: Double }

    @MainActor static func sync(since: Double, changes: [CloudChange]) async throws -> SyncResult {
        struct Body: Encodable { var since: Double; var changes: [CloudChange] }
        return try await send("POST", "sync", body: Body(since: since, changes: changes))
    }

    @MainActor static func person(_ username: String) async throws -> PersonShelf { try await send("GET", "users/\(username)") }

    @MainActor static func search(_ text: String) async throws -> [PublicProfile] {
        struct Result: Decodable { var results: [PublicProfile] }
        return try await (send("GET", "search", query: ["q": text]) as Result).results
    }

    @MainActor static func follow(_ username: String, _ on: Bool) async throws {
        struct Result: Decodable { var following: Bool }
        let _: Result = try await send(on ? "POST" : "DELETE", "users/\(username)/follow")
    }

    /// Request, accept, or (with `on` false) cancel / decline / unfriend.
    @MainActor static func friend(_ username: String, _ on: Bool) async throws -> String {
        struct Result: Decodable { var friend: String }
        return try await (send(on ? "POST" : "DELETE", "users/\(username)/friend") as Result).friend
    }

    @MainActor static func friendRequests() async throws -> [PublicProfile] {
        struct Result: Decodable { var requests: [PublicProfile] }
        return try await (send("GET", "friends/requests") as Result).requests
    }

    @MainActor static func feed() async throws -> [FeedEntry] {
        struct Result: Decodable { var entries: [FeedEntry] }
        return try await (send("GET", "feed") as Result).entries
    }
}
