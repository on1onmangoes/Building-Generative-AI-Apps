import Foundation

// MARK: - iTunes Search API Response Models

struct iTunesSearchResponse: Codable {
    let resultCount: Int
    let results: [iTunesPodcast]
}

struct iTunesPodcast: Codable, Identifiable {
    let collectionId: Int
    let collectionName: String
    let artistName: String
    let artworkUrl600: String?
    let artworkUrl100: String?
    let feedUrl: String?
    let primaryGenreName: String?
    let genreIds: [String]?
    let genres: [String]?
    let trackCount: Int?
    let releaseDate: String?
    let collectionExplicitness: String?
    let contentAdvisoryRating: String?
    let country: String?
    let collectionViewUrl: String?

    var id: Int { collectionId }

    var artworkUrl: String {
        artworkUrl600 ?? artworkUrl100 ?? ""
    }
}

// MARK: - Unified Podcast Model (for your app)

struct Podcast: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String
    let artworkUrl: String
    let feedUrl: String
    let genre: String
    let episodeCount: Int
    let description: String
    let releaseDate: String
    let appleRating: Double?
    let appleReviewCount: Int?
    let applePodcastUrl: String?
    let country: String?

    // Additional metadata from RSS
    var episodes: [Episode]?
    var language: String?
    var copyright: String?
    var websiteUrl: String?
    var author: String?
    var categories: [String]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Podcast, rhs: Podcast) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Episode Model

struct Episode: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let publishDate: String
    let duration: Int? // in seconds
    let audioUrl: String?
    let episodeNumber: Int?
    let seasonNumber: Int?
    let episodeType: String? // "full", "trailer", "bonus"
    let explicit: Bool?

    // Transcript info
    var transcriptUrl: String?
    var transcriptType: String? // "srt", "vtt", "json"
    var hasTranscript: Bool { transcriptUrl != nil }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Transcript Model

struct Transcript: Codable {
    let episodeId: String
    let format: TranscriptFormat
    let segments: [TranscriptSegment]?
    let fullText: String?
    let language: String?
}

struct TranscriptSegment: Codable {
    let startTime: Double
    let endTime: Double
    let text: String
    let speaker: String?
}

enum TranscriptFormat: String, Codable {
    case srt
    case vtt
    case json
    case text
    case none
}

// MARK: - Shortlist Model

struct PodcastShortlist: Codable {
    let id: String
    let name: String
    let createdAt: Date
    var podcasts: [Podcast]

    init(name: String, podcasts: [Podcast] = []) {
        self.id = UUID().uuidString
        self.name = name
        self.createdAt = Date()
        self.podcasts = podcasts
    }

    mutating func add(_ podcast: Podcast) {
        if !podcasts.contains(where: { $0.id == podcast.id }) {
            podcasts.append(podcast)
        }
    }

    mutating func remove(_ podcast: Podcast) {
        podcasts.removeAll { $0.id == podcast.id }
    }
}

// MARK: - Food Podcast Entry (from your list)

struct FoodPodcastEntry: Codable {
    let rank: Int
    let name: String
    let hosts: [String]
    let producer: String?
    let appleRating: Double?
    let appleReviews: Int?
    let avgLengthMinutes: Int?
    let format: String? // "Short form", "Medium form", "Long form", "Extended"
    let since: String?
    let description: String?
    let websiteUrl: String?
    let appleUrl: String?
    let spotifyUrl: String?
}

// MARK: - API Error Types

enum PodcastAPIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case noResults
    case rateLimited
    case feedParsingError(String)
    case transcriptNotAvailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .noResults:
            return "No results found"
        case .rateLimited:
            return "Rate limited - please try again later"
        case .feedParsingError(let message):
            return "Feed parsing error: \(message)"
        case .transcriptNotAvailable:
            return "Transcript not available for this episode"
        }
    }
}
