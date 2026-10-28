import Foundation
import Observation

/// The people you follow and your friends, plus requests waiting for you.
@MainActor
@Observable
final class FriendsList {
    static let shared = FriendsList()

    struct Person: Codable, Identifiable, Hashable {
        var username: String
        var displayName: String
        var bio: String?
        var following: Bool
        /// none, requested, friends
        var friend: String
        var id: String { username }
    }

    private(set) var people: [Person] = []
    private(set) var requests: [PublicProfile] = []
    private(set) var feed: [FeedEntry] = []

    func refresh() async {
        guard Account.shared.isSignedIn else { people = []; requests = []; feed = []; return }
        struct Result: Decodable { var people: [Person] }
        if let result: Result = try? await CloudAPI.send("GET", "me/people") { people = result.people }
        if let incoming = try? await CloudAPI.friendRequests() { requests = incoming }
        if let entries = try? await CloudAPI.feed() { feed = entries }
    }
}
