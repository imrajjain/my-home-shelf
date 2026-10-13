import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Tiny HTTP helper with a polite, browser-like identity. Some sites
/// (Goodreads, Letterboxd) serve stripped pages to unknown agents.
public struct HTTP: Sendable {
    public static let shared = HTTP()

    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15 Shelf/0.1"

    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(_ url: URL, accept: String = "*/*", timeout: TimeInterval = 12) async throws -> (Data, URL) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MetadataError.badResponse(http.statusCode)
        }
        return (data, response.url ?? url)
    }

    public func json<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, _) = try await data(url, accept: "application/json")
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func jsonObject(from url: URL) async throws -> [String: Any] {
        let (data, _) = try await data(url, accept: "application/json")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MetadataError.unreadable
        }
        return object
    }
}

extension URL {
    /// Builds `base?name=value&...` with proper escaping.
    static func api(_ base: String, _ query: [String: String]) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.percentEncodedQueryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key.queryEncoded, value: $0.value.queryEncoded) }
        return components.url
    }

    /// Upgrades http:// to https:// (Google Books thumbnails, etc).
    var secured: URL {
        guard scheme == "http", var c = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        c.scheme = "https"
        return c.url ?? self
    }

    var hostWithoutWWW: String {
        let h = (host ?? "").lowercased()
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    /// Like `queryValue`, but decodes HTML-form style `+` as a space
    /// (what search engines put in their URLs).
    func formValue(_ name: String) -> String? {
        guard let raw = URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .percentEncodedQueryItems?.first(where: { $0.name == name })?.value else { return nil }
        return raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }
}

extension String {
    /// Percent-encodes for use as a query name/value. Unlike URLComponents'
    /// default, this also escapes `&`, `=`, `+`, `?` and `#`.
    public var queryEncoded: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#/")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
