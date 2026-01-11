-- ============================================================================
-- r/sgmusicchat - TEST DATA AND VALIDATION
-- Purpose: Validate schema, WAP workflow, idempotency, search, and TTL purge
-- Usage: Run after all schema files (01-05) have been executed
-- ============================================================================

USE rsgmusicchat_silver;

-- ============================================================================
-- TEST DATA: Dimension Tables
-- ============================================================================

-- Test Venues (3 venues representing different venue types)
INSERT INTO dim_venues (venue_name, venue_slug, address, postal_code, google_maps_url, capacity, venue_type) VALUES
    ('Test Club Techno', 'test-club-techno', '123 Club Street', '069470', 'https://maps.google.com/?q=test-club-techno', 500, 'club'),
    ('Test Bar House', 'test-bar-house', '456 Bar Avenue', '068898', 'https://maps.google.com/?q=test-bar-house', 150, 'bar'),
    ('Test Outdoor Arena', 'test-outdoor-arena', '789 Marina Bay', '018956', 'https://maps.google.com/?q=test-outdoor-arena', 2000, 'outdoor');

-- Test Artists (5 artists for lineup testing)
INSERT INTO dim_artists (artist_name, artist_slug, bio, spotify_url, instagram_handle) VALUES
    ('DJ Test Alpha', 'dj-test-alpha', 'Pioneering techno artist', 'https://spotify.com/artist/test-alpha', '@dj_test_alpha'),
    ('Producer Beta', 'producer-beta', 'Deep house specialist', 'https://spotify.com/artist/producer-beta', '@producer_beta'),
    ('Amelie Lens Test', 'amelie-lens-test', 'Test version of famous DJ', 'https://spotify.com/artist/amelie-test', '@amelie_test'),
    ('Charlotte De Witte Test', 'charlotte-de-witte-test', 'Techno queen test', 'https://spotify.com/artist/charlotte-test', '@charlotte_test'),
    ('Carl Cox Test', 'carl-cox-test', 'Legendary DJ test', 'https://spotify.com/artist/carl-test', '@carl_test');

-- Genres already pre-populated in 02_silver_layer.sql

-- ============================================================================
-- TEST SCENARIO 1: Happy Path (Valid event with all fields)
-- ============================================================================

CALL sp_upsert_event(
    1,                                          -- venue_id (Test Club Techno)
    DATE_ADD(CURDATE(), INTERVAL 3 DAY),       -- event_date (3 days from now)
    'Techno Tuesday - Test Event',             -- event_name
    '22:00:00',                                -- start_time
    '04:00:00',                                -- end_time
    20.00,                                     -- price_min
    30.00,                                     -- price_max
    FALSE,                                     -- is_free
    'Weekly techno night featuring local DJs', -- description
    '21+',                                     -- age_restriction
    'https://example.com/tickets/techno-tuesday', -- ticket_url
    'admin_manual',                            -- source_type
    NULL,                                      -- source_id
    @event1_id,
    @event1_is_new
);

-- Add genres to event
INSERT INTO event_genres (event_id, genre_id, is_primary) VALUES
    (@event1_id, 1, TRUE),  -- Techno (primary)
    (@event1_id, 6, FALSE); -- Electro (secondary)

-- Add artists to event
INSERT INTO event_artists (event_id, artist_id, performance_order, is_headliner) VALUES
    (@event1_id, 1, 1, TRUE),  -- DJ Test Alpha (headliner)
    (@event1_id, 2, 2, FALSE); -- Producer Beta (support)

-- ============================================================================
-- TEST SCENARIO 2: Idempotency Test (Duplicate event - should UPDATE)
-- ============================================================================

CALL sp_upsert_event(
    1,                                          -- Same venue_id
    DATE_ADD(CURDATE(), INTERVAL 3 DAY),       -- Same event_date
    'Techno Tuesday - UPDATED TITLE',          -- Updated event_name
    '22:00:00',                                -- Same start_time (uid will match)
    '04:00:00',
    15.00,                                     -- Updated price_min
    25.00,                                     -- Updated price_max
    FALSE,
    'UPDATED description',
    '18+',                                     -- Updated age_restriction
    'https://example.com/tickets/techno-tuesday-updated',
    'admin_manual',
    NULL,
    @event2_id,
    @event2_is_new
);

-- Validation: event2_id should equal event1_id, and is_new should be FALSE
-- SELECT @event1_id AS first_insert_id, @event2_id AS second_insert_id,
--        @event1_is_new AS first_is_new, @event2_is_new AS second_is_new;
-- Expected: first_is_new=1, second_is_new=0, same event_id

-- ============================================================================
-- TEST SCENARIO 3: Free Event (is_free = TRUE with NULL prices)
-- ============================================================================

CALL sp_upsert_event(
    2,                                          -- venue_id (Test Bar House)
    DATE_ADD(CURDATE(), INTERVAL 5 DAY),       -- event_date
    'Free House Music Night',                  -- event_name
    '20:00:00',
    '02:00:00',
    NULL,                                      -- price_min (NULL for free)
    NULL,                                      -- price_max (NULL for free)
    TRUE,                                      -- is_free
    'Free entry all night!',
    'all_ages',
    NULL,
    'user_submission',
    NULL,
    @event3_id,
    @event3_is_new
);

