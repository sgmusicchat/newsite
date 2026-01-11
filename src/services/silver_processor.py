"""
Silver Processor Service
Purpose: Transform Bronze → Silver via sp_upsert_event stored procedure
Ensures idempotency via uid (MD5 hash)
"""

import json
from typing import Dict, List, Tuple
from config import get_db_cursor, DB_NAME_BRONZE, DB_NAME_SILVER


def process_bronze_to_silver(bronze_id: int, scraper_source: str = "scraper") -> Tuple[int, int]:
    """
    Transform Bronze raw data to Silver layer via sp_upsert_event

    Args:
        bronze_id: Bronze record ID to process
        scraper_source: Source type ('scraper', 'user_submission', 'admin_manual')

    Returns:
        Tuple of (events_processed, new_events_created)
    """
    # Step 1: Fetch Bronze raw data
    with get_db_cursor(DB_NAME_BRONZE) as cursor:
        sql = """
            SELECT raw_payload FROM bronze_scraper_raw WHERE id = %s
        """
        cursor.execute(sql, (bronze_id,))
        result = cursor.fetchone()

        if not result:
            raise ValueError(f"Bronze record {bronze_id} not found")

        raw_payload = json.loads(result['raw_payload'])

    # Step 2: Transform each event to Silver via sp_upsert_event
    events_processed = 0
    new_events = 0

    with get_db_cursor(DB_NAME_SILVER) as cursor:
        for event in raw_payload:
            # Call sp_upsert_event stored procedure
            sql = """
                CALL sp_upsert_event(
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    @event_id, @is_new
                )
            """

            params = (
                event.get('venue_id'),
                event.get('event_date'),
                event.get('event_name'),
                event.get('start_time'),
                event.get('end_time'),
                event.get('price_min'),
                event.get('price_max'),
                event.get('is_free', False),
                event.get('description'),
                event.get('age_restriction', 'all_ages'),
                event.get('ticket_url'),
                scraper_source,
                bronze_id
            )

            cursor.execute(sql, params)

            # Get output parameters
            cursor.execute("SELECT @event_id AS event_id, @is_new AS is_new")
            result = cursor.fetchone()

            event_id = result['event_id']
            is_new = result['is_new']

            events_processed += 1
            if is_new:
                new_events += 1

            # Insert genre relationships if present
            if 'genre_ids' in event and event['genre_ids']:
                insert_genre_relationships(cursor, event_id, event['genre_ids'])

            # Insert artist relationships if present
            if 'artist_ids' in event and event['artist_ids']:
                insert_artist_relationships(cursor, event_id, event['artist_ids'])

            action = "CREATED" if is_new else "UPDATED"
            print(f"  {action} event_id={event_id}: {event.get('event_name')}")

    print(f"✅ Processed {events_processed} events from Bronze → Silver (new={new_events}, updated={events_processed - new_events})")

    return (events_processed, new_events)


def insert_genre_relationships(cursor, event_id: int, genre_ids: List[int]):
    """
    Insert event-genre relationships

    Args:
        cursor: Database cursor
        event_id: Silver event ID
        genre_ids: List of genre IDs
    """
    # Delete existing relationships
    cursor.execute("DELETE FROM event_genres WHERE event_id = %s", (event_id,))

    # Insert new relationships
    for idx, genre_id in enumerate(genre_ids):
        is_primary = (idx == 0)  # First genre is primary
        sql = """
            INSERT INTO event_genres (event_id, genre_id, is_primary)
            VALUES (%s, %s, %s)
        """
        cursor.execute(sql, (event_id, genre_id, is_primary))


def insert_artist_relationships(cursor, event_id: int, artist_ids: List[int]):
    """
    Insert event-artist relationships (lineup)

    Args:
        cursor: Database cursor
        event_id: Silver event ID
        artist_ids: List of artist IDs
    """
    # Delete existing relationships
    cursor.execute("DELETE FROM event_artists WHERE event_id = %s", (event_id,))

    # Insert new relationships
    for idx, artist_id in enumerate(artist_ids):
        performance_order = idx + 1
        is_headliner = (idx == 0)  # First artist is headliner
        sql = """
            INSERT INTO event_artists (event_id, artist_id, performance_order, is_headliner)
            VALUES (%s, %s, %s, %s)
        """
        cursor.execute(sql, (event_id, artist_id, performance_order, is_headliner))


if __name__ == "__main__":
    # Test Silver processor
    from scrapers.mock_scraper import generate_mock_events
    from services.bronze_writer import write_to_bronze

    print("Testing Silver Processor...")

    # Generate mock events
    mock_events = generate_mock_events(count=2)

    # Write to Bronze
    bronze_id = write_to_bronze(mock_events, scraper_source="mock_scraper")

    # Process Bronze → Silver
    processed, new = process_bronze_to_silver(bronze_id, scraper_source="scraper")

    print(f"\nResult: {processed} processed, {new} new events created")
