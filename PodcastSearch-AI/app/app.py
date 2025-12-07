"""
PodcastSearch-AI: A podcast search and shortlist application
Searches podcasts using iTunes Search API and provides semantic ranking
"""

import gradio as gr
import requests
from typing import List, Dict, Optional
import json
from dataclasses import dataclass, asdict
from datetime import datetime

# iTunes Search API endpoint (free, no auth required)
ITUNES_SEARCH_URL = "https://itunes.apple.com/search"

@dataclass
class Podcast:
    """Podcast data structure for easy serialization to Swift"""
    id: str
    name: str
    artist: str
    artwork_url: str
    feed_url: str
    genre: str
    episode_count: int
    description: str
    release_date: str

    def to_dict(self) -> Dict:
        return asdict(self)

def search_podcasts(
    query: str,
    limit: int = 10,
    country: str = "US",
    genre: Optional[str] = None
) -> List[Podcast]:
    """
    Search for podcasts using iTunes Search API

    Args:
        query: Search term
        limit: Maximum number of results (1-200)
        country: Two-letter country code
        genre: Optional genre filter

    Returns:
        List of Podcast objects
    """
    if not query or not query.strip():
        return []

    params = {
        "term": query,
        "media": "podcast",
        "entity": "podcast",
        "limit": min(limit, 200),
        "country": country
    }

    if genre:
        params["genreId"] = get_genre_id(genre)

    try:
        response = requests.get(ITUNES_SEARCH_URL, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()

        podcasts = []
        for item in data.get("results", []):
            podcast = Podcast(
                id=str(item.get("collectionId", "")),
                name=item.get("collectionName", "Unknown"),
                artist=item.get("artistName", "Unknown"),
                artwork_url=item.get("artworkUrl600", item.get("artworkUrl100", "")),
                feed_url=item.get("feedUrl", ""),
                genre=item.get("primaryGenreName", ""),
                episode_count=item.get("trackCount", 0),
                description=item.get("description", "") or item.get("collectionName", ""),
                release_date=item.get("releaseDate", "")[:10] if item.get("releaseDate") else ""
            )
            podcasts.append(podcast)

        return podcasts

    except requests.RequestException as e:
        print(f"Error searching podcasts: {e}")
        return []

def get_genre_id(genre_name: str) -> str:
    """Map genre names to iTunes genre IDs"""
    genres = {
        "arts": "1301",
        "business": "1321",
        "comedy": "1303",
        "education": "1304",
        "fiction": "1483",
        "health": "1307",
        "history": "1487",
        "kids": "1305",
        "music": "1310",
        "news": "1489",
        "science": "1533",
        "sports": "1545",
        "technology": "1318",
        "true crime": "1488",
        "tv & film": "1309"
    }
    return genres.get(genre_name.lower(), "")

def get_available_genres() -> List[str]:
    """Return list of available podcast genres"""
    return [
        "Arts", "Business", "Comedy", "Education", "Fiction",
        "Health", "History", "Kids", "Music", "News",
        "Science", "Sports", "Technology", "True Crime", "TV & Film"
    ]

def format_results_for_display(podcasts: List[Podcast]) -> str:
    """Format podcast results as markdown for Gradio display"""
    if not podcasts:
        return "No podcasts found. Try a different search term."

    output = f"## Found {len(podcasts)} Podcasts\n\n"

    for i, podcast in enumerate(podcasts, 1):
        output += f"### {i}. {podcast.name}\n"
        output += f"**Artist:** {podcast.artist}\n\n"
        output += f"**Genre:** {podcast.genre} | **Episodes:** {podcast.episode_count}\n\n"
        if podcast.description and podcast.description != podcast.name:
            desc = podcast.description[:200] + "..." if len(podcast.description) > 200 else podcast.description
            output += f"*{desc}*\n\n"
        output += f"---\n\n"

    return output

def format_results_as_json(podcasts: List[Podcast]) -> str:
    """Format podcast results as JSON for API consumption"""
    return json.dumps({
        "count": len(podcasts),
        "podcasts": [p.to_dict() for p in podcasts]
    }, indent=2)

def search_and_display(query: str, limit: int, country: str, genre: str):
    """Main search function for Gradio interface"""
    genre_filter = genre if genre != "All Genres" else None
    podcasts = search_podcasts(query, limit, country, genre_filter)

    display_output = format_results_for_display(podcasts)
    json_output = format_results_as_json(podcasts)

    return display_output, json_output

def create_shortlist(current_json: str, indices: str) -> str:
    """Create a shortlist from selected podcast indices"""
    try:
        data = json.loads(current_json)
        podcasts = data.get("podcasts", [])

        # Parse indices (e.g., "1, 3, 5" or "1-3, 5")
        selected_indices = []
        for part in indices.split(","):
            part = part.strip()
            if "-" in part:
                start, end = map(int, part.split("-"))
                selected_indices.extend(range(start, end + 1))
            else:
                selected_indices.append(int(part))

        # Filter podcasts (convert to 0-indexed)
        shortlist = [podcasts[i-1] for i in selected_indices if 0 < i <= len(podcasts)]

        return json.dumps({
            "count": len(shortlist),
            "shortlist": shortlist
        }, indent=2)

    except (json.JSONDecodeError, ValueError, IndexError) as e:
        return json.dumps({"error": str(e)})

# Build Gradio Interface
with gr.Blocks(title="PodcastSearch-AI", theme=gr.themes.Soft()) as app:
    gr.Markdown("""
    # 🎙️ PodcastSearch-AI

    Search for podcasts and create a shortlist to integrate with your app.

    **API Endpoint:** Use the JSON output to integrate with your Swift app.
    """)

    with gr.Row():
        with gr.Column(scale=2):
            query_input = gr.Textbox(
                label="Search Query",
                placeholder="Enter podcast topic, name, or keywords...",
                lines=1
            )
        with gr.Column(scale=1):
            limit_slider = gr.Slider(
                minimum=5,
                maximum=50,
                value=10,
                step=5,
                label="Results Limit"
            )

    with gr.Row():
        country_dropdown = gr.Dropdown(
            choices=["US", "GB", "CA", "AU", "DE", "FR", "JP", "MX", "BR", "IN"],
            value="US",
            label="Country"
        )
        genre_dropdown = gr.Dropdown(
            choices=["All Genres"] + get_available_genres(),
            value="All Genres",
            label="Genre Filter"
        )

    search_btn = gr.Button("🔍 Search Podcasts", variant="primary")

    with gr.Row():
        with gr.Column():
            results_display = gr.Markdown(label="Search Results")
        with gr.Column():
            json_output = gr.Code(
                label="JSON Output (for Swift integration)",
                language="json",
                lines=15
            )

    gr.Markdown("---")
    gr.Markdown("### Create Shortlist")

    with gr.Row():
        indices_input = gr.Textbox(
            label="Select podcasts by number",
            placeholder="e.g., 1, 3, 5 or 1-3, 5",
            lines=1
        )
        shortlist_btn = gr.Button("📋 Create Shortlist")

    shortlist_output = gr.Code(
        label="Shortlist JSON (copy for Swift app)",
        language="json",
        lines=10
    )

    # Event handlers
    search_btn.click(
        fn=search_and_display,
        inputs=[query_input, limit_slider, country_dropdown, genre_dropdown],
        outputs=[results_display, json_output]
    )

    query_input.submit(
        fn=search_and_display,
        inputs=[query_input, limit_slider, country_dropdown, genre_dropdown],
        outputs=[results_display, json_output]
    )

    shortlist_btn.click(
        fn=create_shortlist,
        inputs=[json_output, indices_input],
        outputs=[shortlist_output]
    )

    gr.Markdown("""
    ---
    ### Swift Integration

    Copy the JSON output and use it in your Swift app with `Codable`:

    ```swift
    struct Podcast: Codable {
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
    """)

# For API access
def api_search(query: str, limit: int = 10, country: str = "US", genre: str = None) -> Dict:
    """Direct API function for programmatic access"""
    podcasts = search_podcasts(query, limit, country, genre)
    return {
        "count": len(podcasts),
        "podcasts": [p.to_dict() for p in podcasts]
    }

if __name__ == "__main__":
    app.launch(
        server_name="0.0.0.0",
        server_port=7860,
        share=False
    )
