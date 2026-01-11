"""
Persona Database Operations
Handles storage and retrieval of AI-generated personas

Architecture: Gutsy Startup - raw SQL, no ORM
Database: rsgmusicchat_gold.personas
"""

import json
from typing import Optional, Dict, Any
from config import get_db_cursor, DB_NAME_GOLD
import logging

logger = logging.getLogger(__name__)


def save_persona(
    session_id: str,
    hex_colors: list,
    persona_json: dict,
    pixelated_image_data: Optional[str] = None
) -> int:
    """
    Save generated persona to database with upsert logic

    Uses ON DUPLICATE KEY UPDATE to handle re-generation:
    - If session_id exists: Update with new persona
    - If session_id new: Insert new record

    Args:
        session_id: Unique session identifier (from cookie, 32-64 chars)
        hex_colors: List of 3 hex color codes ["#FF0000", "#00FF00", "#0000FF"]
        persona_json: Full persona object from Gemini (validated against schema)
        pixelated_image_data: Optional base64 encoded image (data:image/png;base64,...)

    Returns:
        int: Inserted/updated persona ID

    Raises:
        Exception: If database operation fails

    Example:
        >>> persona_id = save_persona(
        ...     session_id="abc123def456",
        ...     hex_colors=["#FF0000", "#00FF00", "#0000FF"],
        ...     persona_json={"module": "neo_y2k", "metadata": {...}},
        ...     pixelated_image_data="data:image/png;base64,iVBOR..."
        ... )
        >>> print(persona_id)
        42
    """
    query = """
    INSERT INTO personas (session_id, hex_colors, persona_json, pixelated_image_data)
    VALUES (%s, %s, %s, %s)
    ON DUPLICATE KEY UPDATE
        hex_colors = VALUES(hex_colors),
        persona_json = VALUES(persona_json),
        pixelated_image_data = VALUES(pixelated_image_data),
        last_accessed_at = CURRENT_TIMESTAMP
    """

    try:
        with get_db_cursor(DB_NAME_GOLD) as cursor:
            cursor.execute(query, (
                session_id,
                json.dumps(hex_colors),  # Convert list to JSON string
                json.dumps(persona_json),  # Convert dict to JSON string
                pixelated_image_data
            ))

            # Get the inserted/updated ID
            # For INSERT: cursor.lastrowid is the new ID
            # For UPDATE: cursor.lastrowid is 0, so we need to SELECT
            if cursor.lastrowid > 0:
                persona_id = cursor.lastrowid
            else:
                # Was an update, fetch the existing ID
                cursor.execute("SELECT id FROM personas WHERE session_id = %s", (session_id,))
                row = cursor.fetchone()
                persona_id = row['id'] if row else 0

            logger.info("[DB] ✓ Saved persona (ID: %s, session: %s...)", persona_id, session_id[:8])
            return persona_id

    except Exception as e:
        logger.exception("[DB] ✗ Error saving persona")
        raise


def retrieve_persona_by_session(session_id: str) -> Optional[Dict[str, Any]]:
    """
    Retrieve persona by session ID

    Args:
        session_id: Session identifier to look up

    Returns:
        Dict with persona data or None if not found
        {
            "id": 42,
            "session_id": "abc123def456",
            "hex_colors": ["#FF0000", "#00FF00", "#0000FF"],
            "persona_json": {"module": "neo_y2k", ...},
            "pixelated_image_data": "data:image/png;base64,...",
            "created_at": "2026-01-10T14:30:00"
        }

    Example:
        >>> persona = retrieve_persona_by_session("abc123def456")
        >>> if persona:
        ...     print(persona["persona_json"]["metadata"]["alias"])
        "n30ndr34m"
    """
    query = """
    SELECT
        id,
        session_id,
        hex_colors,
        persona_json,
        pixelated_image_data,
        created_at,
        last_accessed_at
    FROM personas
    WHERE session_id = %s
    """

    try:
        logger.info("[DB] Querying persona for session: %s...", session_id[:16])
        with get_db_cursor(DB_NAME_GOLD) as cursor:
            cursor.execute(query, (session_id,))
            row = cursor.fetchone()

            if not row:
                logger.warning("[DB] No persona found for session: %s...", session_id[:16])
                return None

            # Parse JSON columns back to Python objects
            persona_data = {
                "id": row['id'],
                "session_id": row['session_id'],
                "hex_colors": json.loads(row['hex_colors']),  # JSON string → list
                "persona_json": json.loads(row['persona_json']),  # JSON string → dict
                "pixelated_image_data": row['pixelated_image_data'],
                "created_at": row['created_at'].isoformat() if row['created_at'] else None,
                "last_accessed_at": row['last_accessed_at'].isoformat() if row['last_accessed_at'] else None
            }

            logger.info("[DB] ✓ Retrieved persona (ID: %s, alias: %s)", persona_data['id'], persona_data['persona_json']['metadata']['alias'])
            return persona_data

    except json.JSONDecodeError as e:
        logger.exception("[DB] ✗ Error parsing JSON from database")
        return None
    except Exception as e:
        logger.exception("[DB] ✗ Error retrieving persona")
        return None


