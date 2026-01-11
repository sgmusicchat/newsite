"""
Gemini AI Persona Generator Service
Handles color-to-persona transformation via Gemini API

Architecture: Gutsy Startup - direct API calls, no abstractions
Purpose: Generate MySpace-style personas from webcam color extraction
"""

import json
import os
import logging
from typing import List, Dict, Any
import google.generativeai as genai

# ============================================================================
# Configuration
# ============================================================================

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)

# Allow overriding the Gemini model via env var (useful for testing/rollouts)
MODEL_NAME = os.getenv("GEMINI_MODEL_NAME", "gemini-2.0-flash-exp")  # Default model

# Logger
logger = logging.getLogger(__name__)

# ============================================================================
# Idempotent JSON Schema (enforce strict structure)
# ============================================================================

PERSONA_JSON_SCHEMA = {
    "type": "object",
    "properties": {
        "module": {
            "type": "string",
            "enum": ["neo_y2k", "glitch_grunge"],
            "description": "Visual theme module"
        },
        "metadata": {
            "type": "object",
            "properties": {
                "alias": {
                    "type": "string",
                    "description": "Internet alias (3-12 characters)"
                },
                "aura": {
                    "type": "integer",
                    "description": "Aura score based on color vibrancy (1-99)"
                },
                "alignment": {
                    "type": "string",
                    "description": "D&D-style alignment (e.g., 'chaotic good')"
                },
                "bio": {
                    "type": "string",
                    "description": "1-2 sentence MySpace-style bio"
                }
            },
            "required": ["alias", "aura", "alignment", "bio"]
        },
        "visuals": {
            "type": "object",
            "properties": {
                "bg_color": {
                    "type": "string",
                    "description": "Background color in hex format (e.g. #1a1a2e)"
                },
                "accent_color": {
                    "type": "string",
                    "description": "Accent/highlight color in hex format (e.g. #00ff41)"
                },
                "font_type": {
                    "type": "string",
                    "enum": ["monospace", "sans-serif"],
                    "description": "CSS font family"
                },
                "border_style": {
                    "type": "string",
                    "description": "CSS border style (e.g., 'dotted 3px')"
                }
            },
            "required": ["bg_color", "accent_color", "font_type", "border_style"]
        },
        "audio": {
            "type": "object",
            "properties": {
                "prompt": {
                    "type": "string",
                    "description": "Music generation prompt for Lyria (placeholder for MVP)"
                },
                "tempo": {
                    "type": "integer",
                    "description": "BPM (beats per minute)"
                },
                "vibe_weight": {
                    "type": "number",
                    "description": "Intensity of musical vibe (0.0-1.0)"
                }
            },
            "required": ["prompt", "tempo", "vibe_weight"]
        }
    },
    "required": ["module", "metadata", "visuals", "audio"]
}

# ============================================================================
# System Instruction (Gemini AI Behavior)
# ============================================================================

SYSTEM_INSTRUCTION = """You are a MySpace-era digital persona synthesizer from 2006.
Given 3 hex color codes extracted from a pixelated webcam capture, generate a retro internet identity.

COLOR PSYCHOLOGY RULES:
- Bright/warm colors (#FF*, #FE*, red/orange/yellow tones) → "neo_y2k" module
- Dark/cool colors (#00-#44*, blue/purple/black tones) → "glitch_grunge" module
- High saturation → High aura score (70-99)
- Low saturation/muted → Low aura score (1-40)

PERSONA GENERATION RULES:
1. **Alias**: 3-12 character internet handle. Examples: "xXcyb3rXx", "n30ndr3am", "gl1tchk1d"
   - Use leetspeak (1=i, 3=e, 0=o, 4=a, 7=t)
   - Add X's, underscores, or numbers for authenticity

2. **Aura**: 1-99 score based on color vibrancy
   - Vibrant RGB → 80-99
   - Muted/pastel → 30-50
   - Dark/desaturated → 1-30

3. **Alignment**: D&D-style based on color psychology
   - Red/orange → chaotic
   - Blue/green → lawful
   - Purple/yellow → neutral
   - Good/evil based on brightness (bright=good, dark=evil)

4. **Bio**: 1-2 sentence MySpace profile description
   - Include emotive language ("digital wanderer", "neon dreamer")
   - Reference internet culture (cyber, matrix, glitch, vaporwave)

5. **Visuals**:
   - bg_color: Use darkest input color or complementary
   - accent_color: Use brightest input color
   - font_type: "monospace" for tech/glitch vibes, "sans-serif" for clean/y2k
   - border_style: "dotted 3px" or "solid 2px" or "dashed 4px"

6. **Audio**: (Placeholder for MVP - music not generated yet)
   - prompt: Describe 30-second instrumental loop matching persona vibe
   - tempo: 80-100 (chill), 120-140 (upbeat), 160+ (intense)
   - vibe_weight: 0.0-1.0 (how strongly the vibe should be expressed)

CRITICAL: Return ONLY valid JSON. No markdown, no explanations, no code blocks.

Example for colors ["#FF5733", "#33FF57", "#3357FF"]:
{
  "module": "neo_y2k",
  "metadata": {
    "alias": "n30nv1b3z",
    "aura": 87,
    "alignment": "chaotic good",
    "bio": "A digital wanderer surfing the chromatic waves of the early internet. Powered by RGB energy and Y2K nostalgia."
  },
  "visuals": {
    "bg_color": "#1a1a2e",
    "accent_color": "#00ff41",
    "font_type": "monospace",
    "border_style": "dotted 3px"
  },
  "audio": {
    "prompt": "Upbeat synthwave with bright arpeggios and nostalgic FM synth pads, 128 BPM",
    "tempo": 128,
    "vibe_weight": 0.8
  }
}
"""

