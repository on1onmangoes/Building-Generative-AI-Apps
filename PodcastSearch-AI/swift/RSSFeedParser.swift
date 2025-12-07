import Foundation

/// Parser for podcast RSS feeds to extract episodes and transcript information
/// Supports Apple Podcast namespace extensions for transcripts
actor RSSFeedParser: NSObject {

    static let shared = RSSFeedParser()

    private let session: URLSession

    private override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        super.init()
    }

    // MARK: - Fetch and Parse Feed

    /// Fetch and parse a podcast RSS feed
    func parseFeed(url: String) async throws -> PodcastFeed {
        guard let feedURL = URL(string: url) else {
            throw PodcastAPIError.invalidURL
        }

        let (data, _) = try await session.data(from: feedURL)
        return try parseFeedData(data)
    }

    /// Parse RSS feed data
    func parseFeedData(_ data: Data) throws -> PodcastFeed {
        let parser = RSSXMLParser(data: data)
        return try parser.parse()
    }

    // MARK: - Get Episodes with Metadata

    /// Get all episodes from a feed URL
    func getEpisodes(feedUrl: String, limit: Int? = nil) async throws -> [Episode] {
        let feed = try await parseFeed(url: feedUrl)
        if let limit = limit {
            return Array(feed.episodes.prefix(limit))
        }
        return feed.episodes
    }

    /// Get episodes that have transcripts available
    func getEpisodesWithTranscripts(feedUrl: String) async throws -> [Episode] {
        let episodes = try await getEpisodes(feedUrl: feedUrl)
        return episodes.filter { $0.hasTranscript }
    }

    // MARK: - Fetch Transcript

    /// Fetch transcript content for an episode
    func fetchTranscript(for episode: Episode) async throws -> Transcript {
        guard let transcriptUrl = episode.transcriptUrl,
              let url = URL(string: transcriptUrl) else {
            throw PodcastAPIError.transcriptNotAvailable
        }

        let (data, _) = try await session.data(from: url)

        guard let content = String(data: data, encoding: .utf8) else {
            throw PodcastAPIError.feedParsingError("Could not decode transcript")
        }

        let format = detectTranscriptFormat(url: transcriptUrl, content: content)

        switch format {
        case .srt:
            return parseSRTTranscript(content, episodeId: episode.id)
        case .vtt:
            return parseVTTTranscript(content, episodeId: episode.id)
        case .json:
            return try parseJSONTranscript(data, episodeId: episode.id)
        default:
            return Transcript(
                episodeId: episode.id,
                format: .text,
                segments: nil,
                fullText: content,
                language: nil
            )
        }
    }

    // MARK: - Transcript Parsing

    private func detectTranscriptFormat(url: String, content: String) -> TranscriptFormat {
        if url.hasSuffix(".srt") { return .srt }
        if url.hasSuffix(".vtt") || content.hasPrefix("WEBVTT") { return .vtt }
        if url.hasSuffix(".json") || content.hasPrefix("{") || content.hasPrefix("[") { return .json }
        return .text
    }

    private func parseSRTTranscript(_ content: String, episodeId: String) -> Transcript {
        var segments: [TranscriptSegment] = []
        let blocks = content.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }

            // Parse timestamp line: "00:00:01,000 --> 00:00:04,000"
            let timeLine = lines[1]
            let times = timeLine.components(separatedBy: " --> ")
            guard times.count == 2 else { continue }

            let startTime = parseTimestamp(times[0])
            let endTime = parseTimestamp(times[1])
            let text = lines.dropFirst(2).joined(separator: " ")

            segments.append(TranscriptSegment(
                startTime: startTime,
                endTime: endTime,
                text: text,
                speaker: nil
            ))
        }

        return Transcript(
            episodeId: episodeId,
            format: .srt,
            segments: segments,
            fullText: segments.map(\.text).joined(separator: " "),
            language: nil
        )
    }

    private func parseVTTTranscript(_ content: String, episodeId: String) -> Transcript {
        var segments: [TranscriptSegment] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Look for timestamp line: "00:00:01.000 --> 00:00:04.000"
            if line.contains("-->") {
                let times = line.components(separatedBy: " --> ")
                guard times.count >= 2 else {
                    i += 1
                    continue
                }

                let startTime = parseTimestamp(times[0])
                let endTime = parseTimestamp(times[1].components(separatedBy: " ").first ?? times[1])

                // Collect text lines until empty line
                var textLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].isEmpty {
                    textLines.append(lines[i])
                    i += 1
                }

                if !textLines.isEmpty {
                    segments.append(TranscriptSegment(
                        startTime: startTime,
                        endTime: endTime,
                        text: textLines.joined(separator: " "),
                        speaker: nil
                    ))
                }
            }
            i += 1
        }

        return Transcript(
            episodeId: episodeId,
            format: .vtt,
            segments: segments,
            fullText: segments.map(\.text).joined(separator: " "),
            language: nil
        )
    }

    private func parseJSONTranscript(_ data: Data, episodeId: String) throws -> Transcript {
        // Try Apple Podcasts JSON format
        struct AppleTranscript: Codable {
            let segments: [AppleSegment]?

            struct AppleSegment: Codable {
                let startTime: Double?
                let endTime: Double?
                let text: String?
                let speaker: String?
            }
        }

        do {
            let apple = try JSONDecoder().decode(AppleTranscript.self, from: data)
            let segments = apple.segments?.compactMap { seg -> TranscriptSegment? in
                guard let text = seg.text else { return nil }
                return TranscriptSegment(
                    startTime: seg.startTime ?? 0,
                    endTime: seg.endTime ?? 0,
                    text: text,
                    speaker: seg.speaker
                )
            } ?? []

            return Transcript(
                episodeId: episodeId,
                format: .json,
                segments: segments,
                fullText: segments.map(\.text).joined(separator: " "),
                language: nil
            )
        } catch {
            // Fallback: try as plain text array
            if let text = String(data: data, encoding: .utf8) {
                return Transcript(
                    episodeId: episodeId,
                    format: .text,
                    segments: nil,
                    fullText: text,
                    language: nil
                )
            }
            throw PodcastAPIError.feedParsingError("Could not parse JSON transcript")
        }
    }

    private func parseTimestamp(_ timestamp: String) -> Double {
        let cleaned = timestamp.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")

        let parts = cleaned.components(separatedBy: ":")
        guard parts.count >= 2 else { return 0 }

        var seconds: Double = 0

        if parts.count == 3 {
            // HH:MM:SS.mmm
            seconds += (Double(parts[0]) ?? 0) * 3600
            seconds += (Double(parts[1]) ?? 0) * 60
            seconds += Double(parts[2]) ?? 0
        } else {
            // MM:SS.mmm
            seconds += (Double(parts[0]) ?? 0) * 60
            seconds += Double(parts[1]) ?? 0
        }

        return seconds
    }
}

