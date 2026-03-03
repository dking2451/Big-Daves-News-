from __future__ import annotations

import os
from datetime import datetime
from zoneinfo import ZoneInfo

from app.email_report import send_daily_email


def main() -> None:
    timezone_name = os.getenv("SCHEDULER_TIMEZONE", "America/Chicago")
    hour_target = int(os.getenv("DAILY_SEND_HOUR_LOCAL", "8"))
    minute_target = int(os.getenv("DAILY_SEND_MINUTE_LOCAL", "0"))

    now = datetime.now(ZoneInfo(timezone_name))
    if now.hour != hour_target or now.minute > minute_target + 10:
        # Safe no-op when cron runs at other times.
        print(
            f"Skip send: now={now.isoformat()} target={hour_target:02d}:{minute_target:02d} {timezone_name}"
        )
        return

    result = send_daily_email()
    print(f"Daily send completed: {result}")


if __name__ == "__main__":
    main()