INSERT INTO event_genres (event_id, genre_id, is_primary) VALUES
    (@event3_id, 2, TRUE); -- House

-- ============================================================================
-- TEST SCENARIO 4: Multi-Genre Event (3 genres)
-- ============================================================================

CALL sp_upsert_event(
    3,                                          -- venue_id (Test Outdoor Arena)
    DATE_ADD(CURDATE(), INTERVAL 7 DAY),       -- event_date
    'Massive Electronic Music Festival',       -- event_name
    '14:00:00',
    '23:00:00',
    50.00,
    100.00,
    FALSE,
    'All-day music festival with multiple stages',
    '18+',
    'https://example.com/tickets/massive-festival',
    'scraper',
    12345,
    @event4_id,
    @event4_is_new
);

-- Add 3 genres
INSERT INTO event_genres (event_id, genre_id, is_primary) VALUES
    (@event4_id, 1, TRUE),   -- Techno (primary)
    (@event4_id, 2, FALSE),  -- House
    (@event4_id, 4, FALSE);  -- Drum and Bass

-- Add 4 artists (lineup)
INSERT INTO event_artists (event_id, artist_id, performance_order, is_headliner) VALUES
    (@event4_id, 3, 1, TRUE),  -- Amelie Lens Test (headliner)
    (@event4_id, 4, 2, TRUE),  -- Charlotte De Witte Test (co-headliner)
    (@event4_id, 5, 3, FALSE), -- Carl Cox Test (support)
    (@event4_id, 1, 4, FALSE); -- DJ Test Alpha (opening)

-- ============================================================================
-- TEST SCENARIO 5: Boolean Search Test - Pure Techno Event
-- ============================================================================

CALL sp_upsert_event(
    1,
    DATE_ADD(CURDATE(), INTERVAL 10 DAY),
    'Pure Techno Night',
    '23:00:00',
    '05:00:00',
    25.00,
    35.00,
    FALSE,
    'Hard techno only, no House allowed',
    '21+',
    'https://example.com/tickets/pure-techno',
    'admin_manual',
    NULL,
    @event5_id,
    @event5_is_new
);

INSERT INTO event_genres (event_id, genre_id, is_primary) VALUES
    (@event5_id, 1, TRUE); -- Techno only

-- ============================================================================
-- TEST SCENARIO 6: Boolean Search Test - Pure House Event
-- ============================================================================

CALL sp_upsert_event(
    2,
    DATE_ADD(CURDATE(), INTERVAL 12 DAY),
    'Deep House Vibes',
    '21:00:00',
    '03:00:00',
    15.00,
    20.00,
    FALSE,
    'Smooth house music all night',
    '18+',
    'https://example.com/tickets/deep-house',
    'admin_manual',
    NULL,
    @event6_id,
    @event6_is_new
);

INSERT INTO event_genres (event_id, genre_id, is_primary) VALUES
    (@event6_id, 2, TRUE); -- House only

-- ============================================================================
-- TEST SCENARIO 7: Past Date Violation (should fail audit)
-- ============================================================================

CALL sp_upsert_event(
    1,
    DATE_SUB(CURDATE(), INTERVAL 5 DAY),       -- Past date
    'Past Event - Should Be Rejected',
    '22:00:00',
    '04:00:00',
    20.00,
    30.00,
    FALSE,
    'This event is in the past',
    '21+',
    NULL,
    'admin_manual',
    NULL,
    @event7_id,
    @event7_is_new
);

INSERT INTO event_genres (event_id, genre_id, is_primary) VALUES
    (@event7_id, 1, TRUE);

-- ============================================================================
-- TEST SCENARIO 8: Old Event for TTL Purge Test (8 days ago)
-- ============================================================================

CALL sp_upsert_event(
    2,
    DATE_SUB(CURDATE(), INTERVAL 8 DAY),
    'Old Event - Should Be Purged',
    '20:00:00',
    '02:00:00',
    10.00,
    15.00,
    FALSE,
    'Event from 8 days ago',
    'all_ages',
    NULL,
    'admin_manual',
    NULL,
    @event8_id,
    @event8_is_new
);

INSERT INTO event_genres (event_id, genre_id, is_primary) VALUES
    (@event8_id, 2, TRUE);

-- ============================================================================
-- VALIDATION TESTS
-- ============================================================================

-- ============================================================================
-- Test 1: Verify Idempotency (Duplicate Prevention)
-- ============================================================================

SELECT
    COUNT(*) AS total_events,
    COUNT(DISTINCT uid) AS unique_uids
FROM silver_events;
-- Expected: total_events = unique_uids (no duplicates)

SELECT
    COUNT(*) AS duplicate_count
FROM (
    SELECT uid, COUNT(*) AS cnt
    FROM silver_events
    GROUP BY uid
    HAVING cnt > 1
) AS duplicates;
-- Expected: 0

-- ============================================================================
-- Test 2: Run Audit on Pending Events
-- ============================================================================

