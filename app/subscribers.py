from __future__ import annotations

import re
from datetime import datetime, timezone

from app.db import execute_query, get_connection

MAX_SUBSCRIBERS = 10


def load_subscribers() -> list[str]:
    with get_connection() as conn:
        rows = execute_query(conn, "SELECT email FROM subscribers ORDER BY created_at ASC").fetchall()
    return [str(row["email"]).strip().lower() for row in rows if str(row["email"]).strip()]


def save_subscribers(emails: list[str]) -> None:
    unique = []
    seen = set()
    for email in emails:
        normalized = email.strip().lower()
        if normalized and normalized not in seen:
            seen.add(normalized)
            unique.append(normalized)
    trimmed = unique[:MAX_SUBSCRIBERS]
    with get_connection() as conn:
        execute_query(conn, "DELETE FROM subscribers")
        for email in trimmed:
            execute_query(
                conn,
                "INSERT INTO subscribers(email, created_at) VALUES (?, ?)",
                (email, datetime.now(timezone.utc).isoformat()),
            )
        conn.commit()


def is_valid_email(email: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", email.strip()))


def add_subscriber(email: str) -> tuple[bool, str, int]:
    normalized = email.strip().lower()
    if not is_valid_email(normalized):
        return False, "Please enter a valid email address.", len(load_subscribers())

    emails = load_subscribers()
    if normalized in emails:
        return False, "This email is already subscribed.", len(emails)
    if len(emails) >= MAX_SUBSCRIBERS:
        return False, f"Subscriber limit reached ({MAX_SUBSCRIBERS}).", len(emails)

    emails.append(normalized)
    save_subscribers(emails)
    return True, "Added successfully. You will receive daily report emails.", len(emails)
