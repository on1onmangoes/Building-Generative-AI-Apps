import SwiftUI

/// SwiftUI View for searching and shortlisting podcasts
struct PodcastSearchView: View {
    @StateObject private var manager = PodcastSearchManager()
    @State private var searchText = ""
    @State private var selectedTab = 0
    @State private var selectedPodcast: Podcast?
    @State private var showingPodcastDetail = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("View", selection: $selectedTab) {
                    Text("Search").tag(0)
                    Text("Food Podcasts").tag(1)
                    Text("Shortlist (\(manager.shortlist.podcasts.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                // Content based on selected tab
                switch selectedTab {
                case 0:
                    searchView
                case 1:
                    foodPodcastsView
                case 2:
                    shortlistView
                default:
                    searchView
                }
            }
            .navigationTitle("Podcast Search")
            .sheet(isPresented: $showingPodcastDetail) {
                if let podcast = selectedPodcast {
                    PodcastDetailView(podcast: podcast, manager: manager)
                }
            }
        }
    }

    // MARK: - Search View

    private var searchView: some View {
        VStack {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search podcasts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task {
                            await manager.search(query: searchText)
                        }
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)

            // Results
            if manager.isLoading {
                ProgressView("Searching...")
                    .padding()
                Spacer()
            } else if let error = manager.error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                }
                .padding()
                Spacer()
            } else {
                podcastList(podcasts: manager.searchResults)
            }
        }
    }

    // MARK: - Food Podcasts View

    private var foodPodcastsView: some View {
        VStack {
            // Quick filter buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    FilterButton(title: "Top Rated", systemImage: "star.fill") {
                        // Show top rated
                    }
                    FilterButton(title: "Most Reviewed", systemImage: "text.bubble.fill") {
                        // Show most reviewed
                    }
                    FilterButton(title: "Long Form", systemImage: "clock.fill") {
                        // Filter by format
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            // Food podcasts list
            List(FoodPodcastsData.allPodcasts, id: \.rank) { entry in
                FoodPodcastRow(entry: entry) {
                    Task {
                        if let podcast = await manager.searchFoodPodcast(entry: entry) {
                            selectedPodcast = podcast
                            showingPodcastDetail = true
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Shortlist View

    private var shortlistView: some View {
        VStack {
            if manager.shortlist.podcasts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No podcasts in shortlist")
                        .font(.headline)
                    Text("Search and add podcasts to build your shortlist")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                Spacer()
            } else {
                // Export button
                HStack {
                    Spacer()
                    Button(action: exportShortlist) {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                    .padding(.trailing)
                }

                podcastList(podcasts: manager.shortlist.podcasts, isShortlist: true)
            }
        }
    }

    // MARK: - Podcast List

    private func podcastList(podcasts: [Podcast], isShortlist: Bool = false) -> some View {
        List(podcasts, id: \.id) { podcast in
            PodcastRow(
                podcast: podcast,
                isInShortlist: manager.isInShortlist(podcast),
                onTap: {
                    selectedPodcast = podcast
                    showingPodcastDetail = true
                },
                onShortlistToggle: {
                    if manager.isInShortlist(podcast) {
                        manager.removeFromShortlist(podcast)
                    } else {
                        manager.addToShortlist(podcast)
                    }
                }
            )
        }
        .listStyle(.plain)
    }

    private func exportShortlist() {
        let json = manager.exportShortlistAsJSON()
        UIPasteboard.general.string = json
        // Could also share via share sheet
    }
}

// MARK: - Podcast Row

struct PodcastRow: View {
    let podcast: Podcast
    let isInShortlist: Bool
    let onTap: () -> Void
    let onShortlistToggle: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Artwork
                AsyncImage(url: URL(string: podcast.artworkUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(podcast.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(podcast.artist)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack {
                        if !podcast.genre.isEmpty {
                            Text(podcast.genre)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                        if podcast.episodeCount > 0 {
                            Text("\(podcast.episodeCount) episodes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Shortlist button
                Button(action: onShortlistToggle) {
                    Image(systemName: isInShortlist ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2)
                        .foregroundColor(isInShortlist ? .green : .blue)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Food Podcast Row

struct FoodPodcastRow: View {
    let entry: FoodPodcastEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                // Rank
                Text("#\(entry.rank)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.headline)
                        .lineLimit(2)

                    if !entry.hosts.isEmpty {
                        Text(entry.hosts.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        if let rating = entry.appleRating {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", rating))
                            }
                            .font(.caption)
                        }

                        if let reviews = entry.appleReviews {
                            Text("(\(reviews) reviews)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let format = entry.format {
                            Text(format)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Button

struct FilterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(16)
        }
    }
}

// MARK: - Podcast Detail View

struct PodcastDetailView: View {
    let podcast: Podcast
    @ObservedObject var manager: PodcastSearchManager
    @State private var episodes: [Episode] = []
    @State private var isLoadingEpisodes = false
    @State private var fullData: PodcastFullData?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(alignment: .top, spacing: 16) {
                        AsyncImage(url: URL(string: podcast.artworkUrl)) { image in
                            image.resizable()
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 120, height: 120)
                        .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(podcast.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(podcast.artist)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            if !podcast.genre.isEmpty {
                                Text(podcast.genre)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }

                            // Shortlist button
                            Button(action: {
                                if manager.isInShortlist(podcast) {
                                    manager.removeFromShortlist(podcast)
                                } else {
                                    manager.addToShortlist(podcast)
                                }
                            }) {
                                Label(
                                    manager.isInShortlist(podcast) ? "In Shortlist" : "Add to Shortlist",
                                    systemImage: manager.isInShortlist(podcast) ? "checkmark.circle.fill" : "plus.circle"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(manager.isInShortlist(podcast) ? .green : .blue)
                        }
                    }
                    .padding()

                    Divider()

                    // Metadata
                    if let fullData = fullData {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.headline)

                            if let desc = fullData.fullDescription, !desc.isEmpty {
                                Text(desc)
                                    .font(.body)
                            }

                            if fullData.hasTranscripts {
                                Label("\(fullData.episodesWithTranscripts.count) episodes with transcripts", systemImage: "text.bubble")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }

                            if !fullData.categories.isEmpty {
                                Text("Categories: \(fullData.categories.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Divider()

                    // Episodes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Episodes (\(episodes.count))")
                            .font(.headline)
                            .padding(.horizontal)

                        if isLoadingEpisodes {
                            ProgressView()
                                .padding()
                        } else {
                            ForEach(episodes) { episode in
                                EpisodeRow(episode: episode)
                            }
                        }
                    }

                    // Export JSON button
                    if let fullData = fullData {
                        Button(action: {
                            UIPasteboard.general.string = fullData.toJSON()
                        }) {
                            Label("Copy Full JSON Data", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding()
                    }
                }
            }
            .navigationTitle("Podcast Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadData()
            }
        }
    }

    private func loadData() async {
        isLoadingEpisodes = true
        episodes = await manager.fetchEpisodes(for: podcast)
        fullData = await manager.getFullPodcastData(for: podcast)
        isLoadingEpisodes = false
    }
}

// MARK: - Episode Row

struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(episode.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Spacer()

                if episode.hasTranscript {
                    Image(systemName: "text.bubble.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            HStack {
                Text(episode.publishDate)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let duration = episode.duration {
                    Text("• \(duration / 60) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let epNum = episode.episodeNumber {
                    Text("• Ep \(epNum)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview

#Preview {
    PodcastSearchView()
}
