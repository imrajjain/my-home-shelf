import Foundation

/// Where Shelf's cloud lives. None of these are secrets: a desktop app is a
/// public client, and the API checks every token it's given.
enum CloudConfig {
    static let tenantID = "ba154de6-63d1-45c4-8ad7-a98f3d8415b3"
    static let authority = URL(string: "https://shelfraj.ciamlogin.com/\(tenantID)/oauth2/v2.0")!
    /// Shelf for Mac, the app people sign in to.
    static let clientID = "0b9bc567-893b-4a9c-9af1-bbd26b10ec8f"
    /// Shelf API: tokens are issued for its `access` scope.
    static let apiScope = "api://3e7f5280-e2af-43a7-9c03-456c5d49dba9/access"
    static let scopes = "\(apiScope) openid offline_access"
    static let redirectScheme = "shelf"
    static let redirectURI = "shelf://auth"
    static let api = URL(string: "https://shelfraj-api.azurewebsites.net")!
    /// The public website (Azure Static Web Apps, free plan).
    static let web = URL(string: "https://gentle-water-02c5bb500.5.azurestaticapps.net")!
    /// A profile anyone can open; it offers "Open in Shelf" to people who have the app.
    static func profileURL(_ username: String) -> URL { web.appending(path: "u/\(username)") }
}