// MARK: - Podcast Feed Model

struct PodcastFeed {
    let title: String
    let description: String
    let author: String?
    let language: String?
    let copyright: String?
    let imageUrl: String?
    let websiteUrl: String?
    let categories: [String]
    let episodes: [Episode]
}

// MARK: - RSS XML Parser

class RSSXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var feed: PodcastFeed?
    private var episodes: [Episode] = []
    private var categories: [String] = []

    // Parsing state
    private var currentElement = ""
    private var currentText = ""
    private var isInChannel = false
    private var isInItem = false

    // Channel data
    private var channelTitle = ""
    private var channelDescription = ""
    private var channelAuthor: String?
    private var channelLanguage: String?
    private var channelCopyright: String?
    private var channelImageUrl: String?
    private var channelWebsiteUrl: String?

    // Item data
    private var itemTitle = ""
    private var itemDescription = ""
    private var itemPubDate = ""
    private var itemDuration: Int?
    private var itemAudioUrl: String?
    private var itemGuid = ""
    private var itemEpisodeNumber: Int?
    private var itemSeasonNumber: Int?
    private var itemEpisodeType: String?
    private var itemExplicit = false
    private var itemTranscriptUrl: String?
    private var itemTranscriptType: String?

    init(data: Data) {
        self.data = data
        super.init()
    }

    func parse() throws -> PodcastFeed {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        if let error = parser.parserError {
            throw PodcastAPIError.feedParsingError(error.localizedDescription)
        }

        return PodcastFeed(
            title: channelTitle,
            description: channelDescription,
            author: channelAuthor,
            language: channelLanguage,
            copyright: channelCopyright,
            imageUrl: channelImageUrl,
            websiteUrl: channelWebsiteUrl,
            categories: categories,
            episodes: episodes
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {

        currentElement = elementName
        currentText = ""

        switch elementName {
        case "channel":
            isInChannel = true
        case "item":
            isInItem = true
            resetItemData()
        case "enclosure":
            if isInItem, let url = attributeDict["url"],
               attributeDict["type"]?.contains("audio") == true {
                itemAudioUrl = url
            }
        case "itunes:image":
            if !isInItem, let href = attributeDict["href"] {
                channelImageUrl = href
            }
        case "podcast:transcript":
            // Apple Podcasts transcript extension
            if isInItem {
                itemTranscriptUrl = attributeDict["url"]
                itemTranscriptType = attributeDict["type"]
            }
        case "itunes:category":
            if let category = attributeDict["text"] {
                categories.append(category)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {

        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isInItem {
            // Episode data
            switch elementName {
            case "title":
                itemTitle = text
            case "description", "itunes:summary":
                if itemDescription.isEmpty {
                    itemDescription = text
                }
            case "pubDate":
                itemPubDate = text
            case "itunes:duration":
                itemDuration = parseDuration(text)
            case "guid":
                itemGuid = text
            case "itunes:episode":
                itemEpisodeNumber = Int(text)
            case "itunes:season":
                itemSeasonNumber = Int(text)
            case "itunes:episodeType":
                itemEpisodeType = text
            case "itunes:explicit":
                itemExplicit = text.lowercased() == "yes" || text.lowercased() == "true"
            case "item":
                // End of item - create episode
                let episode = Episode(
                    id: itemGuid.isEmpty ? UUID().uuidString : itemGuid,
                    title: itemTitle,
                    description: itemDescription,
                    publishDate: itemPubDate,
                    duration: itemDuration,
                    audioUrl: itemAudioUrl,
                    episodeNumber: itemEpisodeNumber,
                    seasonNumber: itemSeasonNumber,
                    episodeType: itemEpisodeType,
                    explicit: itemExplicit,
                    transcriptUrl: itemTranscriptUrl,
                    transcriptType: itemTranscriptType
                )
                episodes.append(episode)
                isInItem = false
            default:
                break
            }
        } else if isInChannel {
            // Channel data
            switch elementName {
            case "title":
                channelTitle = text
            case "description", "itunes:summary":
                if channelDescription.isEmpty {
                    channelDescription = text
                }
            case "itunes:author":
                channelAuthor = text
            case "language":
                channelLanguage = text
            case "copyright":
                channelCopyright = text
            case "link":
                channelWebsiteUrl = text
            default:
                break
            }
        }
    }

    private func resetItemData() {
        itemTitle = ""
        itemDescription = ""
        itemPubDate = ""
        itemDuration = nil
        itemAudioUrl = nil
        itemGuid = ""
        itemEpisodeNumber = nil
        itemSeasonNumber = nil
        itemEpisodeType = nil
        itemExplicit = false
        itemTranscriptUrl = nil
        itemTranscriptType = nil
    }

    private func parseDuration(_ text: String) -> Int? {
        // Duration can be in seconds or HH:MM:SS format
        if let seconds = Int(text) {
            return seconds
        }

        let parts = text.components(separatedBy: ":")
        guard !parts.isEmpty else { return nil }

        var totalSeconds = 0
        let reversedParts = Array(parts.reversed())

        for (index, part) in reversedParts.enumerated() {
            guard let value = Int(part) else { continue }
            switch index {
            case 0: totalSeconds += value           // seconds
            case 1: totalSeconds += value * 60      // minutes
            case 2: totalSeconds += value * 3600    // hours
            default: break
            }
        }

        return totalSeconds > 0 ? totalSeconds : nil
    }
}
