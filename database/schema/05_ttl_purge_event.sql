-- ============================================================================
-- r/sgmusicchat - TTL PURGE EVENT SCHEDULER
-- Purpose: Automated 7-day TTL enforcement for Gold layer
-- Schedule: Daily at 02:00 AM Singapore time
-- Safety: Only affects Gold layer; Silver remains intact for replay
-- ============================================================================

USE rsgmusicchat_gold;

-- ============================================================================
-- Enable MySQL Event Scheduler
-- Note: Add 'event_scheduler=ON' to my.cnf or docker-compose command
-- ============================================================================

SET GLOBAL event_scheduler = ON;

-- ============================================================================
-- OPTIONAL: Purge audit log table
-- Purpose: Track automated purge executions for compliance
-- ============================================================================

CREATE TABLE IF NOT EXISTS gold_purge_log (
    log_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    purge_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    threshold_date DATE NOT NULL COMMENT 'Events before this date were deleted',
    rows_deleted INT UNSIGNED NOT NULL DEFAULT 0,
    execution_time_ms INT UNSIGNED DEFAULT NULL,
    purge_type ENUM('automated', 'manual') NOT NULL DEFAULT 'automated',

    PRIMARY KEY (log_id),
    INDEX idx_purge_date (purge_date),
    INDEX idx_threshold_date (threshold_date)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Audit log for automated Gold layer purges';

-- ============================================================================
-- SCHEDULED EVENT: evt_purge_expired_events
-- Purpose: Delete events older than 7 days from Gold layer
-- Frequency: Daily at 02:00 AM
-- ============================================================================

DELIMITER $$

DROP EVENT IF EXISTS evt_purge_expired_events$$

CREATE EVENT evt_purge_expired_events
    ON SCHEDULE
        EVERY 1 DAY
        STARTS CONCAT(CURDATE() + INTERVAL 1 DAY, ' 02:00:00')
    ON COMPLETION PRESERVE
    ENABLE
    COMMENT 'Purge events older than 7 days from Gold layer (TTL enforcement)'
    DO
    BEGIN
        DECLARE v_deleted_count INT DEFAULT 0;
        DECLARE v_purge_date DATE;
        DECLARE v_start_time BIGINT;
        DECLARE v_execution_time INT;

        SET v_start_time = UNIX_TIMESTAMP(NOW(3)) * 1000;

        -- Calculate purge threshold: 7 days ago
        SET v_purge_date = DATE_SUB(CURDATE(), INTERVAL 7 DAY);

        -- Delete expired events from primary Gold table
        DELETE FROM gold_events
        WHERE event_date < v_purge_date;

        SET v_deleted_count = ROW_COUNT();

        -- Also purge from shadow table
        DELETE FROM gold_events_new
        WHERE event_date < v_purge_date;

        -- Calculate execution time
        SET v_execution_time = UNIX_TIMESTAMP(NOW(3)) * 1000 - v_start_time;

        -- Log purge activity
        INSERT INTO gold_purge_log (
            purge_date,
            threshold_date,
            rows_deleted,
            execution_time_ms,
            purge_type
        ) VALUES (
            NOW(),
            v_purge_date,
            v_deleted_count,
            v_execution_time,
            'automated'
        );
    END$$

DELIMITER ;

-- ============================================================================
-- MANUAL PURGE PROCEDURE
-- Purpose: On-demand purge for testing or maintenance
-- ============================================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_manual_purge_gold$$

CREATE PROCEDURE sp_manual_purge_gold(
    IN p_days_threshold INT,
    OUT p_deleted_count INT
)
BEGIN
    DECLARE v_purge_date DATE;
    DECLARE v_start_time BIGINT;
    DECLARE v_execution_time INT;

    SET v_start_time = UNIX_TIMESTAMP(NOW(3)) * 1000;

    -- Calculate dynamic threshold
    SET v_purge_date = DATE_SUB(CURDATE(), INTERVAL p_days_threshold DAY);

    -- Execute purge on primary table
    DELETE FROM gold_events
    WHERE event_date < v_purge_date;

    SET p_deleted_count = ROW_COUNT();

    -- Also purge from shadow table
    DELETE FROM gold_events_new
    WHERE event_date < v_purge_date;

    -- Calculate execution time
    SET v_execution_time = UNIX_TIMESTAMP(NOW(3)) * 1000 - v_start_time;

    -- Log manual purge
    INSERT INTO gold_purge_log (
        purge_date,
        threshold_date,
        rows_deleted,
        execution_time_ms,
        purge_type
    ) VALUES (
        NOW(),
        v_purge_date,
        p_deleted_count,
        v_execution_time,
        'manual'
    );

    -- Output summary
    SELECT
        v_purge_date AS purge_threshold,
        p_deleted_count AS events_deleted,
        v_execution_time AS execution_time_ms,
        NOW() AS executed_at;
END$$

DELIMITER ;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check event scheduler status
-- SHOW VARIABLES LIKE 'event_scheduler';
-- Expected: ON

-- View scheduled events
-- SHOW EVENTS FROM rsgmusicchat_gold;

-- Check event details
-- SELECT
--     event_name,
--     event_schema,
--     event_definition,
--     interval_value,
--     interval_field,
--     starts,
--     status
-- FROM information_schema.EVENTS
-- WHERE event_name = 'evt_purge_expired_events';

-- Manual execution test (purge events older than 7 days)
-- CALL sp_manual_purge_gold(7, @deleted);
-- SELECT @deleted AS events_purged;

-- Verify Gold layer only contains upcoming events
-- SELECT
--     MIN(event_date) AS earliest_event,
--     MAX(event_date) AS latest_event,
--     COUNT(*) AS total_events,
--     DATEDIFF(MIN(event_date), CURDATE()) AS days_from_now_min
-- FROM gold_events;
-- Expected: earliest_event >= CURDATE() or within past 7 days

-- View purge history
-- SELECT
--     purge_date,
--     threshold_date,
--     rows_deleted,
--     execution_time_ms,
--     purge_type
-- FROM gold_purge_log
-- ORDER BY purge_date DESC
-- LIMIT 10;

-- ============================================================================
-- PERFORMANCE NOTES
-- ============================================================================
-- 1. DELETE uses B-Tree index on event_date (fast execution)
-- 2. Typical purge time: <5 seconds for thousands of events
-- 3. Event scheduler runs in background, no impact on queries
-- 4. Purges both gold_events and gold_events_new for consistency
-- 5. Log table tracks all purges for compliance and debugging
-- ============================================================================

-- ============================================================================
-- SAFETY FEATURES
-- ============================================================================
-- 1. Only Gold layer affected; Silver remains intact for replay
-- 2. Scheduled during low-traffic hours (02:00 AM)
-- 3. ON COMPLETION PRESERVE ensures event persists after execution
-- 4. Manual override via sp_manual_purge_gold() for on-demand execution
-- 5. Audit logging tracks all purges with timestamps and row counts
-- ============================================================================
