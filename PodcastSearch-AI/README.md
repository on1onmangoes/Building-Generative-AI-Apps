# PodcastSearch-AI

A podcast search and shortlisting application that helps you discover podcasts and integrate them into your Swift app. Includes a curated list of **70 Best Food Podcasts** with full metadata.

## Project Structure

```
PodcastSearch-AI/
├── app/                          # Python/Gradio backend
│   ├── app.py                    # Main Gradio application
│   └── requirements.txt          # Python dependencies
├── swift/                        # Swift/iOS implementation
│   ├── PodcastModels.swift       # Data models (Podcast, Episode, Transcript)
│   ├── iTunesAPIService.swift    # iTunes Search API service
│   ├── RSSFeedParser.swift       # RSS feed parser for episodes & transcripts
│   ├── FoodPodcastsData.swift    # Curated list of 70 food podcasts
│   ├── PodcastSearchManager.swift # Main manager class
│   └── PodcastSearchView.swift   # SwiftUI views
└── README.md
```

## Features

- **Search Podcasts**: Search the iTunes podcast directory with keywords, topics, or names
- **Genre Filtering**: Filter results by podcast genre (Comedy, Technology, News, etc.)
- **Multi-Country Support**: Search podcasts from different countries (US, UK, CA, AU, etc.)
- **Shortlist Creation**: Select and create a shortlist of your favorite podcasts
- **JSON Export**: Get results in JSON format for easy integration with mobile apps
- **Swift-Ready**: Data structures designed for seamless Swift/iOS integration

## Quick Start

### Installation

```bash
cd PodcastSearch-AI/app
pip install -r requirements.txt
```

### Run Locally

```bash
python app.py
```

The app will be available at `http://localhost:7860`

## API Usage

### Python API

```python
from app import search_podcasts, api_search

# Simple search
podcasts = search_podcasts("technology", limit=10)

# Full API response
result = api_search("true crime", limit=20, country="US", genre="True Crime")
print(result["count"])  # Number of results
print(result["podcasts"])  # List of podcast dictionaries
```

### JSON Response Format

```json
{
  "count": 10,
  "podcasts": [
    {
      "id": "123456789",
      "name": "Podcast Name",
      "artist": "Host Name",
      "artwork_url": "https://...",
      "feed_url": "https://...",
      "genre": "Technology",
      "episode_count": 150,
      "description": "A great podcast about...",
      "release_date": "2024-01-15"
    }
  ]
}
```

## Swift Integration

### Podcast Model

```swift
import Foundation

struct PodcastResponse: Codable {
    let count: Int
    let podcasts: [Podcast]
}

struct Podcast: Codable, Identifiable {
    let id: String
    let name: String
    let artist: String
    let artworkUrl: String
    let feedUrl: String
    let genre: String
    let episodeCount: Int
    let description: String
    let releaseDate: String

    enum CodingKeys: String, CodingKey {
        case id, name, artist, genre, description
        case artworkUrl = "artwork_url"
        case feedUrl = "feed_url"
        case episodeCount = "episode_count"
        case releaseDate = "release_date"
    }
}
```

### Network Service

```swift
import Foundation

class PodcastService {
    static let shared = PodcastService()

    // For local development
    private let baseURL = "http://localhost:7860"

    // For production (when deployed to HuggingFace Spaces)
    // private let baseURL = "https://your-space.hf.space"

    func searchPodcasts(query: String, limit: Int = 10) async throws -> [Podcast] {
        // If using the Gradio API endpoint
        let url = URL(string: "\(baseURL)/api/predict")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "data": [query, limit, "US", "All Genres"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(PodcastResponse.self, from: data)
        return response.podcasts
    }
}
```

### Alternative: Direct iTunes API (Client-Side)

If you prefer to call the iTunes API directly from your Swift app:

```swift
import Foundation

class iTunesPodcastService {
    static let shared = iTunesPodcastService()

    private let baseURL = "https://itunes.apple.com/search"

    func searchPodcasts(query: String, limit: Int = 10, country: String = "US") async throws -> [Podcast] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country)
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)

        struct iTunesResponse: Codable {
            let resultCount: Int
            let results: [iTunesPodcast]
        }

        struct iTunesPodcast: Codable {
            let collectionId: Int
            let collectionName: String
            let artistName: String
            let artworkUrl600: String?
            let feedUrl: String?
            let primaryGenreName: String?
            let trackCount: Int?
            let releaseDate: String?
        }

        let response = try JSONDecoder().decode(iTunesResponse.self, from: data)

        return response.results.map { item in
            Podcast(
                id: String(item.collectionId),
                name: item.collectionName,
                artist: item.artistName,
                artworkUrl: item.artworkUrl600 ?? "",
                feedUrl: item.feedUrl ?? "",
                genre: item.primaryGenreName ?? "",
                episodeCount: item.trackCount ?? 0,
                description: "",
                releaseDate: String(item.releaseDate?.prefix(10) ?? "")
            )
        }
    }
}
```

### SwiftUI View Example

