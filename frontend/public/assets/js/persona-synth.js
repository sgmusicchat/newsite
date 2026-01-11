/**
 * Persona Synth - MySpace Profile Generator
 * Vanilla JavaScript (no dependencies)
 *
 * Architecture: Gutsy Startup - boring tech, no frameworks
 * Purpose: Webcam → Color Extraction → Gemini → CSS Theme
 */

class PersonaSynth {
    constructor() {
        this.stream = null;
        this.videoElement = null;
        this.canvasElement = null;
        this.modal = null;
        this.hexColors = [];
        this.sessionId = null;
        this.apiBaseUrl = 'http://localhost:8000';  // Python FastAPI backend

        this.init();
    }

    init() {
        // Check for existing session
        this.sessionId = this.getCookie('persona_session_id');
        if (this.sessionId) {
            this.loadExistingPersona();
        }

        // Create modal HTML
        this.createModal();

        // Bind event listeners
        const initBtn = document.getElementById('persona-init-btn');
        if (initBtn) {
            initBtn.addEventListener('click', () => this.openModal());
        }
    }

    createModal() {
        const modalHTML = `
        <div id="persona-modal" class="persona-modal" style="display: none;">
            <div class="persona-modal-content">
                <span class="persona-close">&times;</span>

                <!-- Step 1: Camera Capture -->
                <div id="step-capture" class="persona-step">
                    <h2>The Capture</h2>
                    <p>Initialize your digital identity...</p>
                    <div class="retro-monitor">
                        <video id="persona-video" autoplay playsinline></video>
                        <canvas id="persona-canvas" style="display: none;"></canvas>
                    </div>
                    <button id="capture-btn" class="retro-btn">Initialize Identity</button>
                </div>

                <!-- Step 2: Loading -->
                <div id="step-loading" class="persona-step" style="display: none;">
                    <h2>The Synthesis</h2>
                    <div class="dialup-loader">
                        <div class="loader-bar"></div>
                        <div id="loading-log" class="loading-log">
                            <p>→ Analyzing chromatic soul...</p>
                        </div>
                    </div>
                </div>

                <!-- Step 3: Result -->
                <div id="step-result" class="persona-step" style="display: none;">
                    <h2>The Persona</h2>
                    <div id="persona-display">
                        <!-- Dynamically populated -->
                    </div>
                    <button id="apply-theme-btn" class="retro-btn">Apply Theme</button>
                    <button id="regenerate-btn" class="retro-btn-secondary" style="margin-left: 10px;">Regenerate</button>
                </div>
            </div>
        </div>`;

        document.body.insertAdjacentHTML('beforeend', modalHTML);
        this.modal = document.getElementById('persona-modal');

        // Close button
        document.querySelector('.persona-close').addEventListener('click', () => {
            this.closeModal();
        });

        // Capture button
        document.getElementById('capture-btn').addEventListener('click', () => {
            this.captureFrame();
        });

        // Apply theme button
        const applyBtn = document.getElementById('apply-theme-btn');
        if (applyBtn) {
            applyBtn.addEventListener('click', () => {
                this.closeModal();
            });
        }

        // Regenerate button
        const regenBtn = document.getElementById('regenerate-btn');
        if (regenBtn) {
            regenBtn.addEventListener('click', () => {
                this.resetToCapture();
            });
        }

        // Click outside to close
        window.addEventListener('click', (event) => {
            if (event.target === this.modal) {
                this.closeModal();
            }
        });
    }

    async openModal() {
        this.modal.style.display = 'block';
        document.getElementById('step-capture').style.display = 'block';
        document.getElementById('step-loading').style.display = 'none';
        document.getElementById('step-result').style.display = 'none';
        await this.startCamera();
    }

    closeModal() {
        this.modal.style.display = 'none';
        this.stopCamera();
        
        // If persona was just generated, reload page to apply theme via PHP helper
        if (this.sessionId && document.getElementById('step-result').style.display === 'block') {
            console.log('[PersonaSynth] Reloading page to apply theme...');
            setTimeout(() => {
                window.location.reload();
            }, 500);
        }
    }