# ============================================================================
# Core Function
# ============================================================================

def generate_persona_from_colors(
    hex_colors: List[str],
    user_intent: str = "default"
) -> Dict[str, Any]:
    """
    Generate persona JSON from 3 hex colors using Gemini API

    Args:
        hex_colors: List of exactly 3 hex color strings (e.g., ["#FF5733", "#33FF57", "#3357FF"])
        user_intent: Optional user-provided vibe/intent (e.g., "cyberpunk", "chill", "default")

    Returns:
        Dict containing persona JSON matching PERSONA_JSON_SCHEMA

    Raises:
        ValueError: If API key not set or Gemini returns invalid JSON
        Exception: If API call fails

    Example:
        >>> persona = generate_persona_from_colors(["#FF0000", "#00FF00", "#0000FF"])
        >>> print(persona["metadata"]["alias"])
        "cyb3rdr34m"
    """
    # Validation
    if not GEMINI_API_KEY:
        # Treat missing API key as a server configuration error
        raise RuntimeError("GEMINI_API_KEY not set in environment. Add it to .env file.")

    if len(hex_colors) != 3:
        raise ValueError(f"Expected 3 hex colors, got {len(hex_colors)}")

    # Initialize Gemini model with structured output
    model = genai.GenerativeModel(
        model_name=MODEL_NAME,
        generation_config=genai.GenerationConfig(
            response_mime_type="application/json",
            response_schema=PERSONA_JSON_SCHEMA,
            temperature=0.9,  # High creativity for persona generation
            top_p=0.95,
            top_k=40
        ),
        system_instruction=SYSTEM_INSTRUCTION
    )

    # Construct user prompt
    user_prompt = f"""Generate a MySpace persona from these colors:

Color 1: {hex_colors[0]}
Color 2: {hex_colors[1]}
Color 3: {hex_colors[2]}

User vibe preference: {user_intent}

Return valid JSON matching the schema."""

    try:
        # Call Gemini API
        print(f"[Gemini] Generating persona from colors: {hex_colors}")
        response = model.generate_content(user_prompt)

        # Parse JSON response
        persona_json = json.loads(response.text)

        # Validation (basic sanity check)
        required_keys = ["module", "metadata", "visuals", "audio"]
        if not all(key in persona_json for key in required_keys):
            raise ValueError(f"Gemini response missing required keys. Got: {list(persona_json.keys())}")

        print(f"[Gemini] ✓ Generated persona: {persona_json['metadata']['alias']}")
        return persona_json

    except json.JSONDecodeError as e:
        raise ValueError(f"Gemini returned invalid JSON: {e}\nResponse text: {response.text[:200]}")
    except AttributeError as e:
        raise Exception(f"Gemini API response format error: {e}")
    except Exception as e:
        raise Exception(f"Gemini API error: {str(e)}")


# ============================================================================
# Testing/Development
# ============================================================================

if __name__ == "__main__":
    # Test function with sample colors
    test_colors = ["#FF5733", "#33FF57", "#3357FF"]

    try:
        persona = generate_persona_from_colors(test_colors, "cyberpunk")
        print("\n" + "="*60)
        print("GENERATED PERSONA")
        print("="*60)
        print(json.dumps(persona, indent=2))
        print("="*60)
    except Exception as e:
        print(f"Error: {e}")