CALL sp_audit_pending_events(@errors, @summary);
SELECT @errors AS error_count, @summary AS error_details;
-- Expected: error_count >= 1 (past dates violation)

-- ============================================================================
-- Test 3: Publish to Gold (only future events should be published)
-- ============================================================================

CALL sp_publish_to_gold(100, @published, @msg);
SELECT @published AS published_count, @msg AS result_message;
-- Expected: published_count = number of future events

-- ============================================================================
-- Test 4: Verify Gold Layer Denormalization
-- ============================================================================

SELECT
    event_name,
    venue_name,
    genres_concat,
    artists_concat,
    event_date
FROM rsgmusicchat_gold.v_live_events
ORDER BY event_date ASC;
-- Expected: See denormalized genres and artists

-- ============================================================================
-- Test 5: Boolean Search - Find Techno, exclude House
-- ============================================================================

SELECT
    event_name,
    genres_concat,
    MATCH(genres_fulltext) AGAINST('+Techno -House' IN BOOLEAN MODE) AS relevance_score
FROM rsgmusicchat_gold.v_live_events
WHERE MATCH(genres_fulltext) AGAINST('+Techno -House' IN BOOLEAN MODE)
ORDER BY relevance_score DESC;
-- Expected: "Pure Techno Night" appears, "Deep House Vibes" does NOT appear

-- ============================================================================
-- Test 6: Boolean Search Performance Test
-- ============================================================================

SET profiling = 1;

SELECT
    event_id,
    event_name,
    venue_name,
    genres_concat
FROM rsgmusicchat_gold.v_live_events
WHERE
    event_date >= CURDATE()
    AND MATCH(event_name, genres_fulltext, artists_fulltext, search_tags)
        AGAINST('+Amelie' IN BOOLEAN MODE)
ORDER BY event_date ASC;

SHOW PROFILES;
-- Expected: Query time < 150ms

SET profiling = 0;

-- ============================================================================
-- Test 7: Manual TTL Purge (delete events older than 7 days)
-- ============================================================================

USE rsgmusicchat_gold;

CALL sp_manual_purge_gold(7, @deleted);
SELECT @deleted AS events_purged;
-- Expected: @deleted >= 1 (should delete event8 which is 8 days old)

-- ============================================================================
-- Test 8: Verify Only Upcoming Events Remain in Gold
-- ============================================================================

SELECT
    MIN(event_date) AS earliest_event,
    MAX(event_date) AS latest_event,
    COUNT(*) AS total_events,
    DATEDIFF(MIN(event_date), CURDATE()) AS days_from_now_min
FROM rsgmusicchat_gold.v_live_events;
-- Expected: days_from_now_min >= -7 (within 7-day window)

-- ============================================================================
-- Test 9: Check WAP Audit Log
-- ============================================================================

USE rsgmusicchat_silver;

SELECT
    procedure_name,
    events_processed,
    events_published,
    error_count,
    error_summary,
    execution_time_ms,
    status,
    execution_timestamp
FROM wap_audit_log
ORDER BY execution_timestamp DESC;
-- Expected: See log entries for sp_audit_pending_events, sp_publish_to_gold

-- ============================================================================
-- Test 10: Check Gold Purge Log
-- ============================================================================

USE rsgmusicchat_gold;

SELECT
    purge_date,
    threshold_date,
    rows_deleted,
    execution_time_ms,
    purge_type
FROM gold_purge_log
ORDER BY purge_date DESC;
-- Expected: See manual purge entry

-- ============================================================================
-- Test 11: Verify VIEW Swap (Zero-Downtime Rebuild)
-- ============================================================================

USE rsgmusicchat_silver;

-- Check current event count
SELECT COUNT(*) AS events_before_rebuild FROM rsgmusicchat_gold.v_live_events;

-- Execute rebuild
CALL sp_rebuild_gold_from_silver();

-- Check event count after rebuild (should be same)
SELECT COUNT(*) AS events_after_rebuild FROM rsgmusicchat_gold.v_live_events;
-- Expected: events_before_rebuild = events_after_rebuild

-- Verify VIEW definition changed
SELECT VIEW_DEFINITION
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'rsgmusicchat_gold'
    AND TABLE_NAME = 'v_live_events';
-- Expected: VIEW points to one of the gold tables

-- ============================================================================
-- SUMMARY VALIDATION QUERIES
-- ============================================================================

-- Final status check: Silver events by status
SELECT
    status,
    COUNT(*) AS event_count,
    MIN(event_date) AS earliest_date,
    MAX(event_date) AS latest_date
FROM rsgmusicchat_silver.silver_events
GROUP BY status;

-- Final status check: Gold events count
SELECT COUNT(*) AS gold_events FROM rsgmusicchat_gold.v_live_events;

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. All tests validate core requirements: idempotency, WAP workflow, search, TTL
-- 2. Test scenarios include edge cases: past dates, free events, multi-genre
-- 3. Boolean search tests verify FULLTEXT indexes work correctly
-- 4. Purge tests validate 7-day TTL enforcement
-- 5. VIEW swap test validates zero-downtime rebuild capability
-- ============================================================================