    resetToCapture() {
        document.getElementById('step-result').style.display = 'none';
        document.getElementById('step-capture').style.display = 'block';
        this.startCamera();
    }

    async startCamera() {
        try {
            this.stream = await navigator.mediaDevices.getUserMedia({
                video: { width: 640, height: 480, facingMode: 'user' }
            });
            this.videoElement = document.getElementById('persona-video');
            this.videoElement.srcObject = this.stream;
        } catch (error) {
            console.error('Camera access denied:', error);
            alert('Camera access required for persona generation. Please allow camera access and try again.');
            this.closeModal();
        }
    }

    stopCamera() {
        if (this.stream) {
            this.stream.getTracks().forEach(track => track.stop());
        }
    }

    captureFrame() {
        // Create canvas for pixelation
        this.canvasElement = document.getElementById('persona-canvas');
        const ctx = this.canvasElement.getContext('2d');

        // Draw video frame to canvas (pixelate to 16x16)
        this.canvasElement.width = 16;
        this.canvasElement.height = 16;
        ctx.drawImage(this.videoElement, 0, 0, 16, 16);

        // Extract dominant colors
        this.hexColors = this.extractDominantColors(ctx);
        console.log('[PersonaSynth] Extracted colors:', this.hexColors);

        // Get pixelated image as base64 (for profile picture)
        const imageData = this.canvasElement.toDataURL('image/png');

        // Stop camera
        this.stopCamera();

        // Show loading
        this.showLoading();

        // Call backend to generate persona
        this.generatePersona(imageData);
    }

    extractDominantColors(ctx) {
        const imageData = ctx.getImageData(0, 0, 16, 16);
        const pixels = imageData.data;
        const colorCounts = {};

        // Count color frequencies (skip very similar colors)
        for (let i = 0; i < pixels.length; i += 4) {
            const r = pixels[i];
            const g = pixels[i + 1];
            const b = pixels[i + 2];
            const hex = this.rgbToHex(r, g, b);
            colorCounts[hex] = (colorCounts[hex] || 0) + 1;
        }

        // Sort by frequency and return top 3
        const sorted = Object.entries(colorCounts)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 3)
            .map(entry => entry[0]);

        // Ensure we have exactly 3 colors (fill with black if needed)
        while (sorted.length < 3) {
            sorted.push('#000000');
        }

