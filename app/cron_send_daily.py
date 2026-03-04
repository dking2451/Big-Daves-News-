from __future__ import annotations

import os
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from app.db import execute_query, get_connection
from app.email_report import send_daily_email


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


def _already_sent_today(local_date: str) -> bool:
    with get_connection() as conn:
        row = execute_query(
            conn,
            "SELECT send_date_local FROM daily_email_sends WHERE send_date_local = ? LIMIT 1",
            (local_date,),
        ).fetchone()
    return bool(row)


def _mark_sent_today(local_date: str, timezone_name: str) -> None:
    with get_connection() as conn:
        execute_query(
            conn,
            """
            INSERT INTO daily_email_sends(send_date_local, timezone_name, sent_at_utc)
            VALUES (?, ?, ?)
            """,
            (local_date, timezone_name, datetime.now(timezone.utc).isoformat()),
        )
        conn.commit()


def main() -> None:
    timezone_name = os.getenv("SCHEDULER_TIMEZONE", "America/Chicago")
    hour_target = _env_int("DAILY_SEND_HOUR_LOCAL", 8)
    minute_target = _env_int("DAILY_SEND_MINUTE_LOCAL", 0)
    window_minutes = _env_int("DAILY_SEND_WINDOW_MINUTES", 180)
    force_send = _env_bool("FORCE_SEND_NOW", False)

    # Keep scheduling guardrails sane even with bad env config.
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
        print(
            "Skip send: "
            f"already sent for local_date={local_date} "
            f"tz={timezone_name}"
        )
        return

    if not in_send_window and not force_send:
        # Safe no-op when cron runs at other times.
        print(
            "Skip send: "
            f"now={now.isoformat()} "
            f"target={hour_target:02d}:{minute_target:02d} "
            f"window={window_minutes}m "
            f"tz={timezone_name}"
        )
        return

    result = send_daily_email()
    _mark_sent_today(local_date, timezone_name)
    print(f"Daily send completed: {result}")


if __name__ == "__main__":
    main()
