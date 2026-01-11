/**
 * Persona Theme Manager - Global Application
 * Purpose: Load stored persona theme from session cookie and apply CSS variables
 * Works across all public pages except admin
 */

class PersonaThemeManager {
    constructor() {
        this.apiBaseUrl = 'http://localhost:8000';
        this.cookieName = 'persona_session_id';
        this.init();
    }

    init() {
        // Skip theme application on admin pages
        if (this.isAdminPage()) {
            return;
        }

        // Check for existing session
        const sessionId = this.getCookie(this.cookieName);
        if (sessionId) {
            this.loadAndApplyTheme(sessionId);
        }
    }

    isAdminPage() {
        // Check if current URL path contains /admin/
        return window.location.pathname.includes('/admin/');
    }

    getCookie(name) {
        const nameEQ = name + '=';
        const cookies = document.cookie.split(';');
        for (let cookie of cookies) {
            cookie = cookie.trim();
            if (cookie.indexOf(nameEQ) === 0) {
                return cookie.substring(nameEQ.length);
            }
        }
        return null;
    }

    async loadAndApplyTheme(sessionId) {
        try {
            const response = await fetch(
                `${this.apiBaseUrl}/api/v1/persona/retrieve/${sessionId}`
            );

            if (!response.ok) {
                console.warn('[PersonaTheme] Failed to retrieve persona:', response.status);
                return;
            }

            const data = await response.json();
            if (data.status !== 'success' || !data.persona) {
                console.warn('[PersonaTheme] Invalid persona response');
                return;
            }

            this.applyTheme(data.persona);
        } catch (error) {
            console.warn('[PersonaTheme] Error loading theme:', error);
        }
    }

    applyTheme(persona) {
        try {
            const visuals = persona.persona_json?.visuals || {};

            // Extract colors and styles from persona
            const bgColor = visuals.bg_color || '#000000';
            const accentColor = visuals.accent_color || '#00ff00';
            const fontType = visuals.font_type || 'monospace';
            const borderStyle = visuals.border_style || 'dotted 3px';

            // Apply CSS variables to root
            document.documentElement.style.setProperty('--persona-bg', bgColor);
            document.documentElement.style.setProperty('--persona-accent', accentColor);
            document.documentElement.style.setProperty('--persona-font', fontType);
            document.documentElement.style.setProperty('--persona-border', borderStyle);

            // Optional: Apply background color to body
            document.body.style.backgroundColor = bgColor;

            console.log('[PersonaTheme] ✓ Applied theme for:', persona.persona_json.metadata.alias);
        } catch (error) {
            console.warn('[PersonaTheme] Error applying theme:', error);
        }
    }
}

// Initialize on DOM ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        new PersonaThemeManager();
    });
} else {
    new PersonaThemeManager();
}
