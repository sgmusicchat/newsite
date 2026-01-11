-- ============================================================================
-- Database Initialization Script
-- Purpose: Create all three databases and grant permissions
-- Execution: Runs first (00_ prefix) during MySQL container initialization
-- ============================================================================

-- Create Bronze database
CREATE DATABASE IF NOT EXISTS rsgmusicchat_bronze
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- Create Silver database (already created by docker-compose, but ensure correct collation)
CREATE DATABASE IF NOT EXISTS rsgmusicchat_silver
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- Fix collation if database was auto-created with wrong default
ALTER DATABASE rsgmusicchat_silver
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- Create Gold database
CREATE DATABASE IF NOT EXISTS rsgmusicchat_gold
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- Grant all privileges to rsguser on all three databases
GRANT ALL PRIVILEGES ON rsgmusicchat_bronze.* TO 'rsguser'@'%';
GRANT ALL PRIVILEGES ON rsgmusicchat_silver.* TO 'rsguser'@'%';
GRANT ALL PRIVILEGES ON rsgmusicchat_gold.* TO 'rsguser'@'%';

-- Flush privileges to ensure changes take effect
FLUSH PRIVILEGES;

-- Display confirmation
SELECT 'Databases created and permissions granted successfully' AS status;