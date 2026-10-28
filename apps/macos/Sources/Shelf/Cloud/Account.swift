import Foundation
import Observation

/// Your Shelf account: signed out, choosing a username, or signed in.
/// Signing in is optional; without it Shelf works exactly as before.
@MainActor
@Observable
final class Account {
    static let shared = Account()

    enum State: Equatable {
        case signedOut
        case checking
        /// Signed in, but no username yet. Carries a suggested display name.
        case needsUsername(String)
        case signedIn(MyProfile)
        /// Signed in, but Shelf's cloud couldn't be reached just now.
        case unreachable(String)
    }

    private(set) var state: State = .signedOut
    var error: String?

    var profile: MyProfile? { if case .signedIn(let p) = state { p } else { nil } }
    var isSignedIn: Bool { profile != nil }

    private init() {}

    /// On launch: pick up an existing sign-in quietly.
    func restore() async {
        guard Auth.shared.hasSession else { state = .signedOut; return }
        await refresh()
    }

    func signIn() async {
        error = nil
        do {
            try await Auth.shared.signIn()
            await refresh()
        } catch Auth.Failure.cancelled {
            state = .signedOut
        } catch {
            self.error = error.localizedDescription
            state = .signedOut
        }
    }

    func refresh() async {
        state = .checking
        do {
            state = .signedIn(try await CloudAPI.me())
            CloudSync.shared.start()
            await FriendsList.shared.refresh()
        } catch let failure as CloudAPI.Failure where failure.code == 404 {
            state = .needsUsername("")
        } catch CloudAPI.Failure.signedOut {
            state = .signedOut
        } catch {
            // Offline or the cloud is down: stay signed in, try again later.
            state = Auth.shared.hasSession ? .unreachable(error.localizedDescription) : .signedOut
        }
    }

    /// Claims a username (or changes it) and sets the display name.
    func save(username: String, displayName: String, bio: String? = nil) async -> Bool {
        error = nil
        do {
            let profile = try await CloudAPI.updateMe(username: username, displayName: displayName, bio: bio)
            state = .signedIn(profile)
            CloudSync.shared.start()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func signOut() {
        Auth.shared.signOut()
        CloudSync.shared.reset()
        state = .signedOut
    }
}
