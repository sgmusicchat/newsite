"""
Mock Scraper for r/sgmusicchat
Purpose: Generate random events for testing without external API dependencies
"""

import json
import random
from datetime import datetime, timedelta
from typing import List, Dict

# Mock data pools
VENUE_IDS = list(range(1, 11))  # Assuming 10 venues exist in dim_venues

EVENT_NAMES = [
    "Techno Night @ {venue}",
    "House Music Festival",
    "Underground Beats",
    "Electronic Sunset Sessions",
    "Bass & Breaks",
    "Ambient Soundscapes",
    "Trance Journey",
    "Deep House Sessions",
    "Drum & Bass Takeover",
    "Minimal Techno Showcase"
]

GENRE_IDS = list(range(1, 12))  # Assuming 11 genres in dim_genres (1-11)

ARTIST_IDS = list(range(1, 21))  # Assuming 20 artists exist


def generate_mock_events(count: int = 10) -> List[Dict]:
    """
    Generate mock event data for testing

    Args:
        count: Number of mock events to generate

    Returns:
        List of event dictionaries with raw scraper format
    """
    events = []
    now = datetime.now()

    for i in range(count):
        # Generate random future date (next 7-30 days)
        days_ahead = random.randint(1, 30)
        event_date = (now + timedelta(days=days_ahead)).date()

        # Generate random start time (18:00 - 23:00)
        start_hour = random.randint(18, 23)
        start_time = f"{start_hour:02d}:00:00"

        # End time 3-5 hours later
        end_hour = min(start_hour + random.randint(3, 5), 27)  # Allow next day
        if end_hour >= 24:
            end_hour_formatted = end_hour - 24
        else:
            end_hour_formatted = end_hour
        end_time = f"{end_hour_formatted:02d}:00:00"

        # Random pricing
        is_free = random.random() < 0.2  # 20% chance of free event
        if is_free:
            price_min = None
            price_max = None
        else:
            price_min = random.choice([10, 15, 20, 25, 30])
            price_max = price_min + random.choice([0, 10, 20])

        # Random venue
        venue_id = random.choice(VENUE_IDS)

        # Random event name
        event_name = random.choice(EVENT_NAMES).format(venue=f"Venue{venue_id}")

        # Random genres (1-3 genres per event)
        num_genres = random.randint(1, 3)
        genre_ids = random.sample(GENRE_IDS, num_genres)

        # Random artists (1-4 artists per event)
        num_artists = random.randint(1, 4)
        artist_ids = random.sample(ARTIST_IDS, min(num_artists, len(ARTIST_IDS)))

        # Build event object
        event = {
            "venue_id": venue_id,
            "event_date": str(event_date),
            "event_name": event_name,
            "start_time": start_time,
            "end_time": end_time,
            "price_min": price_min,
            "price_max": price_max,
            "is_free": is_free,
            "description": f"Mock event {i+1} for testing purposes. Join us for an amazing night of electronic music!",
            "age_restriction": random.choice(["all_ages", "18+", "21+"]),
            "ticket_url": f"https://example.com/tickets/event-{i+1}" if not is_free else None,
            "event_url": f"https://example.com/events/event-{i+1}",
            "fb_event_url": f"https://facebook.com/events/{random.randint(100000, 999999)}",
            "image_url": f"https://picsum.photos/seed/event{i+1}/800/600",
            "genre_ids": genre_ids,
            "artist_ids": artist_ids,
            "scraped_at": now.isoformat(),
            "scraper_version": "mock_v1.0.0"
        }

        events.append(event)

    return events


def generate_bad_event_for_quarantine_testing() -> Dict:
    """
    Generate intentionally bad event data for testing quarantine logic

    Returns:
        Event dictionary with data quality issues
    """
    bad_types = [
        # Past date (should be auto-quarantined)
        {
            "venue_id": 1,
            "event_date": "2025-01-01",  # Past date
            "event_name": "Past Event (Should Be Quarantined)",
            "start_time": "20:00:00",
            "end_time": "23:00:00",
            "is_free": False,
            "price_min": 20,
        },
        # Temporal violation (end_time < start_time)
        {
            "venue_id": 1,
            "event_date": str((datetime.now() + timedelta(days=5)).date()),
            "event_name": "Temporal Violation (Should Be Quarantined)",
            "start_time": "23:00:00",
            "end_time": "20:00:00",  # End before start
            "is_free": False,
            "price_min": 20,
        },
        # Extreme future date (>6 months)
        {
            "venue_id": 1,
            "event_date": str((datetime.now() + timedelta(days=200)).date()),
            "event_name": "Too Far Future (Should Be Quarantined)",
            "start_time": "20:00:00",
            "end_time": "23:00:00",
            "is_free": False,
            "price_min": 20,
        },
        # Free event with price (price logic violation)
        {
            "venue_id": 1,
            "event_date": str((datetime.now() + timedelta(days=5)).date()),
            "event_name": "Free Event With Price (Should Be Quarantined)",
            "start_time": "20:00:00",
            "end_time": "23:00:00",
            "is_free": True,  # Marked as free
            "price_min": 20,  # But has price!
        }
    ]

    return random.choice(bad_types)


if __name__ == "__main__":
    # Test mock scraper
    print("Generating 5 mock events:")
    events = generate_mock_events(5)
    for event in events:
        print(json.dumps(event, indent=2))

    print("\nGenerating 1 bad event for quarantine testing:")
    bad_event = generate_bad_event_for_quarantine_testing()
    print(json.dumps(bad_event, indent=2))
