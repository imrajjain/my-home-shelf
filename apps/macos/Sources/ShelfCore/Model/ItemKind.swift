import Foundation

/// Every kind of thing that can live on the shelf.
public enum ItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case book
    case film
    case show
    case paper
    case article
    case video
    case podcast
    case music
    case place
    case curiosity

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .book: "Book"
        case .film: "Film"
        case .show: "Show"
        case .paper: "Paper"
        case .article: "Article"
        case .video: "Video"
        case .podcast: "Podcast"
        case .music: "Music"
        case .place: "Place"
        case .curiosity: "Curiosity"
        }
    }

    public var pluralTitle: String {
        switch self {
        case .book: "Books"
        case .film: "Films"
        case .show: "Shows"
        case .paper: "Papers"
        case .article: "Articles & Blogs"
        case .video: "Videos"
        case .podcast: "Podcasts"
        case .music: "Music"
        case .place: "Places"
        case .curiosity: "Curiosities"
        }
    }

    public var symbol: String {
        switch self {
        case .book: "book.closed"
        case .film: "film"
        case .show: "tv"
        case .paper: "doc.text.magnifyingglass"
        case .article: "newspaper"
        case .video: "play.rectangle"
        case .podcast: "waveform"
        case .music: "music.note"
        case .place: "mappin.and.ellipse"
        case .curiosity: "sparkle.magnifyingglass"
        }
    }

    /// Verb phrases for each status, so the UI reads naturally:
    /// "Want to read" / "Reading" / "Read".
    public func label(for status: ItemStatus) -> String {
        switch (self, status) {
        case (_, .dropped): return "Set aside"
        case (.book, .want), (.paper, .want), (.article, .want): return "Want to read"
        case (.book, .inProgress), (.paper, .inProgress), (.article, .inProgress): return "Reading"
        case (.book, .done), (.paper, .done), (.article, .done): return "Read"
        case (.film, .want), (.show, .want), (.video, .want): return "Want to watch"
        case (.film, .inProgress), (.show, .inProgress), (.video, .inProgress): return "Watching"
        case (.film, .done), (.show, .done), (.video, .done): return "Watched"
        case (.podcast, .want), (.music, .want): return "Want to listen"
        case (.podcast, .inProgress), (.music, .inProgress): return "Listening"
        case (.podcast, .done), (.music, .done): return "Listened"
        case (.place, .want): return "Want to go"
        case (.place, .inProgress): return "Planning"
        case (.place, .done): return "Been there"
        case (.curiosity, .want): return "Want to explore"
        case (.curiosity, .inProgress): return "Exploring"
        case (.curiosity, .done): return "Explored"
        }
    }

    /// Cover aspect ratio (width / height) that suits the medium.
    public var coverAspect: Double {
        switch self {
        case .book, .film, .show: 2.0 / 3.0
        case .podcast, .music, .place, .curiosity: 1.0
        case .paper, .article: 3.0 / 4.0
        case .video: 16.0 / 9.0
        }
    }

    /// Kinds whose covers carry the identity (posters, jackets, artwork).
    public var isVisual: Bool {
        switch self {
        case .book, .film, .show, .podcast, .music, .video: true
        case .paper, .article, .place, .curiosity: false
        }
    }
}

public enum ItemStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case want
    case inProgress
    case done
    case dropped

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .want: "Up next"
        case .inProgress: "In progress"
        case .done: "Finished"
        case .dropped: "Set aside"
        }
    }

    public var symbol: String {
        switch self {
        case .want: "bookmark"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.seal"
        case .dropped: "moon.zzz"
        }
    }
}
