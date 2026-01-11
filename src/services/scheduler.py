"""
Background Scheduler Service
Purpose: Schedule recurring tasks (mock scraper, auto-publish WAP)
Uses: APScheduler (in-process background scheduler)
"""

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger
from datetime import datetime
import config
from scrapers.mock_scraper import generate_mock_events
from services.bronze_writer import write_to_bronze
from services.silver_processor import process_bronze_to_silver
from services.wap_executor import auto_publish_workflow

# Global scheduler instance
scheduler = BackgroundScheduler()


def run_mock_scraper_job():
    """
    Scheduled job: Run mock scraper and process to Silver
    Frequency: Daily at configured hour (default 6 AM)
    """
    print(f"\n[SCHEDULER] Mock Scraper Job Started - {datetime.now()}")

    try:
        # Generate mock events
        events = generate_mock_events(count=10)
        print(f"✅ Generated {len(events)} mock events")

        # Write to Bronze
        bronze_id = write_to_bronze(events, scraper_source="mock_scraper")

        # Process to Silver
        processed, new = process_bronze_to_silver(bronze_id, scraper_source="scraper")

        print(f"✅ Mock Scraper Job Completed: {processed} processed, {new} new")
    except Exception as e:
        print(f"❌ Mock Scraper Job Failed: {str(e)}")


def run_auto_publish_job():
    """
    Scheduled job: Auto-publish WAP workflow
    Frequency: Every hour (configurable via AUTO_PUBLISH_INTERVAL)
    """
    print(f"\n[SCHEDULER] Auto-Publish Job Started - {datetime.now()}")

    try:
        result = auto_publish_workflow(batch_size=500)
        print(f"✅ Auto-Publish Job Completed: {result['status']}")
    except Exception as e:
        print(f"❌ Auto-Publish Job Failed: {str(e)}")


def start_scheduler():
    """
    Start background scheduler with configured jobs
    Called by FastAPI on startup
    """
    if not config.ENABLE_SCHEDULER:
        print("⚠️  Scheduler DISABLED (ENABLE_SCHEDULER=false)")
        return

    print("\n" + "="*60)
    print("🕐 Starting Background Scheduler")
    print("="*60)

    # Job 1: Daily mock scraper (runs at configured hour, default 6 AM)
    scheduler.add_job(
        func=run_mock_scraper_job,
        trigger=CronTrigger(hour=config.MOCK_SCRAPER_HOUR, minute=0),
        id='daily_mock_scraper',
        name='Daily Mock Scraper',
        replace_existing=True
    )
    print(f"✅ Scheduled: Daily Mock Scraper at {config.MOCK_SCRAPER_HOUR}:00")

    # Job 2: Auto-publish WAP workflow (runs every N minutes, default 60)
    scheduler.add_job(
        func=run_auto_publish_job,
        trigger=IntervalTrigger(minutes=config.AUTO_PUBLISH_INTERVAL),
        id='auto_publish_wap',
        name='Auto-Publish WAP Workflow',
        replace_existing=True
    )
    print(f"✅ Scheduled: Auto-Publish WAP every {config.AUTO_PUBLISH_INTERVAL} minutes")

    # Start scheduler
    scheduler.start()
    print("="*60)
    print("✨ Scheduler started successfully")
    print("="*60 + "\n")


def stop_scheduler():
    """
    Stop background scheduler
    Called by FastAPI on shutdown
    """
    if scheduler.running:
        scheduler.shutdown(wait=True)
        print("🛑 Scheduler stopped")


def get_scheduled_jobs():
    """
    Get list of currently scheduled jobs

    Returns:
        List of job information dictionaries
    """
    jobs = []
    for job in scheduler.get_jobs():
        jobs.append({
            "id": job.id,
            "name": job.name,
            "next_run_time": str(job.next_run_time) if job.next_run_time else "Never",
            "trigger": str(job.trigger)
        })
    return jobs


if __name__ == "__main__":
    # Test scheduler
    print("Testing Scheduler...")

    # Start scheduler
    start_scheduler()

    # Show scheduled jobs
    jobs = get_scheduled_jobs()
    print("\n📋 Scheduled Jobs:")
    for job in jobs:
        print(f"  - {job['name']}: Next run at {job['next_run_time']}")

    # Keep alive for testing (remove in production)
    try:
        import time
        print("\n⏳ Scheduler running... Press Ctrl+C to stop")
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        stop_scheduler()
        print("\n👋 Scheduler stopped")
