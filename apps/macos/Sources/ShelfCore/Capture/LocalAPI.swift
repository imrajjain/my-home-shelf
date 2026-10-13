import Foundation

/// The tiny localhost API the browser extension talks to.
///
///     GET  /v1/ping          -> {"ok":true,"app":"Shelf","version":"0.1"}
///     POST /v1/items         body: CaptureRequest JSON -> {"ok":true,"id":"…"}
///
/// Every request must carry `X-Shelf-Token: <token>` (shown in Settings).
/// No CORS headers are ever sent, so ordinary web pages can't use it.
public enum LocalAPI {
    public static let defaultPort: UInt16 = 47_291
    public static let tokenHeader = "x-shelf-token"
    public static let maxRequestBytes = 512 * 1024

    public struct Request: Sendable {
        public var method: String
        public var path: String
        public var headers: [String: String]   // lowercased names
        public var body: Data
    }

    public enum ParseResult: Sendable {
        case complete(Request)
        case needMoreData
        case invalid
    }

    /// Incremental HTTP/1.1 request parsing over the bytes received so far.
    public static func parse(_ data: Data) -> ParseResult {
        guard data.count <= maxRequestBytes else { return .invalid }
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            return data.count > 16 * 1024 ? .invalid : .needMoreData
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .invalid }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= maxRequestBytes else { return .invalid }
        let bodyStart = headerEnd.upperBound
        guard data.endIndex - bodyStart >= length else { return .needMoreData }
        let body = data[bodyStart..<(bodyStart + length)]

        let rawPath = String(requestLine[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        return .complete(Request(method: String(requestLine[0]).uppercased(), path: path, headers: headers, body: Data(body)))
    }

    public static func response(status: Int, json: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        let reason: String = switch status {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    /// Constant-time comparison so the token can't be guessed byte by byte.
    public static func tokensMatch(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count, !y.isEmpty else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    public static func makeToken() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        var rng = SystemRandomNumberGenerator()
        let raw = (0..<20).map { _ in alphabet[Int(rng.next(upperBound: UInt32(alphabet.count)))] }
        // Group for legibility: xxxxx-xxxxx-xxxxx-xxxxx
        return stride(from: 0, to: raw.count, by: 5).map { String(raw[$0..<min($0 + 5, raw.count)]) }.joined(separator: "-")
    }
}
