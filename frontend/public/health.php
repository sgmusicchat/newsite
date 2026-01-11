<?php
/**
 * Health Check Endpoint
 * Purpose: Docker/Nginx health check
 */

require_once '../includes/config.php';

try {
    // Test Gold layer connection
    $stmt = $pdo_gold->query("SELECT 1 AS test");
    $result = $stmt->fetch();

    if ($result && $result['test'] == 1) {
        http_response_code(200);
        echo json_encode([
            'status' => 'healthy',
            'service' => 'rsgmusicchat_php',
            'timestamp' => date('Y-m-d H:i:s')
        ]);
    } else {
        throw new Exception("Database query failed");
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'unhealthy',
        'error' => $e->getMessage()
    ]);
}
?>
