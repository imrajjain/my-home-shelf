import AppKit
import AVFoundation
import CryptoKit
import ShelfCore

/// One country in the Flags & Anthems room. Curated once by
/// scripts/museum/flags.py and shipped as JSON; the flag images and anthem
/// recordings come from Wikimedia Commons, public domain or freely licensed.
struct NationalFlag: Codable, Identifiable, Hashable {
    struct Image: Codable, Hashable {
        var image: URL
        var page: URL
        var credit: String
        /// Width over height, as the flag is officially drawn.
        var aspect: Double

        /// Commons serves a few fixed thumbnail widths; 330 suits the drawer.
        var thumb: URL {
            URL(string: image.absoluteString.replacingOccurrences(of: "/1280px-", with: "/330px-")) ?? image
        }
    }

    struct Recording: Codable, Hashable {
        var audio: URL
        var page: URL
        var credit: String
        var duration: Double?
    }

    struct Anthem: Codable, Hashable {
        var title: String?
        var composers: [String]
        var lyricists: [String]
        var about: String
        var source: URL?
        var recording: Recording?
    }

    var id: String
    var country: String
    var emoji: String
    var region: String
    var flag: Image
    var flagTitle: String
    var flagAbout: String
    var flagSource: URL
    var anthem: Anthem?
}

private struct FlagCollection: Codable {
    var countries: [NationalFlag]
}

@MainActor
enum NationalFlags {
    static let all: [NationalFlag] = load()

    static var regions: [String] {
        var seen = Set<String>()
        return all.map(\.region).sorted().filter { seen.insert($0).inserted }
    }

    private static func load() -> [NationalFlag] {
        let bundled = Bundle.main.url(forResource: "flags", withExtension: "json", subdirectory: "Museum")
        let source = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Support/Museum/flags.json")
        for url in [bundled, source].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let collection = try? JSONDecoder().decode(FlagCollection.self, from: data) {
                return collection.countries
            }
        }
        return []
    }
}

/// Plays one anthem at a time, kept on disk after the first listen, and
/// reports how loud it is right now so the flag can move with the music.
@Observable @MainActor
final class AnthemPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = AnthemPlayer()

    private(set) var playingID: String?
    private(set) var loadingID: String?
    private(set) var failedID: String?
    private var player: AVAudioPlayer?

    private let folder: URL = {
        let url = URL.cachesDirectory.appending(path: "Shelf/Museum/Anthems", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    var progress: Double {
        guard let player, player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }

    var duration: Double { player?.duration ?? 0 }

    func isPlaying(_ flag: NationalFlag) -> Bool { playingID == flag.id }

    /// 0…1, smoothed loudness of what's playing.
    func level() -> Double {
        guard let player, player.isPlaying else { return 0 }
        player.updateMeters()
        let db = Double(player.averagePower(forChannel: 0))   // about -60…0
        return max(0, min(1, (db + 40) / 40))
    }

    func toggle(_ flag: NationalFlag) {
        if playingID == flag.id { stop() } else { Task { await play(flag) } }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    private func play(_ flag: NationalFlag) async {
        guard let recording = flag.anthem?.recording else { return }
        stop()
        loadingID = flag.id
        failedID = nil
        defer { if loadingID == flag.id { loadingID = nil } }
        let file = folder.appending(path: Self.name(for: recording.audio))
        if !FileManager.default.fileExists(atPath: file.path) {
            guard let data = try? await HTTP.shared.data(recording.audio, accept: "audio/*", timeout: 60).0 else {
                failedID = flag.id
                return
            }
            try? data.write(to: file)
        }
        // Someone may have moved on while it downloaded.
        guard loadingID == flag.id, let player = try? AVAudioPlayer(contentsOf: file) else {
            if loadingID == flag.id { failedID = flag.id }
            return
        }
        player.isMeteringEnabled = true
        player.delegate = self
        player.play()
        self.player = player
        playingID = flag.id
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.player = nil; self.playingID = nil }
        }
    }

    private static func name(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined() + ".mp3"
    }
}
