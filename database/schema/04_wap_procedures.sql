-- ============================================================================
-- r/sgmusicchat - WAP (WRITE-AUDIT-PUBLISH) PROCEDURES
-- Purpose: Data quality validation and Silver → Gold promotion
-- Pattern: pending → audit → published → Gold
-- Components: 1 audit log table + 5 stored procedures
-- ============================================================================

USE rsgmusicchat_silver;

-- ============================================================================
-- WAP AUDIT LOG TABLE
-- Purpose: Track all WAP workflow executions for debugging and compliance
-- ============================================================================

CREATE TABLE wap_audit_log (
    log_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    execution_timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    procedure_name VARCHAR(100) NOT NULL COMMENT 'Which procedure was executed',
    batch_size INT DEFAULT NULL,
    events_processed INT DEFAULT 0,
    events_published INT DEFAULT 0,
    events_rejected INT DEFAULT 0,
    error_count INT DEFAULT 0,
    error_summary TEXT DEFAULT NULL COMMENT 'Detailed error messages',
    execution_time_ms INT UNSIGNED DEFAULT NULL COMMENT 'Performance tracking',
    status ENUM('success', 'partial_success', 'failed') NOT NULL,
    executed_by VARCHAR(100) DEFAULT 'system' COMMENT 'Admin username or system',

    PRIMARY KEY (log_id),
    INDEX idx_timestamp (execution_timestamp),
    INDEX idx_procedure (procedure_name, execution_timestamp),
    INDEX idx_status (status)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Audit trail for WAP workflow executions';

-- ============================================================================
-- STORED PROCEDURE: sp_upsert_event
-- Purpose: Idempotent insert/update with duplicate prevention
-- Pattern: INSERT ... ON DUPLICATE KEY UPDATE
-- ============================================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_upsert_event$$

CREATE PROCEDURE sp_upsert_event(
    IN p_venue_id INT UNSIGNED,
    IN p_event_date DATE,
    IN p_event_name VARCHAR(500),
    IN p_start_time TIME,
    IN p_end_time TIME,
    IN p_price_min DECIMAL(8,2),
    IN p_price_max DECIMAL(8,2),
    IN p_is_free BOOLEAN,
    IN p_description TEXT,
    IN p_age_restriction VARCHAR(20),
    IN p_ticket_url VARCHAR(500),
    IN p_source_type VARCHAR(50),
    IN p_source_id BIGINT UNSIGNED,
    OUT p_event_id BIGINT UNSIGNED,
    OUT p_is_new BOOLEAN
)
BEGIN
    DECLARE v_uid VARCHAR(32);
    DECLARE v_existing_id BIGINT UNSIGNED;

    -- Generate deterministic uid: MD5(venue_id || event_date || start_time)
    SET v_uid = MD5(CONCAT(
        CAST(p_venue_id AS CHAR),
        '-',
        CAST(p_event_date AS CHAR),
        '-',
        IFNULL(CAST(p_start_time AS CHAR), '00:00:00')
    ));

    -- Check if uid already exists
    SELECT event_id INTO v_existing_id
    FROM silver_events
    WHERE uid = v_uid
    LIMIT 1;

    -- Idempotent upsert
    INSERT INTO silver_events (
        uid,
        venue_id,
        event_date,
        event_name,
        start_time,
        end_time,
        price_min,
        price_max,
        is_free,
        description,
        age_restriction,
        ticket_url,
        source_type,
        source_id,
        status
    ) VALUES (
        v_uid,
        p_venue_id,
        p_event_date,
        p_event_name,
        p_start_time,
        p_end_time,
        p_price_min,
        p_price_max,
        p_is_free,
        p_description,
        p_age_restriction,
        p_ticket_url,
        p_source_type,
        p_source_id,
        'pending'
    )
    ON DUPLICATE KEY UPDATE
        event_name = VALUES(event_name),
        start_time = VALUES(start_time),
        end_time = VALUES(end_time),
        price_min = VALUES(price_min),
        price_max = VALUES(price_max),
        is_free = VALUES(is_free),
        description = VALUES(description),
        age_restriction = VALUES(age_restriction),
        ticket_url = VALUES(ticket_url),
        updated_at = CURRENT_TIMESTAMP;

    -- Get event_id (whether new or updated)
    IF v_existing_id IS NULL THEN
        SET p_event_id = LAST_INSERT_ID();
        SET p_is_new = TRUE;
    ELSE
        SET p_event_id = v_existing_id;
        SET p_is_new = FALSE;
    END IF;
END$$

-- ============================================================================
-- STORED PROCEDURE: sp_audit_pending_events (AGGRESSIVE REJECTION VERSION)
-- Purpose: Data quality validation with auto-quarantine
-- Binary Success Model: 100% perfect or quarantined
-- Checks: deal-breakers, past dates, referential integrity, temporal logic
-- ============================================================================

DROP PROCEDURE IF EXISTS sp_audit_pending_events$$

CREATE PROCEDURE sp_audit_pending_events(
    OUT p_error_count INT,
    OUT p_quarantined_count INT,
    OUT p_error_summary TEXT
)
BEGIN
    DECLARE v_errors TEXT DEFAULT '';
    DECLARE v_count INT DEFAULT 0;
    DECLARE v_start_time BIGINT;
    DECLARE v_execution_time INT;
    DECLARE v_quarantined_total INT DEFAULT 0;

    SET v_start_time = UNIX_TIMESTAMP(NOW(3)) * 1000;

    -- ========================================================================
    -- AUTO-QUARANTINE: Past dates (ZERO TOLERANCE)
    -- ========================================================================
    UPDATE silver_events
    SET status = 'quarantined',
        rejection_reason = 'Auto-rejected: Event date in the past',
        updated_at = NOW()
    WHERE status = 'pending'
      AND event_date < CURDATE();

    SET v_count = ROW_COUNT();
    IF v_count > 0 THEN
        SET v_errors = CONCAT(v_errors, 'QUARANTINED: ', v_count, ' events with past dates; ');
        SET v_quarantined_total = v_quarantined_total + v_count;
    END IF;

    -- ========================================================================
    -- AUTO-QUARANTINE: Temporal logic violations (end_time < start_time)
    -- ========================================================================
    UPDATE silver_events
    SET status = 'quarantined',
        rejection_reason = 'Auto-rejected: End time before start time',
        updated_at = NOW()
    WHERE status = 'pending'
      AND start_time IS NOT NULL
      AND end_time IS NOT NULL
      AND end_time < start_time;

    SET v_count = ROW_COUNT();
    IF v_count > 0 THEN
        SET v_errors = CONCAT(v_errors, 'QUARANTINED: ', v_count, ' temporal logic violations; ');
        SET v_quarantined_total = v_quarantined_total + v_count;
    END IF;

    -- ========================================================================
    -- AUTO-QUARANTINE: Extreme future dates (>6 months)
    -- ========================================================================
    UPDATE silver_events
    SET status = 'quarantined',
        rejection_reason = 'Auto-rejected: Event date too far in future (>6 months)',
        updated_at = NOW()
    WHERE status = 'pending'
      AND event_date > DATE_ADD(CURDATE(), INTERVAL 6 MONTH);

    SET v_count = ROW_COUNT();
    IF v_count > 0 THEN
        SET v_errors = CONCAT(v_errors, 'QUARANTINED: ', v_count, ' extreme future dates; ');
        SET v_quarantined_total = v_quarantined_total + v_count;
    END IF;

    -- ========================================================================
    -- AUTO-QUARANTINE: Invalid venue_id (orphaned events)
    -- ========================================================================
    UPDATE silver_events se
    LEFT JOIN dim_venues dv ON se.venue_id = dv.venue_id
    SET se.status = 'quarantined',
        se.rejection_reason = 'Auto-rejected: Invalid venue_id (orphaned event)',
        se.updated_at = NOW()
    WHERE se.status = 'pending'
      AND dv.venue_id IS NULL;

    SET v_count = ROW_COUNT();
    IF v_count > 0 THEN
        SET v_errors = CONCAT(v_errors, 'QUARANTINED: ', v_count, ' invalid venue_id; ');
        SET v_quarantined_total = v_quarantined_total + v_count;
    END IF;

    -- ========================================================================
    -- AUTO-QUARANTINE: Price logic violations (free events with prices)
    -- ========================================================================
    UPDATE silver_events
    SET status = 'quarantined',
        rejection_reason = 'Auto-rejected: Free event has price values',
        updated_at = NOW()
    WHERE status = 'pending'
      AND is_free = TRUE
      AND (price_min IS NOT NULL OR price_max IS NOT NULL);

    SET v_count = ROW_COUNT();
    IF v_count > 0 THEN
        SET v_errors = CONCAT(v_errors, 'QUARANTINED: ', v_count, ' free events with prices; ');
        SET v_quarantined_total = v_quarantined_total + v_count;
    END IF;

    -- ========================================================================
    -- CHECK (NO AUTO-FIX): Deal-breaker columns must not be NULL
    -- ========================================================================
    SELECT COUNT(*) INTO v_count
    FROM silver_events
    WHERE status = 'pending'
      AND (venue_id IS NULL OR event_date IS NULL OR event_name IS NULL);

    IF v_count > 0 THEN
        SET v_errors = CONCAT(v_errors, 'ERROR: ', v_count, ' events missing deal-breaker columns; ');
    END IF;

    -- ========================================================================
    -- Calculate results
    -- ========================================================================
    SET p_error_count = (LENGTH(v_errors) - LENGTH(REPLACE(v_errors, 'ERROR:', ''))) / LENGTH('ERROR:');
    SET p_quarantined_count = v_quarantined_total;
    SET p_error_summary = v_errors;

    -- Calculate execution time
    SET v_execution_time = UNIX_TIMESTAMP(NOW(3)) * 1000 - v_start_time;

    -- Log audit execution
    INSERT INTO wap_audit_log (
        procedure_name,
        events_processed,
        events_rejected,
        error_count,
        error_summary,
        execution_time_ms,
        status
    ) VALUES (
        'sp_audit_pending_events',
        0,
        v_quarantined_total,
        p_error_count,
        p_error_summary,
        v_execution_time,
        IF(p_error_count = 0, 'success', 'failed')
    );
END$$

-- ============================================================================
-- STORED PROCEDURE: sp_publish_to_gold
-- Purpose: Atomic Silver → Gold promotion with validation
-- Pattern: Audit → Mark published → Denormalize to Gold → Log
-- ============================================================================

DROP PROCEDURE IF EXISTS sp_publish_to_gold$$

CREATE PROCEDURE sp_publish_to_gold(
    IN p_batch_size INT,
    OUT p_published_count INT,
    OUT p_result_message TEXT
)
BEGIN
    DECLARE v_error_count INT DEFAULT 0;
    DECLARE v_error_summary TEXT DEFAULT '';
    DECLARE v_published INT DEFAULT 0;
    DECLARE v_start_time BIGINT;
    DECLARE v_execution_time INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_published_count = 0;
        SET p_result_message = 'FAILED: Transaction rolled back due to error';

        -- Log failure
        INSERT INTO wap_audit_log (
            procedure_name,
            batch_size,
            events_processed,
            events_published,
            error_count,
            error_summary,
            status
        ) VALUES (
            'sp_publish_to_gold',
            p_batch_size,
            0,
            0,
            1,
            'EXCEPTION: Transaction failed',
            'failed'
        );
    END;

    SET v_start_time = UNIX_TIMESTAMP(NOW(3)) * 1000;

    START TRANSACTION;

    -- Step 1: Run aggressive audit (auto-quarantine bad records)
    CALL sp_audit_pending_events(v_error_count, @quarantined_count, v_error_summary);

    IF v_error_count > 0 THEN
        ROLLBACK;
        SET p_published_count = 0;
        SET p_result_message = CONCAT('AUDIT FAILED: ', v_error_summary);

        -- Log audit failure
        SET v_execution_time = UNIX_TIMESTAMP(NOW(3)) * 1000 - v_start_time;
        INSERT INTO wap_audit_log (
            procedure_name,
            batch_size,
            events_processed,
            events_published,
            error_count,
            error_summary,
            execution_time_ms,
            status
        ) VALUES (
            'sp_publish_to_gold',
            p_batch_size,
            0,
            0,
            v_error_count,
            v_error_summary,
            v_execution_time,
            'failed'
        );
    ELSE
        -- Step 2: Mark events as published in Silver
        UPDATE silver_events
        SET
            status = 'published',
            published_at = NOW()
        WHERE status = 'pending'
            AND event_date >= CURDATE()
        LIMIT p_batch_size;

        SET v_published = ROW_COUNT();

        -- Step 3: Insert into Gold layer (denormalized with pre-aggregations)
        INSERT INTO rsgmusicchat_gold.gold_events (
            event_id,
            uid,
            event_name,
            event_date,
            venue_id,
            venue_name,
            venue_slug,
            venue_address,
            google_maps_url,
            start_time,
            end_time,
            price_min,
            price_max,
            price_notes,
            is_free,
            description,
            age_restriction,
            ticket_url,
            event_url,
            fb_event_url,
            image_url,
            genre_count,
            genres_concat,
            genres_fulltext,
            artists_concat,
            artists_fulltext,
            search_tags,
            published_at
        )
        SELECT
            se.event_id,
            se.uid,
            se.event_name,
            se.event_date,
            se.venue_id,
            dv.venue_name,
            dv.venue_slug,
            dv.address AS venue_address,
            dv.google_maps_url,
            se.start_time,
            se.end_time,
            se.price_min,
            se.price_max,
            se.price_notes,
            se.is_free,
            se.description,
            se.age_restriction,
            se.ticket_url,
            se.event_url,
            se.fb_event_url,
            se.image_url,
            -- Pre-aggregated genre count
            (SELECT COUNT(*) FROM event_genres WHERE event_id = se.event_id) AS genre_count,
            -- Denormalized genres (comma-separated for display)
            (SELECT GROUP_CONCAT(dg.genre_name ORDER BY dg.genre_name SEPARATOR ', ')
             FROM event_genres eg
             INNER JOIN dim_genres dg ON eg.genre_id = dg.genre_id
             WHERE eg.event_id = se.event_id) AS genres_concat,
            -- Denormalized genres (space-separated for FULLTEXT)
            (SELECT GROUP_CONCAT(dg.genre_name ORDER BY dg.genre_name SEPARATOR ' ')
             FROM event_genres eg
             INNER JOIN dim_genres dg ON eg.genre_id = dg.genre_id
             WHERE eg.event_id = se.event_id) AS genres_fulltext,
            -- Denormalized artists (comma-separated for display)
            (SELECT GROUP_CONCAT(da.artist_name ORDER BY ea.performance_order SEPARATOR ', ')
             FROM event_artists ea
             INNER JOIN dim_artists da ON ea.artist_id = da.artist_id
             WHERE ea.event_id = se.event_id) AS artists_concat,
            -- Denormalized artists (space-separated for FULLTEXT)
            (SELECT GROUP_CONCAT(da.artist_name ORDER BY ea.performance_order SEPARATOR ' ')
             FROM event_artists ea
             INNER JOIN dim_artists da ON ea.artist_id = da.artist_id
             WHERE ea.event_id = se.event_id) AS artists_fulltext,
            -- Combined search tags
            CONCAT_WS(' ',
                se.event_name,
                dv.venue_name,
                (SELECT GROUP_CONCAT(dg.genre_name SEPARATOR ' ')
                 FROM event_genres eg
                 INNER JOIN dim_genres dg ON eg.genre_id = dg.genre_id
                 WHERE eg.event_id = se.event_id),
                (SELECT GROUP_CONCAT(da.artist_name SEPARATOR ' ')
                 FROM event_artists ea
                 INNER JOIN dim_artists da ON ea.artist_id = da.artist_id
                 WHERE ea.event_id = se.event_id)
            ) AS search_tags,
            se.published_at
        FROM silver_events se
        INNER JOIN dim_venues dv ON se.venue_id = dv.venue_id
        WHERE se.status = 'published'
            AND se.published_at >= DATE_SUB(NOW(), INTERVAL 1 MINUTE)
        ON DUPLICATE KEY UPDATE
            event_name = VALUES(event_name),
            venue_name = VALUES(venue_name),
            start_time = VALUES(start_time),
            end_time = VALUES(end_time),
            price_min = VALUES(price_min),
            price_max = VALUES(price_max),
            description = VALUES(description),
            genre_count = VALUES(genre_count),
            genres_concat = VALUES(genres_concat),
            genres_fulltext = VALUES(genres_fulltext),
            artists_concat = VALUES(artists_concat),
            artists_fulltext = VALUES(artists_fulltext),
            search_tags = VALUES(search_tags),
            updated_at = NOW();

        -- Step 4: Update pre-aggregated genre statistics
        INSERT INTO rsgmusicchat_gold.gold_genre_stats (genre_id, genre_name, upcoming_event_count)
        SELECT
            g.genre_id,
            g.genre_name,
            COUNT(DISTINCT ge.event_id) AS event_count
        FROM dim_genres g
        LEFT JOIN event_genres eg ON g.genre_id = eg.genre_id
        LEFT JOIN rsgmusicchat_gold.gold_events ge ON eg.event_id = ge.event_id
            AND ge.event_date >= CURDATE()
        GROUP BY g.genre_id, g.genre_name
        ON DUPLICATE KEY UPDATE
            upcoming_event_count = VALUES(upcoming_event_count),
            last_updated = NOW();

        -- Step 5: Update pre-aggregated venue statistics
        INSERT INTO rsgmusicchat_gold.gold_venue_stats (venue_id, venue_name, upcoming_event_count, last_event_date)
        SELECT
            ge.venue_id,
            ge.venue_name,
            COUNT(*) AS upcoming_count,
            MAX(ge.event_date) AS last_event
        FROM rsgmusicchat_gold.gold_events ge
        WHERE ge.event_date >= CURDATE()
        GROUP BY ge.venue_id, ge.venue_name
        ON DUPLICATE KEY UPDATE
            upcoming_event_count = VALUES(upcoming_event_count),
            last_event_date = VALUES(last_event_date),
            last_updated = NOW();

        COMMIT;

        SET p_published_count = v_published;
        SET p_result_message = CONCAT('SUCCESS: Published ', v_published, ' events to Gold layer');

        -- Calculate execution time
        SET v_execution_time = UNIX_TIMESTAMP(NOW(3)) * 1000 - v_start_time;

        -- Log successful publication
        INSERT INTO wap_audit_log (
            procedure_name,
            batch_size,
            events_processed,
            events_published,
            error_count,
            error_summary,
            execution_time_ms,
            status
        ) VALUES (
            'sp_publish_to_gold',
            p_batch_size,
            v_published,
            v_published,
            0,
            'Successfully published events',
            v_execution_time,
            'success'
        );
    END IF;
END$$

-- ============================================================================
-- STORED PROCEDURE: sp_reject_event
-- Purpose: Manually reject low-quality events
-- ============================================================================

DROP PROCEDURE IF EXISTS sp_reject_event$$

CREATE PROCEDURE sp_reject_event(
    IN p_event_id BIGINT UNSIGNED,
    IN p_rejection_reason TEXT
)
BEGIN
    DECLARE v_rows_affected INT;

    UPDATE silver_events
    SET
        status = 'rejected',
        rejection_reason = p_rejection_reason,
        updated_at = NOW()
    WHERE event_id = p_event_id
        AND status = 'pending';

    SET v_rows_affected = ROW_COUNT();

    SELECT v_rows_affected AS rows_affected;
END$$

-- ============================================================================
-- STORED PROCEDURE: sp_rebuild_gold_from_silver
-- Purpose: Zero-downtime Gold layer rebuild from Silver
-- Pattern: Rebuild in shadow table → Swap VIEW → Rename tables
-- ============================================================================

DROP PROCEDURE IF EXISTS sp_rebuild_gold_from_silver$$

CREATE PROCEDURE sp_rebuild_gold_from_silver()
BEGIN
    DECLARE v_current_table VARCHAR(50);
    DECLARE v_rebuild_table VARCHAR(50);
    DECLARE v_events_rebuilt INT DEFAULT 0;
    DECLARE v_start_time BIGINT;
    DECLARE v_execution_time INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;

        -- Log failure
        INSERT INTO wap_audit_log (
            procedure_name,
            events_processed,
            error_count,
            error_summary,
            status
        ) VALUES (
            'sp_rebuild_gold_from_silver',
            0,
            1,
            'EXCEPTION: Rebuild failed',
            'failed'
        );

        SELECT 'FAILED: Rebuild aborted' AS result;
    END;

    SET v_start_time = UNIX_TIMESTAMP(NOW(3)) * 1000;

    -- Determine current active table from VIEW definition
    SELECT TABLE_NAME INTO v_current_table
    FROM INFORMATION_SCHEMA.VIEWS
    WHERE TABLE_SCHEMA = 'rsgmusicchat_gold'
        AND TABLE_NAME = 'v_live_events'
        AND VIEW_DEFINITION LIKE '%gold_events_new%'
    LIMIT 1;

    IF v_current_table IS NOT NULL THEN
        -- VIEW currently points to gold_events_new, rebuild gold_events
        SET v_rebuild_table = 'gold_events';
    ELSE
        -- VIEW currently points to gold_events, rebuild gold_events_new
        SET v_rebuild_table = 'gold_events_new';
    END IF;

    -- Step 1: Truncate inactive table
    IF v_rebuild_table = 'gold_events' THEN
        TRUNCATE TABLE rsgmusicchat_gold.gold_events;
    ELSE
        TRUNCATE TABLE rsgmusicchat_gold.gold_events_new;
    END IF;

    -- Step 2: Rebuild inactive table from Silver
    SET @rebuild_sql = CONCAT('
        INSERT INTO rsgmusicchat_gold.', v_rebuild_table, ' (
            event_id, uid, event_name, event_date, venue_id, venue_name, venue_slug,
            venue_address, google_maps_url, start_time, end_time, price_min, price_max,
            price_notes, is_free, description, age_restriction, ticket_url, event_url,
            fb_event_url, image_url, genres_concat, genres_fulltext, artists_concat,
            artists_fulltext, search_tags, published_at
        )
        SELECT
            se.event_id, se.uid, se.event_name, se.event_date, se.venue_id,
            dv.venue_name, dv.venue_slug, dv.address, dv.google_maps_url,
            se.start_time, se.end_time, se.price_min, se.price_max, se.price_notes,
            se.is_free, se.description, se.age_restriction, se.ticket_url, se.event_url,
            se.fb_event_url, se.image_url,
            (SELECT GROUP_CONCAT(dg.genre_name ORDER BY dg.genre_name SEPARATOR ", ")
             FROM event_genres eg INNER JOIN dim_genres dg ON eg.genre_id = dg.genre_id
             WHERE eg.event_id = se.event_id),
            (SELECT GROUP_CONCAT(dg.genre_name ORDER BY dg.genre_name SEPARATOR " ")
             FROM event_genres eg INNER JOIN dim_genres dg ON eg.genre_id = dg.genre_id
             WHERE eg.event_id = se.event_id),
            (SELECT GROUP_CONCAT(da.artist_name ORDER BY ea.performance_order SEPARATOR ", ")
             FROM event_artists ea INNER JOIN dim_artists da ON ea.artist_id = da.artist_id
             WHERE ea.event_id = se.event_id),
            (SELECT GROUP_CONCAT(da.artist_name ORDER BY ea.performance_order SEPARATOR " ")
             FROM event_artists ea INNER JOIN dim_artists da ON ea.artist_id = da.artist_id
             WHERE ea.event_id = se.event_id),
            CONCAT_WS(" ", se.event_name, dv.venue_name,
                (SELECT GROUP_CONCAT(dg.genre_name SEPARATOR " ")
                 FROM event_genres eg INNER JOIN dim_genres dg ON eg.genre_id = dg.genre_id
                 WHERE eg.event_id = se.event_id),
                (SELECT GROUP_CONCAT(da.artist_name SEPARATOR " ")
                 FROM event_artists ea INNER JOIN dim_artists da ON ea.artist_id = da.artist_id
                 WHERE ea.event_id = se.event_id)),
            se.published_at
        FROM rsgmusicchat_silver.silver_events se
        INNER JOIN rsgmusicchat_silver.dim_venues dv ON se.venue_id = dv.venue_id
        WHERE se.status = "published"
            AND se.event_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
    ');

    PREPARE stmt FROM @rebuild_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    SET v_events_rebuilt = ROW_COUNT();

    -- Step 3: Atomic VIEW swap
    IF v_rebuild_table = 'gold_events_new' THEN
        -- Swap VIEW to newly rebuilt gold_events_new
        CREATE OR REPLACE VIEW rsgmusicchat_gold.v_live_events AS
        SELECT * FROM rsgmusicchat_gold.gold_events_new;
    ELSE
        -- Swap VIEW to newly rebuilt gold_events
        CREATE OR REPLACE VIEW rsgmusicchat_gold.v_live_events AS
        SELECT * FROM rsgmusicchat_gold.gold_events;
    END IF;

    -- Step 4: Rename tables for next rebuild
    -- (This makes the newly active table "gold_events" and old one "gold_events_new")
    IF v_rebuild_table = 'gold_events_new' THEN
        RENAME TABLE
            rsgmusicchat_gold.gold_events TO rsgmusicchat_gold.gold_events_temp,
            rsgmusicchat_gold.gold_events_new TO rsgmusicchat_gold.gold_events,
            rsgmusicchat_gold.gold_events_temp TO rsgmusicchat_gold.gold_events_new;
    END IF;

    -- Calculate execution time
    SET v_execution_time = UNIX_TIMESTAMP(NOW(3)) * 1000 - v_start_time;

    -- Log successful rebuild
    INSERT INTO wap_audit_log (
        procedure_name,
        events_processed,
        error_count,
        error_summary,
        execution_time_ms,
        status
    ) VALUES (
        'sp_rebuild_gold_from_silver',
        v_events_rebuilt,
        0,
        CONCAT('Successfully rebuilt ', v_events_rebuilt, ' events'),
        v_execution_time,
        'success'
    );

    SELECT
        v_events_rebuilt AS events_rebuilt,
        NOW() AS rebuild_timestamp,
        'SUCCESS: Gold layer rebuilt from Silver' AS result;
END$$

DELIMITER ;

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. All procedures log to wap_audit_log for debugging
-- 2. sp_upsert_event ensures idempotency via uid UNIQUE constraint
-- 3. sp_audit_pending_events runs 5 validation checks
-- 4. sp_publish_to_gold uses all-or-nothing transaction
-- 5. sp_rebuild_gold_from_silver implements zero-downtime VIEW swap
-- 6. Execution time tracked in milliseconds for performance monitoring
-- ============================================================================
