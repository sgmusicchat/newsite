<?php
/**
 * Persona Theme Helper - Server-Side Theme Application
 * Purpose: Load persona theme from session and provide PHP functions for template rendering
 * Architecture: Gutsy Startup - no JS, pure PHP server-side logic
 */

/**
 * Get persona theme from session cookie and database
 * 
 * Returns theme data or null if no persona exists
 * 
 * @return array|null Theme data with keys: bg_color, accent_color, font_type, border_style, alias
 */
function get_persona_theme() {
    global $pdo_gold;

    // Check for session cookie
    $session_id = $_COOKIE['persona_session_id'] ?? null;
    if (!$session_id) {
        return null;
    }

    try {
        // Query database for persona
        $sql = "
            SELECT
                persona_json,
                created_at
            FROM personas
            WHERE session_id = ?
        ";
        
        $stmt = $pdo_gold->prepare($sql);
        $stmt->execute([$session_id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$row) {
            return null;
        }

        // Parse persona JSON
        $persona_json = json_decode($row['persona_json'], true);
        if (!$persona_json || !isset($persona_json['visuals']) || !isset($persona_json['metadata'])) {
            return null;
        }

        // Extract theme data
        $visuals = $persona_json['visuals'];
        $metadata = $persona_json['metadata'];

        return [
            'bg_color' => $visuals['bg_color'] ?? '#000000',
            'accent_color' => $visuals['accent_color'] ?? '#00ff00',
            'font_type' => $visuals['font_type'] ?? 'monospace',
            'border_style' => $visuals['border_style'] ?? 'dotted 3px',
            'alias' => $metadata['alias'] ?? 'unknown',
            'created_at' => $row['created_at']
        ];

    } catch (Exception $e) {
        // Log error but don't break the page
        error_log("[Persona] Error loading theme: " . $e->getMessage());
        return null;
    }
}

/**
 * Generate CSS to apply persona theme
 * 
 * @param array|null $theme Theme data from get_persona_theme()
 * @return string CSS string (empty if no theme)
 */
function render_persona_theme_css($theme = null) {
    if (!$theme) {
        return '';
    }

    return <<<CSS
:root {
    --persona-bg: {$theme['bg_color']};
    --persona-accent: {$theme['accent_color']};
    --persona-font: {$theme['font_type']};
    --persona-border: {$theme['border_style']};
}
CSS;
}

/**
 * Generate HTML indicator showing active persona theme (optional UI)
 * 
 * @param array|null $theme Theme data from get_persona_theme()
 * @return string HTML snippet (empty if no theme)
 */
function render_persona_indicator($theme = null) {
    if (!$theme) {
        return '';
    }

    return <<<HTML
<div style="
    font-size: 11px;
    color: {$theme['accent_color']};
    border: 1px solid {$theme['accent_color']};
    border-style: {$theme['border_style']};
    padding: 8px;
    margin-bottom: 15px;
    background: {$theme['bg_color']};
">
    <strong>✨ Persona Active:</strong> {$theme['alias']} (Generated {$theme['created_at']})
</div>
HTML;
}
?>
