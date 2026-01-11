-- ============================================================================
-- r/sgmusicchat - BRONZE LAYER
-- Purpose: Immutable raw storage for event sourcing and replay capability
-- Architecture: Medallion (Bronze → Silver → Gold)
-- Retention: Indefinite (archive old records to object storage periodically)
-- ============================================================================

-- Create Bronze database
CREATE DATABASE IF NOT EXISTS rsgmusicchat_bronze
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE rsgmusicchat_bronze;

-- ============================================================================
-- TABLE: bronze_scraper_raw
-- Purpose: Store raw JSON payloads from automated scrapers
-- Sources: Facebook Events API, Eventbrite API, Instagram scraping, etc.
-- ============================================================================

CREATE TABLE bronze_scraper_raw (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    scraper_source VARCHAR(100) NOT NULL COMMENT 'e.g., facebook, eventbrite, instagram, manual',
    scraped_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Timestamp when data was scraped',
    raw_payload JSON NOT NULL COMMENT 'Complete unprocessed scraper output',
    scraper_version VARCHAR(50) DEFAULT NULL COMMENT 'Scraper version for debugging changes',
    http_status_code INT UNSIGNED DEFAULT NULL COMMENT 'API response code (200, 404, etc.)',
    request_url TEXT DEFAULT NULL COMMENT 'Original API endpoint or URL scraped',

    PRIMARY KEY (id),
    INDEX idx_source_time (scraper_source, scraped_at),
    INDEX idx_scraped_at (scraped_at)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable raw scraper outputs for replay capability';

-- ============================================================================
-- TABLE: bronze_user_submissions
-- Purpose: Store raw user form submissions from public-facing web forms
-- ============================================================================

CREATE TABLE bronze_user_submissions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When user submitted the form',
    submission_ip VARCHAR(45) DEFAULT NULL COMMENT 'IPv4/IPv6 for abuse tracking',
    raw_form_data JSON NOT NULL COMMENT 'Complete form POST data as JSON',
    user_agent TEXT DEFAULT NULL COMMENT 'Browser user agent string',
    referrer_url VARCHAR(500) DEFAULT NULL COMMENT 'HTTP referer (where user came from)',
    session_id VARCHAR(100) DEFAULT NULL COMMENT 'Session identifier for tracking',

    PRIMARY KEY (id),
    INDEX idx_submitted_at (submitted_at),
    INDEX idx_submission_ip (submission_ip, submitted_at)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable user form submissions';

-- ============================================================================
-- TABLE: bronze_admin_edits
-- Purpose: Store manual edits made by administrators
-- ============================================================================

CREATE TABLE bronze_admin_edits (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    edited_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    admin_username VARCHAR(100) NOT NULL COMMENT 'Admin who made the edit',
    edit_type ENUM('create', 'update', 'delete', 'override') NOT NULL,
    raw_edit_data JSON NOT NULL COMMENT 'Complete edit payload',
    edit_notes TEXT DEFAULT NULL COMMENT 'Admin notes explaining the edit',

    PRIMARY KEY (id),
    INDEX idx_edited_at (edited_at),
    INDEX idx_admin (admin_username, edited_at),
    INDEX idx_edit_type (edit_type, edited_at)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Audit trail for manual admin edits';

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. No validation constraints - Bronze accepts ALL data
-- 2. JSON columns preserve complete raw data for debugging and replay
-- 3. Timestamped for chronological replay scenarios
-- 4. Separate tables by source (scraper, user, admin) for clear lineage
-- 5. If scraper logic has bugs, delete Silver/Gold and replay from Bronze
-- 6. Archive old Bronze data (>90 days) to object storage (S3/DigitalOcean Spaces)
-- ============================================================================
