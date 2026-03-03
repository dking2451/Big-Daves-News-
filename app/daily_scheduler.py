from __future__ import annotations

import argparse
import logging
import os
from zoneinfo import ZoneInfo

from apscheduler.schedulers.blocking import BlockingScheduler
from dotenv import load_dotenv

from app.email_report import send_daily_email


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger(__name__)


def run_job() -> None:
    try:
        result = send_daily_email()
        logger.info("Daily email sent. Result=%s", result)
    except Exception as exc:  # pragma: no cover - runtime safety
        logger.exception("Daily email job failed: %s", exc)


def main() -> None:
    load_dotenv()
    parser = argparse.ArgumentParser(description="Daily report email scheduler")
    parser.add_argument(
        "--send-now",
        action="store_true",
        help="Send email immediately and exit",
    )
    args = parser.parse_args()

    if args.send_now:
        run_job()
        return

    timezone_name = os.getenv("SCHEDULER_TIMEZONE", "America/Chicago")
    timezone = ZoneInfo(timezone_name)
    scheduler = BlockingScheduler(timezone=timezone)

    scheduler.add_job(
        run_job,
        trigger="cron",
        hour=8,
        minute=0,
        id="daily_email_report",
        replace_existing=True,
        misfire_grace_time=3600,
        coalesce=True,
    )

    logger.info("Scheduler started. Daily email at 08:00 %s", timezone_name)
    scheduler.start()


if __name__ == "__main__":
    main()
