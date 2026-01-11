"""
r/sgmusicchat - Python/FastAPI Service
Purpose: Internal API for scraper orchestration and WAP workflows
Architecture: Gutsy Startup - boring tech, blazing fast
"""

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
import config
import secrets
import re
import logging
import time
from services.scheduler import start_scheduler, stop_scheduler, get_scheduled_jobs
from scrapers.mock_scraper import generate_mock_events, generate_bad_event_for_quarantine_testing
from services.bronze_writer import write_to_bronze
from services.silver_processor import process_bronze_to_silver
from services.wap_executor import (
    run_audit,
    run_publish,
    auto_publish_workflow,
    get_wap_metrics
)
from services.gemini_persona import generate_persona_from_colors
from services.persona_db import save_persona, retrieve_persona_by_session

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI
app = FastAPI(
    title="r/sgmusicchat Python API",
    description="Internal API for scraper orchestration and WAP workflows",
    version="1.0.0"
)

# Add CORS middleware (for Persona Synth frontend)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request/Response logging middleware for debugging
@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all incoming requests and responses with full details"""
    start_time = time.time()

    # Log incoming request
    logger.debug(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    logger.debug(f"📥 INCOMING REQUEST")
    logger.debug(f"Method: {request.method}")
    logger.debug(f"URL: {request.url}")
    logger.debug(f"Path: {request.url.path}")
    logger.debug(f"Client: {request.client.host}:{request.client.port}")
    logger.debug(f"Headers: {dict(request.headers)}")

    # Process request
    response = await call_next(request)

    # Log response
    process_time = time.time() - start_time
    logger.debug(f"📤 RESPONSE")
    logger.debug(f"Status: {response.status_code}")
    logger.debug(f"Time: {process_time:.3f}s")
    logger.debug(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    return response


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    # Log validation errors and request body for easier debugging (avoid storing secrets)
    try:
        body = await request.body()
    except Exception:
        body = b"<unavailable>"

    logger.error("Request validation error: %s", exc)
    logger.debug("Request body causing validation error: %s", body)

    return JSONResponse(
        status_code=422,
        content={"detail": exc.errors()}
    )

# ============================================================================
# Pydantic Models (Request/Response schemas)
# ============================================================================

class MockScraperRequest(BaseModel):
    count: int = 10
    include_bad_events: bool = False


class ProcessBronzeRequest(BaseModel):
    bronze_id: int
    scraper_source: str = "scraper"


class PublishRequest(BaseModel):
    batch_size: int = 500


class PersonaGenerateRequest(BaseModel):
    hex_colors: List[str]
    user_intent: str = "default"
    pixelated_image_data: Optional[str] = None


class PersonaGenerateResponse(BaseModel):
    status: str
    session_id: str
    persona_json: Dict[str, Any]


# ============================================================================
# FastAPI Lifecycle Events
# ============================================================================

@app.on_event("startup")
async def startup_event():
    """Start background scheduler on FastAPI startup"""
    print("\n🚀 FastAPI Starting Up...")
    start_scheduler()


@app.on_event("shutdown")
async def shutdown_event():
    """Stop background scheduler on FastAPI shutdown"""
    print("\n🛑 FastAPI Shutting Down...")
    stop_scheduler()


# ============================================================================
# Health Check Endpoints
# ============================================================================

@app.get("/api/v1/health")
async def health_check():
    """
    Health check endpoint
    Returns: System health status
    """
    try:
        # Test database connection
        from config import get_db_cursor, DB_NAME_SILVER
        with get_db_cursor(DB_NAME_SILVER) as cursor:
            cursor.execute("SELECT 1 AS test")
            result = cursor.fetchone()

        db_status = "connected" if result else "disconnected"
    except Exception as e:
        db_status = f"error: {str(e)}"

    return {
        "status": "healthy",
        "service": "rsgmusicchat_python_api",
        "database": db_status,
        "scheduler": "enabled" if config.ENABLE_SCHEDULER else "disabled",
        "environment": config.FASTAPI_ENV
    }


@app.get("/api/v1/metrics")
async def get_metrics():
    """
    Get system metrics (event counts by status)
    Returns: Dictionary of event counts
    """
    try:
        metrics = get_wap_metrics()
        return {
            "status": "success",
            "metrics": metrics
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# Scraper Orchestration Endpoints
# ============================================================================

@app.post("/api/v1/scrapers/mock/run")
async def run_mock_scraper(request: MockScraperRequest):
    """
    Trigger mock scraper and process to Silver
    Args: count (number of events), include_bad_events (for quarantine testing)
    Returns: Scraper results
    """
    try:
        # Generate mock events
        events = generate_mock_events(count=request.count)

        # Optionally add bad event for quarantine testing
        if request.include_bad_events:
            bad_event = generate_bad_event_for_quarantine_testing()
            events.append(bad_event)

        # Write to Bronze
        bronze_id = write_to_bronze(events, scraper_source="mock_scraper")

        # Process to Silver
        processed, new = process_bronze_to_silver(bronze_id, scraper_source="scraper")

        return {
            "status": "success",
            "bronze_id": bronze_id,
            "events_generated": len(events),
            "events_processed": processed,
            "new_events": new,
            "updated_events": processed - new
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/scrapers/process-bronze")
async def process_bronze(request: ProcessBronzeRequest):
    """
    Process existing Bronze record to Silver
    Args: bronze_id, scraper_source
    Returns: Processing results
    """
    try:
        processed, new = process_bronze_to_silver(
            bronze_id=request.bronze_id,
            scraper_source=request.scraper_source
        )

        return {
            "status": "success",
            "bronze_id": request.bronze_id,
            "events_processed": processed,
            "new_events": new,
            "updated_events": processed - new
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# WAP Workflow Endpoints
# ============================================================================

@app.post("/api/v1/wap/audit")
async def wap_audit():
    """
    Run aggressive audit (auto-quarantines bad records)
    Returns: Audit results
    """
    try:
        error_count, quarantined_count, error_summary = run_audit()

        return {
            "status": "success" if error_count == 0 else "failed",
            "error_count": error_count,
            "quarantined_count": quarantined_count,
            "error_summary": error_summary,
            "audit_passed": error_count == 0
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/wap/publish")
async def wap_publish(request: PublishRequest):
    """
    Run WAP publish workflow (audit + publish)
    Args: batch_size
    Returns: Publish results
    """
    try:
        result = auto_publish_workflow(batch_size=request.batch_size)

        return {
            "status": result['status'],
            "error_count": result['error_count'],
            "quarantined_count": result['quarantined_count'],
            "published_count": result['published_count'],
            "message": result['message']
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# Scheduler Management Endpoints
# ============================================================================

@app.get("/api/v1/scheduler/jobs")
async def get_jobs():
    """
    Get list of scheduled jobs
    Returns: List of job information
    """
    try:
        jobs = get_scheduled_jobs()
        return {
            "status": "success",
            "jobs": jobs
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# Persona Synth Endpoints (NEW)
# ============================================================================

@app.options("/api/v1/persona/generate")
async def persona_generate_options():
    """Explicit OPTIONS handler for CORS preflight"""
    return JSONResponse(
        content={"message": "OK"},
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
            "Access-Control-Max-Age": "3600",
        }
    )


@app.post("/debug/echo")
async def debug_echo(request: Request):
    """Temporary debug endpoint: returns raw request body as text.

    Use only for local debugging; remove before production.
    """
    try:
        body_bytes = await request.body()
        try:
            body_text = body_bytes.decode('utf-8')
        except Exception:
            body_text = repr(body_bytes)

        return JSONResponse(content={"raw_body": body_text, "headers": dict(request.headers)})
    except Exception as e:
        logger.exception("debug_echo failed")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/persona/generate", response_model=PersonaGenerateResponse)
async def generate_persona(request: PersonaGenerateRequest):
    """
    Generate persona from hex colors using Gemini API

    This endpoint powers the Persona Synth feature - converts webcam-extracted
    colors into a MySpace-style digital identity with theme and music prompt.

    Args:
        hex_colors: Array of exactly 3 hex color codes (e.g., ["#FF5733", "#33FF57", "#3357FF"])
        user_intent: Optional user-provided vibe/intent (e.g., "cyberpunk", "chill")
        pixelated_image_data: Optional base64 encoded image for profile picture

    Returns:
        {
            "status": "success",
            "session_id": "abc123...",
            "persona_json": {
                "module": "neo_y2k",
                "metadata": {...},
                "visuals": {...},
                "audio": {...}
            }
        }

    Errors:
        400: Invalid input (wrong number of colors, invalid hex format)
        422: Gemini API validation error
        500: Server error (Gemini API failure, database error)
    """
    # Validate input - must be exactly 3 colors
    if len(request.hex_colors) != 3:
        raise HTTPException(
            status_code=400,
            detail=f"Must provide exactly 3 hex colors, got {len(request.hex_colors)}"
        )

    # Validate hex format
    hex_pattern = re.compile(r'^#[0-9A-Fa-f]{6}$')
    for color in request.hex_colors:
        if not hex_pattern.match(color):
            raise HTTPException(
                status_code=400,
                detail=f"Invalid hex color format: {color}. Expected format: #RRGGBB"
            )

    try:
        # Generate persona via Gemini
        persona_json = generate_persona_from_colors(
            hex_colors=request.hex_colors,
            user_intent=request.user_intent
        )

        # Generate secure session ID (32 bytes = 43 chars base64)
        session_id = secrets.token_urlsafe(32)

        # Save to database
        save_persona(
            session_id=session_id,
            hex_colors=request.hex_colors,
            persona_json=persona_json,
            pixelated_image_data=request.pixelated_image_data
        )

        return {
            "status": "success",
            "session_id": session_id,
            "persona_json": persona_json
        }

    except ValueError as e:
        # Gemini API validation errors (invalid schema, etc.)
        logger.error("Persona generation validation error: %s", e)
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        # Database errors, missing config (RuntimeError), or other server failures
        logger.exception("Persona generation failed")
        raise HTTPException(
            status_code=500,
            detail=f"Persona generation failed: {str(e)}"
        )


@app.get("/api/v1/persona/retrieve/{session_id}")
async def retrieve_persona(session_id: str):
    """
    Retrieve existing persona by session ID

    Used to restore persona theme when user returns to the site with
    their session cookie.

    Args:
        session_id: Session identifier from cookie

    Returns:
        {
            "status": "success",
            "persona": {
                "id": 42,
                "session_id": "abc123...",
                "hex_colors": ["#FF0000", ...],
                "persona_json": {...},
                "pixelated_image_data": "data:image/png;base64,...",
                "created_at": "2026-01-10T14:30:00"
            }
        }

    Errors:
        404: Persona not found for given session_id
        500: Database error
    """
    try:
        logger.info("[API] Retrieve request for session: %s...", session_id[:16])
        persona = retrieve_persona_by_session(session_id)

        if not persona:
            logger.warning("[API] Persona not found - returning 404")
            raise HTTPException(
                status_code=404,
                detail=f"Persona not found for session: {session_id}"
            )

        logger.info("[API] Persona retrieved successfully")
        return {
            "status": "success",
            "persona": persona
        }

    except HTTPException:
        # Re-raise HTTP exceptions (404)
        raise
    except Exception as e:
        # Database errors
        logger.exception("[API] Retrieve failed")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve persona: {str(e)}"
        )


# ============================================================================
# Root Endpoint
# ============================================================================

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "service": "r/sgmusicchat Python API",
        "version": "1.0.0",
        "description": "Internal API for scraper orchestration and WAP workflows",
        "endpoints": {
            "health": "/api/v1/health",
            "metrics": "/api/v1/metrics",
            "mock_scraper": "POST /api/v1/scrapers/mock/run",
            "wap_audit": "POST /api/v1/wap/audit",
            "wap_publish": "POST /api/v1/wap/publish",
            "scheduler_jobs": "/api/v1/scheduler/jobs",
            "persona_generate": "POST /api/v1/persona/generate",
            "persona_retrieve": "GET /api/v1/persona/retrieve/{session_id}"
        },
        "docs": "/docs"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,  # Auto-reload on code changes (dev only)
        log_level=config.LOG_LEVEL.lower()
    )