```swift
import SwiftUI

struct PodcastSearchView: View {
    @State private var searchText = ""
    @State private var podcasts: [Podcast] = []
    @State private var shortlist: [Podcast] = []
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            List {
                Section("Search") {
                    TextField("Search podcasts...", text: $searchText)
                        .onSubmit { Task { await search() } }
                }

                Section("Results (\(podcasts.count))") {
                    ForEach(podcasts) { podcast in
                        PodcastRow(podcast: podcast) {
                            addToShortlist(podcast)
                        }
                    }
                }

                if !shortlist.isEmpty {
                    Section("Shortlist (\(shortlist.count))") {
                        ForEach(shortlist) { podcast in
                            Text(podcast.name)
                        }
                    }
                }
            }
            .navigationTitle("Podcast Search")
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
    }

    func search() async {
        isLoading = true
        defer { isLoading = false }

        do {
            podcasts = try await iTunesPodcastService.shared.searchPodcasts(query: searchText)
        } catch {
            print("Search failed: \(error)")
        }
    }

    func addToShortlist(_ podcast: Podcast) {
        if !shortlist.contains(where: { $0.id == podcast.id }) {
            shortlist.append(podcast)
        }
    }
}

struct PodcastRow: View {
    let podcast: Podcast
    let onAdd: () -> Void

    var body: some View {
        HStack {
            AsyncImage(url: URL(string: podcast.artworkUrl)) { image in
                image.resizable()
            } placeholder: {
                Color.gray
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)

            VStack(alignment: .leading) {
                Text(podcast.name)
                    .font(.headline)
                Text(podcast.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(podcast.episodeCount) episodes")
                    .font(.caption)
            }

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus.circle")
            }
        }
    }
}
```

## Available Genres

- Arts
- Business
- Comedy
- Education
- Fiction
- Health
- History
- Kids
- Music
- News
- Science
- Sports
- Technology
- True Crime
- TV & Film

## Supported Countries

| Code | Country |
|------|---------|
| US | United States |
| GB | United Kingdom |
| CA | Canada |
| AU | Australia |
| DE | Germany |
| FR | France |
| JP | Japan |
| MX | Mexico |
| BR | Brazil |
| IN | India |

## Deployment

### Deploy to Hugging Face Spaces

1. Create a new Space on [Hugging Face](https://huggingface.co/spaces)
2. Select "Gradio" as the SDK
3. Upload `app.py` and `requirements.txt`
4. Your app will be available at `https://your-username-your-space.hf.space`

### Update Swift App for Production

Replace the localhost URL with your Hugging Face Space URL:

```swift
private let baseURL = "https://your-username-podcast-search.hf.space"
```

## Complete Swift Implementation

The `swift/` directory contains a complete, production-ready Swift implementation:

### Swift Files

| File | Description |
|------|-------------|
| `PodcastModels.swift` | All data models: `Podcast`, `Episode`, `Transcript`, `PodcastShortlist` |
| `iTunesAPIService.swift` | iTunes Search API integration with async/await |
| `RSSFeedParser.swift` | XML parser for podcast RSS feeds, extracts episodes and transcripts |
| `FoodPodcastsData.swift` | Curated list of 70 food podcasts with metadata |
| `PodcastSearchManager.swift` | Main manager combining all services |
| `PodcastSearchView.swift` | Complete SwiftUI interface |

### Usage in Your Swift App

1. Copy all files from `swift/` to your Xcode project
2. Use the `PodcastSearchManager`:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var manager = PodcastSearchManager()

    var body: some View {
        PodcastSearchView()
    }
}

// Or use programmatically:
let manager = PodcastSearchManager()

// Search iTunes
await manager.search(query: "food cooking")

// Get curated food podcasts
let topRated = manager.getTopRatedFoodPodcasts(limit: 10)

// Get full podcast data with episodes
if let podcast = manager.searchResults.first {
    let fullData = await manager.getFullPodcastData(for: podcast)

    // Export as JSON for integration
    let json = fullData.toJSON()
}

// Manage shortlist
manager.addToShortlist(podcast)
let shortlistJSON = manager.exportShortlistAsJSON()
```

### Transcript Support

The RSS parser supports the `<podcast:transcript>` tag (Apple Podcasts specification):

```swift
// Get episodes with transcripts
let episodes = await manager.fetchEpisodesWithTranscripts(for: podcast)

// Fetch transcript content
if let episode = episodes.first {
    let transcript = await manager.fetchTranscript(for: episode)
    print(transcript?.fullText ?? "No transcript")
}
```

**Note:** Transcripts are only available if the podcast publisher includes them in their RSS feed using the `<podcast:transcript>` tag. Not all podcasts have transcripts available.

## Food Podcasts List

The app includes a curated list of 70 top food podcasts with:
- Name, hosts, producer
- Apple rating and review count
- Average episode length
- Format (Short/Medium/Long form)
- Description

Access via `FoodPodcastsData`:

```swift
// All podcasts
let all = FoodPodcastsData.allPodcasts

// Top rated
let topRated = FoodPodcastsData.topRated(limit: 10)

// Most reviewed
let popular = FoodPodcastsData.mostReviewed(limit: 10)

// Search
let results = FoodPodcastsData.search(query: "Gastropod")

// Filter by format
let longForm = FoodPodcastsData.podcasts(format: "Long form")
```

## License

MIT License
