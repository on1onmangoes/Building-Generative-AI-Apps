import Foundation

/// Main manager for podcast search, discovery, and shortlist management
/// Combines iTunes API search with RSS parsing for comprehensive metadata
@MainActor
class PodcastSearchManager: ObservableObject {

    // MARK: - Published Properties

    @Published var searchResults: [Podcast] = []
    @Published var shortlist: PodcastShortlist
    @Published var isLoading = false
    @Published var error: String?

    // Services
    private let iTunesService = iTunesAPIService.shared
    private let rssParser = RSSFeedParser.shared

    // Cache
    private var podcastCache: [String: Podcast] = [:]
    private var episodeCache: [String: [Episode]] = [:]

    // MARK: - Initialization

    init(shortlistName: String = "My Podcast Shortlist") {
        self.shortlist = PodcastShortlist(name: shortlistName)
        loadShortlistFromStorage()
    }

    // MARK: - Search Methods

    /// Search podcasts by query
    func search(query: String, limit: Int = 25) async {
        isLoading = true
        error = nil

        do {
            let results = try await iTunesService.search(term: query, limit: limit)
            searchResults = results

            // Cache results
            for podcast in results {
                podcastCache[podcast.id] = podcast
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Search for a specific podcast from the food podcasts list
    func searchFoodPodcast(entry: FoodPodcastEntry) async -> Podcast? {
        isLoading = true
        error = nil

        do {
            if let iTunesPodcast = try await iTunesService.searchPodcastByName(
                entry.name,
                artist: entry.hosts.first
            ) {
                let podcast = await iTunesService.toPodcast(iTunesPodcast)
                podcastCache[podcast.id] = podcast
                isLoading = false
                return podcast
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
        return nil
    }

    /// Load all food podcasts from the curated list
    func loadAllFoodPodcasts() async -> [Podcast] {
        isLoading = true
        error = nil

        do {
            let podcasts = try await iTunesService.searchFoodPodcasts(
                entries: FoodPodcastsData.allPodcasts
            )
            searchResults = podcasts

            for podcast in podcasts {
                podcastCache[podcast.id] = podcast
            }

            isLoading = false
            return podcasts
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return []
        }
    }

    /// Get top rated food podcasts
    func getTopRatedFoodPodcasts(limit: Int = 10) -> [FoodPodcastEntry] {
        FoodPodcastsData.topRated(limit: limit)
    }

    /// Search within the curated food podcast list
    func searchFoodPodcasts(query: String) -> [FoodPodcastEntry] {
        FoodPodcastsData.search(query: query)
    }

    // MARK: - Episode Methods

    /// Fetch episodes for a podcast
    func fetchEpisodes(for podcast: Podcast, limit: Int? = 20) async -> [Episode] {
        guard !podcast.feedUrl.isEmpty else {
            error = "No feed URL available for this podcast"
            return []
        }

        // Check cache first
        if let cached = episodeCache[podcast.id] {
            return cached
        }

        isLoading = true

        do {
            let episodes = try await rssParser.getEpisodes(feedUrl: podcast.feedUrl, limit: limit)
            episodeCache[podcast.id] = episodes
            isLoading = false
            return episodes
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return []
        }
    }

    /// Get episodes that have transcripts
    func fetchEpisodesWithTranscripts(for podcast: Podcast) async -> [Episode] {
        guard !podcast.feedUrl.isEmpty else { return [] }

        isLoading = true

        do {
            let episodes = try await rssParser.getEpisodesWithTranscripts(feedUrl: podcast.feedUrl)
            isLoading = false
            return episodes
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return []
        }
    }

    /// Fetch transcript for an episode
    func fetchTranscript(for episode: Episode) async -> Transcript? {
        guard episode.hasTranscript else {
            error = "No transcript available for this episode"
            return nil
        }

        isLoading = true

        do {
            let transcript = try await rssParser.fetchTranscript(for: episode)
            isLoading = false
            return transcript
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return nil
        }
    }

    // MARK: - Shortlist Methods

    /// Add podcast to shortlist
    func addToShortlist(_ podcast: Podcast) {
        shortlist.add(podcast)
        saveShortlistToStorage()
    }

    /// Remove podcast from shortlist
    func removeFromShortlist(_ podcast: Podcast) {
        shortlist.remove(podcast)
        saveShortlistToStorage()
    }

    /// Check if podcast is in shortlist
    func isInShortlist(_ podcast: Podcast) -> Bool {
        shortlist.podcasts.contains { $0.id == podcast.id }
    }

    /// Clear shortlist
    func clearShortlist() {
        shortlist.podcasts.removeAll()
        saveShortlistToStorage()
    }

    /// Export shortlist as JSON
    func exportShortlistAsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(shortlist)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"\(error.localizedDescription)\"}"
        }
    }

    // MARK: - Comprehensive Podcast Data

    /// Get full podcast data with episodes and transcript info
    func getFullPodcastData(for podcast: Podcast) async -> PodcastFullData {
        var fullData = PodcastFullData(podcast: podcast)

        // Fetch episodes
        let episodes = await fetchEpisodes(for: podcast)
        fullData.episodes = episodes
        fullData.episodeCount = episodes.count

        // Check for transcripts
        fullData.episodesWithTranscripts = episodes.filter { $0.hasTranscript }
        fullData.hasTranscripts = !fullData.episodesWithTranscripts.isEmpty

        // Get additional metadata from RSS
        if !podcast.feedUrl.isEmpty {
            do {
                let feed = try await rssParser.parseFeed(url: podcast.feedUrl)
                fullData.language = feed.language
                fullData.copyright = feed.copyright
                fullData.websiteUrl = feed.websiteUrl
                fullData.categories = feed.categories
                fullData.fullDescription = feed.description
            } catch {
                print("Could not fetch RSS metadata: \(error)")
            }
        }

        return fullData
    }

    // MARK: - Storage

    private func saveShortlistToStorage() {
        do {
            let data = try JSONEncoder().encode(shortlist)
            UserDefaults.standard.set(data, forKey: "podcast_shortlist")
        } catch {
            print("Failed to save shortlist: \(error)")
        }
    }

    private func loadShortlistFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: "podcast_shortlist"),
              let saved = try? JSONDecoder().decode(PodcastShortlist.self, from: data) else {
            return
        }
        shortlist = saved
    }
}

// MARK: - Full Podcast Data Model

struct PodcastFullData {
    var podcast: Podcast
    var episodes: [Episode] = []
    var episodeCount: Int = 0
    var episodesWithTranscripts: [Episode] = []
    var hasTranscripts: Bool = false
    var language: String?
    var copyright: String?
    var websiteUrl: String?
    var categories: [String] = []
    var fullDescription: String?