        return sorted;
    }

    rgbToHex(r, g, b) {
        return "#" + [r, g, b].map(x => {
            const hex = x.toString(16);
            return hex.length === 1 ? "0" + hex : hex;
        }).join('');
    }

    showLoading() {
        document.getElementById('step-capture').style.display = 'none';
        document.getElementById('step-loading').style.display = 'block';

        // Simulate retro loading logs
        const logs = [
            'Analyzing chromatic soul...',
            'Querying the MySpace Archive...',
            'Encoding persona matrix...',
            'Synthesizing digital aura...'
        ];

        const logContainer = document.getElementById('loading-log');
        logContainer.innerHTML = ''; // Clear previous logs

        logs.forEach((log, index) => {
            setTimeout(() => {
                const p = document.createElement('p');
                p.textContent = `→ ${log}`;
                logContainer.appendChild(p);
            }, index * 800);
        });
    }

    async generatePersona(imageData) {
        try {
            console.log('[PersonaSynth] Calling Gemini API via backend...');

            const response = await fetch(`${this.apiBaseUrl}/api/v1/persona/generate`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    hex_colors: this.hexColors,
                    user_intent: 'default',
                    pixelated_image_data: imageData
                })
            });

            if (!response.ok) {
                const errorData = await response.json().catch(() => ({}));
                throw new Error(errorData.detail || 'Persona generation failed');
            }

            const data = await response.json();
            console.log('[PersonaSynth] ✓ Persona generated:', data.persona_json.metadata.alias);

            this.sessionId = data.session_id;
            this.setCookie('persona_session_id', this.sessionId, 30); // 30 day expiry

            // Show result after minimum loading time (for UX)
            setTimeout(() => {
                this.displayPersona(data.persona_json);
            }, 2000);

        } catch (error) {
            console.error('[PersonaSynth] Error:', error);
            alert(`Failed to generate persona: ${error.message}\n\nPlease try again.`);
            this.closeModal();
        }
    }

    displayPersona(persona) {
        document.getElementById('step-loading').style.display = 'none';
        document.getElementById('step-result').style.display = 'block';

        const display = document.getElementById('persona-display');
        display.innerHTML = `
            <div class="persona-card ${persona.module}">
                <div class="persona-header">
                    <h3>${persona.metadata.alias}</h3>
                    <div class="persona-colors">
                        ${this.hexColors.map(c => `<span class="color-swatch" style="background: ${c};" title="${c}"></span>`).join('')}
                    </div>
                </div>

                <div class="persona-stats">
                    <div class="stat-item">
                        <span class="stat-label">Aura:</span>
                        <span class="stat-value">${persona.metadata.aura}/99</span>
                        <div class="aura-bar">
                            <div class="aura-fill" style="width: ${persona.metadata.aura}%"></div>
                        </div>
                    </div>
                    <div class="stat-item">
                        <span class="stat-label">Alignment:</span>
                        <span class="stat-value">${persona.metadata.alignment}</span>
                    </div>
                    <div class="stat-item">
                        <span class="stat-label">Module:</span>
                        <span class="stat-value">${persona.module === 'neo_y2k' ? 'Neo-Y2K' : 'Glitch Grunge'}</span>
                    </div>
                </div>

                <div class="persona-bio">
                    <p>${persona.metadata.bio}</p>
                </div>

                <div class="persona-theme-preview">
                    <p><strong>Theme Colors:</strong></p>
                    <p>Background: <code>${persona.visuals.bg_color}</code></p>
                    <p>Accent: <code>${persona.visuals.accent_color}</code></p>
                    <p>Font: <code>${persona.visuals.font_type}</code></p>
                </div>

                <div class="persona-music-placeholder">
                    <p><strong>🎵 Music Vibe:</strong> ${persona.audio.prompt}</p>
                    <p><em>(Music generation coming in Phase 2)</em></p>
                </div>
            </div>
        `;

        // Apply theme immediately
        this.applyTheme(persona.visuals);
    }

    applyTheme(visuals) {
        const root = document.documentElement;
        root.style.setProperty('--persona-bg', visuals.bg_color);
        root.style.setProperty('--persona-accent', visuals.accent_color);
        root.style.setProperty('--persona-font', visuals.font_type);
        root.style.setProperty('--persona-border', visuals.border_style);

        // Add theme class to body with smooth transition
        document.body.classList.add('persona-themed');

        console.log('[PersonaSynth] ✓ Theme applied');
    }

    async loadExistingPersona() {
        try {
            console.log('[PersonaSynth] Loading existing persona...');
            const response = await fetch(`${this.apiBaseUrl}/api/v1/persona/retrieve/${this.sessionId}`);

            if (response.ok) {
                const data = await response.json();
                this.applyTheme(data.persona.persona_json.visuals);
                console.log('[PersonaSynth] ✓ Existing persona loaded:', data.persona.persona_json.metadata.alias);
            } else {
                console.log('[PersonaSynth] No existing persona found');
                // Clear invalid session cookie
                this.setCookie('persona_session_id', '', -1);
                this.sessionId = null;
            }
        } catch (error) {
            console.log('[PersonaSynth] Failed to load existing persona:', error);
        }
    }

    setCookie(name, value, days) {
        const expires = new Date(Date.now() + days * 864e5).toUTCString();
        document.cookie = `${name}=${encodeURIComponent(value)}; expires=${expires}; path=/`;
    }

    getCookie(name) {
        return document.cookie.split('; ').reduce((r, v) => {
            const parts = v.split('=');
            return parts[0] === name ? decodeURIComponent(parts[1]) : r;
        }, '');
    }
}

// ============================================================================
// Initialize on DOM load
// ============================================================================

document.addEventListener('DOMContentLoaded', () => {
    console.log('[PersonaSynth] Initializing...');
    window.personaSynth = new PersonaSynth();
});
