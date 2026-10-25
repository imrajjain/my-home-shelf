import AppKit
import CryptoKit
import ShelfCore

/// One note in the World Currencies room. The collection is curated once
/// (see scripts/museum/currencies.py) and ships with the app as JSON;
/// the scans load from Wikipedia, Wikimedia Commons and central banks.
struct Banknote: Codable, Identifiable, Hashable {
    struct Side: Codable, Hashable {
        /// A large rendition of the scan.
        var image: URL
        /// A small rendition for the drawer, when the source offers one.
        var thumb: URL?
        /// The file's page, with its author and licence.
        var page: URL
        var credit: String
        /// Who or what is pictured.
        var subject: String?
    }

    var id: String
    var country: String
    var flag: String
    var region: String
    var currency: String
    /// ISO 4217 code, which groups a currency's notes together.
    var code: String?
    /// Other countries where this currency is the money in use.
    var alsoUsedIn: [String]?
    var denomination: String
    var issued: String
    var series: String?
    var front: Side
    var back: Side
    var history: String
    var design: String
    var source: URL
}

extension Banknote {
    var currencyKey: String { code ?? currency }
}

struct BanknoteCollection: Codable {
    var notes: [Banknote]
}

@MainActor
enum Banknotes {
    static let all: [Banknote] = load()

    /// From the app bundle, or straight from the source tree in a
    /// `swift run` debug build that has no bundle.
    private static func load() -> [Banknote] {
        let bundled = Bundle.main.url(forResource: "currencies", withExtension: "json", subdirectory: "Museum")
        let source = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Support/Museum/currencies.json")
        for url in [bundled, source].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let collection = try? JSONDecoder().decode(BanknoteCollection.self, from: data) {
                return collection.notes
            }
        }
        return []
    }

    /// One entry per currency, in collection order.
    struct Currency: Identifiable, Hashable {
        var id: String
        var name: String
        var country: String
        var flag: String
        var region: String
        var count: Int
        var first: Banknote.ID
    }

    static let currencies: [Currency] = {
        var order: [String] = []
        var map: [String: Currency] = [:]
        for note in all {
            let key = note.currencyKey
            if var c = map[key] { c.count += 1; map[key] = c; continue }
            order.append(key)
            map[key] = Currency(id: key, name: note.currency, country: note.country, flag: note.flag,
                                region: note.region, count: 1, first: note.id)
        }
        return order.compactMap { map[$0] }
    }()

    static var regions: [String] {
        var seen = Set<String>()
        return all.map(\.region).filter { seen.insert($0).inserted }
    }
}

/// Scans are big, so they're kept on disk after the first look.
@MainActor
final class BanknoteImages {
    static let shared = BanknoteImages()
    private var memory: [URL: NSImage] = [:]
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    private let folder: URL = {
        let url = URL.cachesDirectory.appending(path: "Shelf/Museum", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func cached(_ url: URL) -> NSImage? { memory[url] }

    func image(_ url: URL) async -> NSImage? {
        if let image = memory[url] { return image }
        if let task = inFlight[url] { return await task.value }
        let file = folder.appending(path: Self.name(for: url))
        let task = Task<NSImage?, Never> {
            if let image = NSImage(contentsOf: file) { return image }
            guard let data = try? await HTTP.shared.data(url, accept: "image/*", timeout: 30).0,
                  let image = NSImage(data: data) else { return nil }
            try? data.write(to: file)
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory[url] = image }
        return image
    }

    private static func name(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined() + "." + (url.pathExtension.isEmpty ? "img" : url.pathExtension)
    }
}
