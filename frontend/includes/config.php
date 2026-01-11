<?php
/**
 * Database Configuration for r/sgmusicchat
 * Purpose: PDO connections to Bronze, Silver, and Gold layers
 * Architecture: Gutsy Startup - database as only shared state
 */

// Error reporting (disable in production)
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Database credentials from environment variables
$db_host = getenv('DB_HOST') ?: 'mysql';
$db_user = getenv('DB_USER') ?: 'rsguser';
$db_password = getenv('DB_PASSWORD') ?: 'rsgpass';

// Gold layer connection (read-only for public pages)
try {
    $pdo_gold = new PDO(
        "mysql:host={$db_host};dbname=rsgmusicchat_gold;charset=utf8mb4",
        $db_user,
        $db_password,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
} catch (PDOException $e) {
    die("Gold DB Connection failed: " . $e->getMessage());
}

// Silver layer connection (read/write for admin, write for visitor submissions)
try {
    $pdo_silver = new PDO(
        "mysql:host={$db_host};dbname=rsgmusicchat_silver;charset=utf8mb4",
        $db_user,
        $db_password,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
} catch (PDOException $e) {
    die("Silver DB Connection failed: " . $e->getMessage());
}

// Bronze layer connection (write-only for audit trail)
try {
    $pdo_bronze = new PDO(
        "mysql:host={$db_host};dbname=rsgmusicchat_bronze;charset=utf8mb4",
        $db_user,
        $db_password,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
} catch (PDOException $e) {
    die("Bronze DB Connection failed: " . $e->getMessage());
}

// Admin authentication configuration
$admin_username = getenv('ADMIN_USERNAME') ?: 'admin';
$admin_password_hash = getenv('ADMIN_PASSWORD_HASH') ?: password_hash('admin123', PASSWORD_BCRYPT);

// Helper function: Check if user is admin
function is_admin() {
    session_start();
    return isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true;
}

// Helper function: Require admin authentication
function require_admin() {
    if (!is_admin()) {
        header('Location: /admin/login.php');
        exit;
    }
}
?>
