import Foundation

/// Service for searching podcasts via Apple iTunes Search API
/// API Documentation: https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/
actor iTunesAPIService {

    static let shared = iTunesAPIService()

    private let baseURL = "https://itunes.apple.com"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Search Podcasts

    /// Search for podcasts by term
    /// - Parameters:
    ///   - term: Search query
    ///   - limit: Maximum results (1-200)
    ///   - country: Two-letter country code (US, GB, etc.)
    /// - Returns: Array of iTunesPodcast results
    func searchPodcasts(
        term: String,
        limit: Int = 25,
        country: String = "US"
    ) async throws -> [iTunesPodcast] {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }

        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: String(min(limit, 200))),
            URLQueryItem(name: "country", value: country)
        ]

        guard let url = components.url else {
            throw PodcastAPIError.invalidURL
        }

        do {
            let (data, response) = try await session.data(from: url)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 {
                    throw PodcastAPIError.rateLimited
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw PodcastAPIError.networkError(
                        NSError(domain: "HTTP", code: httpResponse.statusCode)
                    )
                }
            }

            let searchResponse = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
            return searchResponse.results

        } catch let error as PodcastAPIError {
            throw error
        } catch let error as DecodingError {
            throw PodcastAPIError.decodingError(error)
        } catch {
            throw PodcastAPIError.networkError(error)
        }
    }

    /// Search for a specific podcast by name (more precise matching)
    func searchPodcastByName(_ name: String, artist: String? = nil) async throws -> iTunesPodcast? {
        var searchTerm = name
        if let artist = artist {
            searchTerm = "\(name) \(artist)"
        }

        let results = try await searchPodcasts(term: searchTerm, limit: 10)

        // Try to find exact match first
        if let exactMatch = results.first(where: {
            $0.collectionName.lowercased() == name.lowercased()
        }) {
            return exactMatch
        }

        // Try partial match
        if let partialMatch = results.first(where: {
            $0.collectionName.lowercased().contains(name.lowercased()) ||
            name.lowercased().contains($0.collectionName.lowercased())
        }) {
            return partialMatch
        }

        return results.first
    }

    /// Lookup podcast by iTunes ID
    func lookupPodcast(id: Int) async throws -> iTunesPodcast? {
        var components = URLComponents(string: "\(baseURL)/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "entity", value: "podcast")
        ]

        guard let url = components.url else {
            throw PodcastAPIError.invalidURL
        }

        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
        return response.results.first
    }

    /// Lookup multiple podcasts by IDs
    func lookupPodcasts(ids: [Int]) async throws -> [iTunesPodcast] {
        guard !ids.isEmpty else { return [] }

        var components = URLComponents(string: "\(baseURL)/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "entity", value: "podcast")
        ]

        guard let url = components.url else {
            throw PodcastAPIError.invalidURL
        }

        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
        return response.results
    }

    // MARK: - Convert to Unified Model

    /// Convert iTunes podcast to unified Podcast model
    func toPodcast(_ iTunes: iTunesPodcast) -> Podcast {
        Podcast(
            id: String(iTunes.collectionId),
            name: iTunes.collectionName,
            artist: iTunes.artistName,
            artworkUrl: iTunes.artworkUrl,
            feedUrl: iTunes.feedUrl ?? "",
            genre: iTunes.primaryGenreName ?? "",
            episodeCount: iTunes.trackCount ?? 0,
            description: "",
            releaseDate: String(iTunes.releaseDate?.prefix(10) ?? ""),
            appleRating: nil,
            appleReviewCount: nil,
            applePodcastUrl: iTunes.collectionViewUrl,
            country: iTunes.country,
            episodes: nil,
            language: nil,
            copyright: nil,
            websiteUrl: nil,
            author: iTunes.artistName,
            categories: iTunes.genres
        )
    }

    /// Search and convert to unified model
    func search(
        term: String,
        limit: Int = 25,
        country: String = "US"
    ) async throws -> [Podcast] {
        let results = try await searchPodcasts(term: term, limit: limit, country: country)
        return results.map { toPodcast($0) }
    }
}

// MARK: - Batch Search Extension

extension iTunesAPIService {

    /// Search for multiple podcasts by name with rate limiting
    func searchMultiple(
        names: [String],
        delayBetweenRequests: UInt64 = 500_000_000 // 0.5 seconds in nanoseconds
    ) async throws -> [String: Podcast?] {
        var results: [String: Podcast?] = [:]

        for name in names {
            do {
                if let iTunesPodcast = try await searchPodcastByName(name) {
                    results[name] = toPodcast(iTunesPodcast)
                } else {
                    results[name] = nil
                }
            } catch {
                print("Error searching for '\(name)': \(error)")
                results[name] = nil
            }

            // Rate limiting delay
            try await Task.sleep(nanoseconds: delayBetweenRequests)
        }

        return results
    }

    /// Search for all food podcasts from the curated list
    func searchFoodPodcasts(entries: [FoodPodcastEntry]) async throws -> [Podcast] {
        var podcasts: [Podcast] = []

        for entry in entries {
            do {
                if let iTunesPodcast = try await searchPodcastByName(
                    entry.name,
                    artist: entry.hosts.first
                ) {
                    var podcast = toPodcast(iTunesPodcast)
                    // Enrich with data from our list
                    podcast = enrichPodcast(podcast, with: entry)
                    podcasts.append(podcast)
                }
                // Rate limit: 0.3 second delay between requests
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                print("Could not find: \(entry.name) - \(error)")
            }
        }

        return podcasts
    }

    private func enrichPodcast(_ podcast: Podcast, with entry: FoodPodcastEntry) -> Podcast {
        Podcast(
            id: podcast.id,
            name: podcast.name,
            artist: entry.hosts.joined(separator: ", "),
            artworkUrl: podcast.artworkUrl,
            feedUrl: podcast.feedUrl,
            genre: podcast.genre,
            episodeCount: podcast.episodeCount,
            description: entry.description ?? podcast.description,
            releaseDate: entry.since ?? podcast.releaseDate,
            appleRating: entry.appleRating,
            appleReviewCount: entry.appleReviews,
            applePodcastUrl: entry.appleUrl ?? podcast.applePodcastUrl,
            country: podcast.country,
            episodes: podcast.episodes,
            language: podcast.language,
            copyright: podcast.copyright,
            websiteUrl: entry.websiteUrl,
            author: entry.producer,
            categories: podcast.categories
        )
    }
}
