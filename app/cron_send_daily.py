from __future__ import annotations

import os
from datetime import datetime
from zoneinfo import ZoneInfo

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


def main() -> None:
    timezone_name = os.getenv("SCHEDULER_TIMEZONE", "America/Chicago")
    hour_target = _env_int("DAILY_SEND_HOUR_LOCAL", 8)
    minute_target = _env_int("DAILY_SEND_MINUTE_LOCAL", 0)
    window_minutes = _env_int("DAILY_SEND_WINDOW_MINUTES", 59)

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
    if not in_send_window:
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
    print(f"Daily send completed: {result}")


if __name__ == "__main__":
    main()