    /// Export as JSON for integration with other apps
    func toJSON() -> String {
        let data: [String: Any] = [
            "podcast": [
                "id": podcast.id,
                "name": podcast.name,
                "artist": podcast.artist,
                "artwork_url": podcast.artworkUrl,
                "feed_url": podcast.feedUrl,
                "genre": podcast.genre,
                "episode_count": episodeCount,
                "description": fullDescription ?? podcast.description,
                "apple_rating": podcast.appleRating as Any,
                "apple_review_count": podcast.appleReviewCount as Any,
                "apple_podcast_url": podcast.applePodcastUrl as Any,
                "language": language as Any,
                "copyright": copyright as Any,
                "website_url": websiteUrl as Any,
                "categories": categories
            ],
            "episodes": episodes.map { ep in
                [
                    "id": ep.id,
                    "title": ep.title,
                    "description": ep.description,
                    "publish_date": ep.publishDate,
                    "duration_seconds": ep.duration as Any,
                    "audio_url": ep.audioUrl as Any,
                    "episode_number": ep.episodeNumber as Any,
                    "season_number": ep.seasonNumber as Any,
                    "has_transcript": ep.hasTranscript,
                    "transcript_url": ep.transcriptUrl as Any
                ]
            },
            "has_transcripts": hasTranscripts,
            "transcripts_available_count": episodesWithTranscripts.count
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"\(error.localizedDescription)\"}"
        }
    }
}

// MARK: - Usage Examples

/*
 // Example: Search and shortlist podcasts

 let manager = PodcastSearchManager()

 // Search iTunes
 await manager.search(query: "food cooking")

 // Get food podcasts from curated list
 let topRated = manager.getTopRatedFoodPodcasts(limit: 10)

 // Search within food podcasts list
 let results = manager.searchFoodPodcasts(query: "Gastropod")

 // Load all food podcasts with iTunes data
 let allPodcasts = await manager.loadAllFoodPodcasts()

 // Get full data for a podcast including episodes
 if let podcast = manager.searchResults.first {
     let fullData = await manager.getFullPodcastData(for: podcast)
     print(fullData.toJSON())
 }

 // Add to shortlist
 manager.addToShortlist(podcast)

 // Export shortlist
 let json = manager.exportShortlistAsJSON()


 // Example: Fetch transcript

 let episodes = await manager.fetchEpisodes(for: podcast)
 if let episodeWithTranscript = episodes.first(where: { $0.hasTranscript }) {
     if let transcript = await manager.fetchTranscript(for: episodeWithTranscript) {
         print(transcript.fullText ?? "No text")
     }
 }
 */
