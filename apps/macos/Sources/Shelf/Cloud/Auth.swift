import AppKit
import AuthenticationServices
import CryptoKit
import ShelfCore

/// Signs in with Microsoft Entra External ID: the authorization-code flow
/// with PKCE in macOS's own sign-in sheet, the standard for desktop apps.
/// The refresh token lives in the keychain; access tokens only in memory.
@MainActor
final class Auth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = Auth()

    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private var session: ASWebAuthenticationSession?

    var hasSession: Bool { Keychain.read("refresh") != nil }

    enum Failure: LocalizedError {
        case cancelled, failed(String)
        var errorDescription: String? {
            switch self {
            case .cancelled: "Sign-in was cancelled."
            case .failed(let why): why
            }
        }
    }

    /// Opens the sign-in sheet; resolves once tokens are stored.
    func signIn() async throws {
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(24)
        var url = URLComponents(url: CloudConfig.authority.appending(path: "authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            .init(name: "client_id", value: CloudConfig.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: CloudConfig.redirectURI),
            .init(name: "scope", value: CloudConfig.scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: CloudConfig.redirectScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { continuation.resume(throwing: Failure.cancelled) }
                else { continuation.resume(throwing: Failure.failed(error?.localizedDescription ?? "Sign-in didn't finish.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error_description" })?.value ?? items.first(where: { $0.name == "error" })?.value {
            throw Failure.failed(error)
        }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw Failure.failed("Sign-in came back incomplete.") }
        try await redeem([
            "grant_type": "authorization_code", "code": code, "code_verifier": verifier,
            "redirect_uri": CloudConfig.redirectURI,
        ])
    }

    /// A valid access token, refreshing quietly when needed; nil when signed out.
    func token() async throws -> String? {
        if let accessToken, expiresAt > .now.addingTimeInterval(60) { return accessToken }
        guard let refresh = Keychain.read("refresh") else { return nil }
        try await redeem(["grant_type": "refresh_token", "refresh_token": refresh])
        return accessToken
    }

    func signOut() {
        accessToken = nil
        expiresAt = .distantPast
        Keychain.write(nil, "refresh")
    }

    private func redeem(_ fields: [String: String]) async throws {
        var request = URLRequest(url: CloudConfig.authority.appending(path: "token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let all = fields.merging(["client_id": CloudConfig.clientID, "scope": CloudConfig.scopes]) { a, _ in a }
        request.httpBody = all.map { "\($0.key)=\($0.value.queryEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        struct Tokens: Decodable { let access_token: String?; let refresh_token: String?; let expires_in: Double?; let error_description: String? }
        let tokens = try JSONDecoder().decode(Tokens.self, from: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let access = tokens.access_token else {
            // A refresh token that no longer works means signing in again.
            if fields["grant_type"] == "refresh_token" { signOut() }
            throw Failure.failed(tokens.error_description?.components(separatedBy: "\r\n").first ?? "Couldn't sign in.")
        }
        accessToken = access
        expiresAt = .now.addingTimeInterval(tokens.expires_in ?? 3600)
        if let refresh = tokens.refresh_token { Keychain.write(refresh, "refresh") }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() }
    }

    private static func randomString(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
