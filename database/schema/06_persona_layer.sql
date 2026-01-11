-- ============================================================================
-- Persona Synth Layer - AI-Generated User Personas
-- ============================================================================
-- Purpose: Store MySpace-style personas generated from webcam color extraction
-- Architecture: Simplified (no medallion for MVP)
-- Database: rsgmusicchat_gold
-- Created: 2026-01-10
-- ============================================================================

USE rsgmusicchat_gold;

-- Drop table if exists (for development/testing)
DROP TABLE IF EXISTS personas;

-- Create personas table
CREATE TABLE personas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    session_id VARCHAR(64) NOT NULL UNIQUE COMMENT 'Browser session identifier (cookie-based)',
    hex_colors JSON NOT NULL COMMENT 'Array of 3 hex colors from camera capture ["#FF0000", "#00FF00", "#0000FF"]',
    persona_json JSON NOT NULL COMMENT 'Full persona object from Gemini (enforced schema)',
    pixelated_image_data MEDIUMTEXT COMMENT 'Base64 encoded 16x16 image for profile picture',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_accessed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_session (session_id),
    INDEX idx_created (created_at),
    INDEX idx_last_accessed (last_accessed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='AI-generated user personas from webcam color extraction';

-- ============================================================================
-- TTL Cleanup Event (Optional - Post-MVP)
-- ============================================================================
-- Purge personas older than 30 days to prevent database bloat
-- Uncomment to enable:

-- DROP EVENT IF EXISTS evt_purge_old_personas;

-- CREATE EVENT evt_purge_old_personas
-- ON SCHEDULE EVERY 1 DAY
-- STARTS '2026-01-11 03:00:00'
-- DO
-- DELETE FROM personas
-- WHERE last_accessed_at < DATE_SUB(NOW(), INTERVAL 30 DAY);

-- ============================================================================
-- Verification Query
-- ============================================================================
-- Run after creation to verify:
-- DESCRIBE personas;
-- SELECT COUNT(*) FROM personas;
