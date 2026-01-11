# r/sgmusicchat - Singapore Music Events Discovery Platform

A data-driven, event management platform for discovering Singapore electronic music events. This project demonstrates a **medallion architecture** (Bronze → Silver → Gold) with automated data quality workflows, Python/FastAPI backend orchestration, and a PHP web frontend.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [System Architecture](#system-architecture)
3. [Database Schema & Initialization](#database-schema--initialization)
4. [Running the Code](#running-the-code)
5. [Configuration](#configuration)
6. [Project Structure](#project-structure)
7. [Common Tasks](#common-tasks)

---

## Quick Start

### Prerequisites
- Docker & Docker Compose 3.8+
- Python 3.11+ (for local development)
- Git

### Start the Application

```bash
# 1. Clone and navigate to project
cd /home/seanai/muSG

# 2. Create .env file from template
cp .env.example .env

# 3. Start all services (MySQL, Nginx, PHP, Python API)
docker-compose -f docker/docker-compose.yml up -d

# 4. Initialize database (runs automatically on first start)
# Wait ~10 seconds for MySQL to be ready, then check:
docker-compose -f docker/docker-compose.yml logs mysql

# 5. Access the application
# Public: http://localhost (event listing)
# Admin: http://localhost/admin (login with admin/admin123)
# Health: http://localhost/health.php
```

### Stop the Application

```bash
docker-compose -f docker/docker-compose.yml down
```

### Reset Everything (Fresh Start)

```bash
# Remove volumes to reset database
docker-compose -f docker/docker-compose.yml down -v

# Start fresh
docker-compose -f docker/docker-compose.yml up -d
```

---

## System Architecture

### High-Level Overview

This is a **three-layer data warehouse** (Medallion Pattern) with automated event discovery, quality control, and publication workflows.

```
┌─────────────────────────────────────────────────────────────────┐
│                   INGESTION SOURCES                              │
├──────────────┬──────────────┬────────────────────────────────────┤
│ Daily Mock   │ Visitor Form │ Admin Manual Entry                 │
│ Scraper      │ Submission   │ (Event Editing)                    │
└──────┬───────┴──────┬───────┴──────────────┬────────────────────┘
       │              │                      │
       └──────────────┼──────────────────────┘
                      ↓
         ┌────────────────────────┐
         │  BRONZE LAYER          │
         │  (Raw Immutable Store) │
         │  - JSON preservation   │
         │  - Audit trail         │
         │  - No validation       │
         └──────────┬─────────────┘
                    ↓
         ┌────────────────────────┐
         │  SILVER LAYER          │
         │  (Normalized Form)     │
         │  - Star schema         │
         │  - Validation rules    │
         │  - Status tracking     │
         │  - Full history (TTL=0)│
         └──────────┬─────────────┘
                    ↓
         ┌────────────────────────┐
         │  WAP WORKFLOW          │
         │  (Write-Audit-Publish) │
         │  1. Audit              │
         │  2. Auto-quarantine bad│
         │  3. Publish if OK      │
         └──────────┬─────────────┘
                    ↓
         ┌────────────────────────┐
         │  GOLD LAYER            │
         │  (Published Data)      │
         │  - Read-only           │
         │  - Pre-aggregated      │
         │  - Indexed for speed   │
         └──────────┬─────────────┘
                    ↓
         ┌────────────────────────┐
         │  PUBLIC CONSUMPTION    │
         │  - Web UI listing      │
         │  - NLP search (AI)     │
         │  - Admin dashboard     │
         └────────────────────────┘
```

### Components Overview

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Web Server** | Nginx 1.25 | Reverse proxy, static assets, public entry point (port 80) |
| **PHP Frontend** | PHP 8.2-FPM | Server-rendered HTML, event listing, admin panel |
| **Python Backend** | FastAPI 0.109 | API orchestration, schedulers, WAP workflows |
| **Database** | MySQL 8.0 | Three-layer data warehouse (Bronze/Silver/Gold) |
| **Scheduler** | APScheduler 3.10 | Background jobs (daily scraper, hourly auto-publish) |
| **AI Search** | OpenRouter API + Gemini 2.0 | Natural language event filtering |

### Network Architecture

All services communicate via private Docker bridge network (`rsgmusicchat_network`):

```
Nginx (port 80)
    ↓ (localhost:9000)
PHP-FPM
    ↓
MySQL (port 3306)
    ↑
Python FastAPI (port 8000, internal only)
```

---

## Database Schema & Initialization

### Three-Layer Structure

#### **BRONZE LAYER** - Raw Immutable Store
- **Purpose**: Audit trail and replay capability
- **Data Retention**: Forever (no TTL)
- **Tables**:
  - `bronze_scraper_raw` - Raw JSON from scrapers
  - `bronze_user_submissions` - Visitor form submissions
  - `bronze_admin_edits` - Admin manual changes
- **Characteristics**: No validation, preserves exact raw data

#### **SILVER LAYER** - System of Record
- **Purpose**: Normalized data with full history
- **Data Retention**: Forever (no TTL) - complete historical record
- **Schema**: Star schema (Kimball dimensional modeling)
- **Tables**:
  - **Fact Table**: `silver_events` - Main event data
  - **Dimensions**:
    - `dim_venues` - Venue information
    - `dim_artists` - Artist/performer data
    - `dim_genres` - Genre taxonomy (31 genres, controlled vocabulary)
  - **Bridge Tables** (Many-to-Many):
    - `event_genres` - Events ↔ Genres relationship
    - `event_artists` - Events ↔ Artists relationship (with performance order)
- **Status Tracking**: `pending` → `published` or `rejected` or `quarantined`
- **Validation**: CHECK constraints, foreign keys, referential integrity

#### **GOLD LAYER** - Published Data
- **Purpose**: Optimized read-only data for public consumption
- **Data Retention**: TTL-based cleanup via MySQL EVENT (configurable)
- **Tables**:
  - `gold_events` - Published events with denormalized data
  - `gold_genre_stats` - Pre-aggregated genre statistics
  - `gold_venue_stats` - Pre-aggregated venue statistics
  - `v_live_events` (View) - Events from last 7 days
- **Characteristics**: Indexes optimized for fast reads, pre-aggregated metrics

### Database Initialization

The database initializes automatically through **numbered SQL schema files** (executed in order on `docker-compose up`):

| File | Purpose |
|------|---------|
| `00_init_databases.sql` | Create 3 databases (Bronze, Silver, Gold) |
| `01_bronze_layer.sql` | Define raw data tables |
| `02_silver_layer.sql` | Define normalized star schema + 31 genres |
| `03_gold_layer.sql` | Define published data + stats + views |
| `04_wap_procedures.sql` | Define stored procedures for WAP workflow |
| `05_ttl_purge_event.sql` | Define MySQL EVENT for TTL cleanup (if enabled) |
| `06_persona_layer.sql` | Define persona theme storage tables |

**Initialization Flow:**
```
1. MySQL container starts
2. Docker entrypoint script mounts /database/schema/ as initialization volume
3. MySQL reads all *.sql files in order (00→06)
4. Tables, views, procedures, and events are created
5. Initial genre data inserted (31 genres)
6. Services become available when status check passes
```

### Key Schema Features

**Idempotency Key (Duplicate Prevention)**
```sql
uid = MD5(CONCAT(venue_id, event_date, start_time))
```
Events with same venue, date, and time are considered duplicates. The UID ensures 100% duplicate prevention.

**Genre Matching Algorithm**
- Genres stored as comma-separated string in `silver_events.genres_concat`
- `FIND_IN_SET()` function matches genres against `dim_genres` controlled vocabulary
- Normalizes spacing and case variations
- 31 genres available: Techno, House, Indie, AOR, Deep House, Tech House, etc.

**WAP Status Tracking**
- `pending` - Awaiting audit validation
- `published` - Passed audit, in Gold layer, visible to public
- `quarantined` - Failed audit, hidden from public
- `rejected` - Manually rejected by admin

---

## Running the Code

### Development Setup

#### 1. Local Python Environment (for testing/development)

```bash
# Create virtual environment
python3.11 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r src/requirements.txt

# Create .env file
cp .env.example .env

# Run tests
pytest src/tests/ -v --cov=src
```

#### 2. Docker Development Mode

```bash
# Start services in foreground (see logs live)
docker-compose -f docker/docker-compose.yml up

# In another terminal, view specific service logs
docker-compose -f docker/docker-compose.yml logs -f python_api
docker-compose -f docker/docker-compose.yml logs -f php_fpm
docker-compose -f docker/docker-compose.yml logs -f mysql
```

#### 3. Access Points

| Service | URL | Purpose |
|---------|-----|---------|
| **Public Frontend** | `http://localhost` | Event listing, search |
| **Event Submit** | `http://localhost/submit.php` | User form submission |
| **Admin Panel** | `http://localhost/admin` | Moderation dashboard |
| **Health Check** | `http://localhost/health.php` | Service status |
| **FastAPI Docs** | Not exposed | Internal API only |

### Production Considerations

#### Environment Variables

See `.env.example` for all configuration options:

```bash
# Database
DB_HOST=mysql
DB_USER=rsguser
DB_PASSWORD=rsgpass

# Admin credentials
ADMIN_USERNAME=admin
ADMIN_PASSWORD_HASH=<bcrypt_hash>

# AI Services
OPENROUTER_API_KEY=sk-or-v1-xxxxx
GEMINI_API_KEY=AIzaxxxxx

# Scheduling
AUTO_PUBLISH_INTERVAL=60  # Minutes between auto-publish runs
MOCK_SCRAPER_HOUR=6       # Hour of day for daily scraper (0-23)

# External APIs (for production scrapers)
FACEBOOK_ACCESS_TOKEN=your_token
EVENTBRITE_API_KEY=your_key
```

#### Database Backups

```bash
# Backup all three databases
docker-compose -f docker/docker-compose.yml exec mysql \
  mysqldump -u rsguser -prsgpass --all-databases > backup.sql

# Restore from backup
docker-compose -f docker/docker-compose.yml exec -T mysql \
  mysql -u rsguser -prsgpass < backup.sql
```

#### Scaling Considerations

- **Scheduler**: Currently runs in FastAPI process (single instance). For multiple FastAPI replicas, use external APScheduler with database backend
- **PHP-FPM**: Stateless, can scale horizontally behind Nginx
- **MySQL**: Single node; for HA, add replication or Galera Cluster

---

## Configuration

### .env File (Required)

Create from template:
```bash
cp .env.example .env
```

**Critical settings:**
```env
# Database connection (change for production)
DB_PASSWORD=your_secure_password

# Admin access
ADMIN_PASSWORD_HASH=$(php -r 'echo password_hash("newpass", PASSWORD_BCRYPT);')

# API keys (get from services)
OPENROUTER_API_KEY=sk-or-v1-...
GEMINI_API_KEY=AIza...
```

### Environment-Specific Configuration

**Development** (`.env` + local override):
```bash
ENVIRONMENT=development
LOG_LEVEL=DEBUG
ENABLE_SCHEDULER=true
AUTO_PUBLISH_INTERVAL=2  # Quick testing
MOCK_SCRAPER_HOUR=*      # Every hour for testing
```

**Production** (`.env` secure):
```bash
ENVIRONMENT=production
LOG_LEVEL=INFO
ENABLE_SCHEDULER=true
AUTO_PUBLISH_INTERVAL=60
MOCK_SCRAPER_HOUR=6
# Enable external scrapers
FACEBOOK_ACCESS_TOKEN=prod_token
EVENTBRITE_API_KEY=prod_key
```

---

## Project Structure

```
/home/seanai/muSG/
│
├── docker/                          # Docker configuration
│   ├── docker-compose.yml          # Multi-service orchestration
│   ├── nginx/
│   │   └── conf.d/default.conf     # Nginx reverse proxy config
│   └── .env                        # Docker service env vars
│
├── src/                            # Python FastAPI Backend
│   ├── main.py                     # Application entry point
│   ├── config.py                   # Database + environment setup
│   ├── requirements.txt            # Python dependencies
│   ├── Dockerfile                  # Python container image
│   ├── scrapers/
│   │   └── mock_scraper.py        # Test event generation
│   ├── services/
│   │   ├── bronze_writer.py       # Raw data ingestion
│   │   ├── silver_processor.py    # Transformation logic
│   │   ├── wap_executor.py        # Audit & publish workflow
│   │   ├── scheduler.py           # Background job orchestration
│   │   ├── gemini_persona.py      # AI theme generation
│   │   └── persona_db.py          # Persona storage
│   └── tests/
│       └── test_*.py              # Unit tests
│
├── frontend/                       # PHP Web Application
│   ├── Dockerfile.php             # PHP 8.2-FPM container
│   ├── includes/
│   │   ├── config.php             # PDO connections + env loader
│   │   └── persona_helper.php     # Theme utilities
│   ├── public/
│   │   ├── index.php              # Event listing (Gold layer)
│   │   ├── submit.php             # Event submission form
│   │   ├── nlp_handler.php        # AI-powered search (OpenRouter)
│   │   ├── health.php             # Health check endpoint
│   │   └── assets/                # CSS, images, fonts
│   └── admin/
│       ├── login.php              # Authentication
│       ├── index.php              # Moderation dashboard
│       ├── approve.php            # Approve events
│       └── reject.php             # Reject events
│
├── database/
│   ├── schema/                    # Database initialization
│   │   ├── 00_init_databases.sql     # Create databases
│   │   ├── 01_bronze_layer.sql       # Raw storage
│   │   ├── 02_silver_layer.sql       # Star schema + genres
│   │   ├── 03_gold_layer.sql         # Published data
│   │   ├── 04_wap_procedures.sql     # Stored procedures
│   │   ├── 05_ttl_purge_event.sql    # TTL cleanup
│   │   └── 06_persona_layer.sql      # Persona tables
│   └── test/
│       └── *.sql                  # Test queries
│
├── .env                           # Environment variables (⚠️ don't commit)
├── .env.example                   # Environment template (✓ commit)
├── .gitignore                     # Git ignore patterns
└── README.md                      # This file
```

---

## Common Tasks

### View Logs

```bash
# All services
docker-compose -f docker/docker-compose.yml logs -f

# Specific service
docker-compose -f docker/docker-compose.yml logs -f python_api
docker-compose -f docker/docker-compose.yml logs -f mysql

# Follow in real-time
docker-compose -f docker/docker-compose.yml logs -f --tail=50
```

### Access MySQL Directly

```bash
# Interactive MySQL shell
docker-compose -f docker/docker-compose.yml exec mysql \
  mysql -u rsguser -prsgpass rsgmusicchat_silver

# Run a single query
docker-compose -f docker/docker-compose.yml exec mysql \
  mysql -u rsguser -prsgpass -e "SELECT COUNT(*) FROM silver_events;"
```

### Trigger Workflows Manually

```bash
# Run the scheduled mock scraper
curl http://localhost:8000/trigger-scraper

# Run WAP workflow (audit + publish)
curl http://localhost:8000/trigger-wap
```

### Clear Data (Development Only)

```bash
# Delete all events but keep schema
docker-compose -f docker/docker-compose.yml exec mysql \
  mysql -u rsguser -prsgpass -e "DELETE FROM rsgmusicchat_silver.silver_events;"

# Or reset everything
docker-compose -f docker/docker-compose.yml down -v
docker-compose -f docker/docker-compose.yml up -d
```

### Update Genres

Genres are in `database/schema/02_silver_layer.sql`. To add more:

1. Edit the INSERT statement in `02_silver_layer.sql`
2. For existing databases:
   ```sql
   INSERT INTO dim_genres (genre_name, genre_slug, sort_order)
   VALUES ('New Genre', 'new-genre', 32);
   ```
3. For fresh installs: The schema file handles it automatically

### Debug Event Processing

```bash
# Check pending events (not yet published)
SELECT * FROM silver_events WHERE status = 'pending';

# Check quarantined events (failed audit)
SELECT * FROM silver_events WHERE status = 'quarantined';

# View audit log
SELECT * FROM wap_audit_log ORDER BY executed_at DESC LIMIT 20;

# Check genre mapping for an event
SELECT eg.*, dg.genre_name FROM event_genres eg
JOIN dim_genres dg ON eg.genre_id = dg.genre_id
WHERE eg.event_id = 2;
```

---

## Architecture Principles

This project follows the "**Gutsy Startup**" philosophy:
- **Boring technology**: MySQL, PHP, Python, Nginx (proven, well-documented)
- **Database as source of truth**: Minimal application state
- **Simple data flows**: Direct SQLite, no message queues or caching layers
- **Aggressive validation**: Fail fast, quarantine bad data, audit everything
- **Reproducibility**: Full historical record in Bronze layer enables replays

---

## Further Reading

- **Database Design**: See `README_IMPLEMENTATION.md` for detailed schema documentation
- **API Development**: See `src/main.py` for FastAPI endpoint definitions
- **Frontend Code**: See `frontend/public/index.php` for public page implementation

---

## Support

For issues or questions:
1. Check logs: `docker-compose logs -f`
2. Verify database: `docker-compose exec mysql mysql -u rsguser -prsgpass -e "SELECT 1;"`
3. Check `.env` configuration
4. Review schema files in `database/schema/`