def get_persona_count() -> int:
    """
    Get total number of personas in database

    Returns:
        int: Total persona count

    Example:
        >>> count = get_persona_count()
        >>> print(f"Total personas: {count}")
        Total personas: 142
    """
    query = "SELECT COUNT(*) FROM personas"

    try:
        with get_db_cursor(DB_NAME_GOLD) as cursor:
            cursor.execute(query)
            row = cursor.fetchone()
            count = row['COUNT(*)'] if row else 0
            return count
    except Exception as e:
        print(f"[DB] ✗ Error counting personas: {e}")
        return 0


def get_recent_personas(limit: int = 10) -> list:
    """
    Get most recently created personas

    Args:
        limit: Maximum number of personas to return (default: 10)

    Returns:
        List of persona dicts (without full image data to save bandwidth)

    Example:
        >>> recent = get_recent_personas(5)
        >>> for p in recent:
        ...     print(f"{p['persona_json']['metadata']['alias']} - {p['created_at']}")
    """
    query = """
    SELECT
        id,
        session_id,
        hex_colors,
        persona_json,
        created_at
    FROM personas
    ORDER BY created_at DESC
    LIMIT %s
    """

    try:
        with get_db_cursor(DB_NAME_GOLD) as cursor:
            cursor.execute(query, (limit,))
            rows = cursor.fetchall()

            personas = []
            for row in rows:
                personas.append({
                    "id": row['id'],
                    "session_id": row['session_id'],
                    "hex_colors": json.loads(row['hex_colors']),
                    "persona_json": json.loads(row['persona_json']),
                    "created_at": row['created_at'].isoformat() if row['created_at'] else None
                })

            return personas

    except Exception as e:
        print(f"[DB] ✗ Error fetching recent personas: {e}")
        return []


# ============================================================================
# Testing/Development
# ============================================================================

if __name__ == "__main__":
    # Test database operations
    print("Testing persona database operations...\n")

    # Test save
    test_session = "test_session_12345"
    test_colors = ["#FF5733", "#33FF57", "#3357FF"]
    test_persona = {
        "module": "neo_y2k",
        "metadata": {
            "alias": "t3stdr34m",
            "aura": 75,
            "alignment": "chaotic neutral",
            "bio": "A test persona for development."
        },
        "visuals": {
            "bg_color": "#1a1a1a",
            "accent_color": "#00ff00",
            "font_type": "monospace",
            "border_style": "dotted 3px"
        },
        "audio": {
            "prompt": "Test music prompt",
            "tempo": 120,
            "vibe_weight": 0.5
        }
    }

    try:
        persona_id = save_persona(test_session, test_colors, test_persona)
        print(f"Saved test persona with ID: {persona_id}\n")

        # Test retrieve
        retrieved = retrieve_persona_by_session(test_session)
        if retrieved:
            print("Retrieved persona:")
            print(f"  Alias: {retrieved['persona_json']['metadata']['alias']}")
            print(f"  Colors: {retrieved['hex_colors']}")
            print(f"  Created: {retrieved['created_at']}\n")

        # Test count
        count = get_persona_count()
        print(f"Total personas in DB: {count}\n")

        # Test recent
        recent = get_recent_personas(3)
        print(f"Recent personas ({len(recent)}):")
        for p in recent:
            print(f"  - {p['persona_json']['metadata']['alias']} ({p['created_at']})")

    except Exception as e:
        print(f"Test failed: {e}")
