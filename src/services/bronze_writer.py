"""
Bronze Writer Service
Purpose: Write raw scraper data to Bronze layer (immutable audit trail)
"""

import json
from datetime import datetime
from typing import Dict, List
from config import get_db_cursor, DB_NAME_BRONZE


def write_to_bronze(events: List[Dict], scraper_source: str = "mock_scraper") -> int:
    """
    Write raw event data to Bronze layer

    Args:
        events: List of raw event dictionaries
        scraper_source: Name of scraper (e.g., 'mock_scraper', 'facebook', 'eventbrite')

    Returns:
        Bronze record ID (last inserted ID)
    """
    with get_db_cursor(DB_NAME_BRONZE) as cursor:
        sql = """
            INSERT INTO bronze_scraper_raw
            (scraper_source, scraped_at, raw_payload, scraper_version)
            VALUES (%s, NOW(), %s, %s)
        """

        # Bundle all events into single Bronze record (typical scraper pattern)
        raw_payload = json.dumps(events, indent=2)
        scraper_version = events[0].get("scraper_version", "v1.0.0") if events else "v1.0.0"

        cursor.execute(sql, (scraper_source, raw_payload, scraper_version))

        bronze_id = cursor.lastrowid

        print(f"✅ Written {len(events)} events to Bronze layer (bronze_id={bronze_id})")

        return bronze_id


def write_user_submission_to_bronze(form_data: Dict, submission_ip: str) -> int:
    """
    Write visitor form submission to Bronze layer

    Args:
        form_data: Raw form submission data
        submission_ip: IP address of submitter

    Returns:
        Bronze submission ID
    """
    with get_db_cursor(DB_NAME_BRONZE) as cursor:
        sql = """
            INSERT INTO bronze_user_submissions
            (submitted_at, submission_ip, raw_form_data, user_agent)
            VALUES (NOW(), %s, %s, %s)
        """

        raw_form_data = json.dumps(form_data, indent=2)
        user_agent = form_data.get("user_agent", "Unknown")

        cursor.execute(sql, (submission_ip, raw_form_data, user_agent))

        bronze_id = cursor.lastrowid

        print(f"✅ User submission written to Bronze (bronze_id={bronze_id})")

        return bronze_id


def write_admin_edit_to_bronze(admin_username: str, edit_type: str, edit_data: Dict) -> int:
    """
    Write admin manual edit to Bronze layer

    Args:
        admin_username: Username of admin
        edit_type: Type of edit ('create', 'update', 'delete')
        edit_data: Raw edit data

    Returns:
        Bronze edit ID
    """
    with get_db_cursor(DB_NAME_BRONZE) as cursor:
        sql = """
            INSERT INTO bronze_admin_edits
            (edited_at, admin_username, edit_type, raw_edit_data)
            VALUES (NOW(), %s, %s, %s)
        """

        raw_edit_data = json.dumps(edit_data, indent=2)

        cursor.execute(sql, (admin_username, edit_type, raw_edit_data))

        bronze_id = cursor.lastrowid

        print(f"✅ Admin edit written to Bronze (bronze_id={bronze_id}, type={edit_type})")

        return bronze_id


if __name__ == "__main__":
    # Test Bronze writer
    from scrapers.mock_scraper import generate_mock_events

    print("Testing Bronze Writer...")
    mock_events = generate_mock_events(count=3)
    bronze_id = write_to_bronze(mock_events, scraper_source="mock_scraper")
    print(f"Bronze ID: {bronze_id}")
