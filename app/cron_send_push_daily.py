from __future__ import annotations

import os
from datetime import datetime, timezone
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

from app.apns_push import send_daily_push_to_devices
from app.db import execute_query, get_connection
from app.push_devices import list_active_push_devices


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        print(f"Invalid int for {name}={raw!r}; using default {default}")
        return default


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name, "").strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "on"}


def _db_target_hint() -> str:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        db_path = os.getenv("DATA_DB_PATH", "data/big_daves_news.db").strip()
        return f"sqlite:{db_path}"
    normalized = database_url
    if normalized.startswith("postgres://"):
        normalized = "postgresql://" + normalized[len("postgres://") :]
    parsed = urlparse(normalized)
    host = parsed.hostname or "unknown-host"
    db_name = (parsed.path or "").lstrip("/") or "unknown-db"
    return f"{parsed.scheme}://{host}/{db_name}"


def _already_sent_today(local_date: str) -> bool:
    with get_connection() as conn:
        row = execute_query(
            conn,
            "SELECT send_date_local FROM daily_push_sends WHERE send_date_local = ? LIMIT 1",
            (local_date,),
        ).fetchone()
    return bool(row)


def _mark_sent_today(local_date: str, timezone_name: str) -> None:
    with get_connection() as conn:
        execute_query(
            conn,
            """
            INSERT INTO daily_push_sends(send_date_local, timezone_name, sent_at_utc)
            VALUES (?, ?, ?)
            """,
            (local_date, timezone_name, datetime.now(timezone.utc).isoformat()),
        )
        conn.commit()


def main() -> None:
    timezone_name = os.getenv("SCHEDULER_TIMEZONE", "America/Chicago")
    hour_target = _env_int("PUSH_SEND_HOUR_LOCAL", 8)
    minute_target = _env_int("PUSH_SEND_MINUTE_LOCAL", 0)
    window_minutes = _env_int("PUSH_SEND_WINDOW_MINUTES", 180)
    force_send = _env_bool("FORCE_SEND_PUSH_NOW", False)
    print(f"Push cron DB target: {_db_target_hint()}")

    hour_target = max(0, min(23, hour_target))
    minute_target = max(0, min(59, minute_target))

    try:
        now = datetime.now(ZoneInfo(timezone_name))
    except Exception as exc:
        print(f"Invalid timezone {timezone_name!r}: {exc}. Falling back to America/Chicago.")
        timezone_name = "America/Chicago"
        now = datetime.now(ZoneInfo(timezone_name))

    latest_minute = min(59, minute_target + max(window_minutes, 0))
    in_send_window = (
        now.hour == hour_target
        and now.minute >= minute_target
        and now.minute <= latest_minute
    )
    local_date = now.strftime("%Y-%m-%d")

    if _already_sent_today(local_date):
        print(f"Skip push: already sent for local_date={local_date} tz={timezone_name}")
        return
    if not in_send_window and not force_send:
        print(
            "Skip push: "
            f"now={now.isoformat()} "
            f"target={hour_target:02d}:{minute_target:02d} "
            f"window={window_minutes}m "
            f"tz={timezone_name}"
        )
        return

    devices = list_active_push_devices(platform="ios", limit=5000)
    if not devices:
        print("Skip push: no active iOS tokens registered.")
        return

    report_url = os.getenv("REPORT_URL", "https://big-daves-news-web.onrender.com/").strip()
    bundle_id = os.getenv("APNS_BUNDLE_ID", "").strip()
    title = os.getenv("PUSH_ALERT_TITLE", "Big Daves News").strip() or "Big Daves News"
    body = os.getenv(
        "PUSH_ALERT_BODY",
        "Your daily brief is ready. Open the app for the latest headlines.",
    ).strip() or "Your daily brief is ready. Open the app for the latest headlines."

    summary = send_daily_push_to_devices(
        devices=devices,
        title=title,
        body=body,
        report_url=report_url,
        bundle_id=bundle_id,
    )
    _mark_sent_today(local_date, timezone_name)
    print(
        "Daily push completed: "
        f"sent={summary.sent} failed={summary.failed} disabled={summary.disabled}"
    )


if __name__ == "__main__":
    main()
