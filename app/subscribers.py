from __future__ import annotations

import json
import re
from pathlib import Path

SUBSCRIBERS_PATH = Path("data/subscribers.json")
MAX_SUBSCRIBERS = 10


def _ensure_store() -> None:
    if not SUBSCRIBERS_PATH.exists():
        SUBSCRIBERS_PATH.parent.mkdir(parents=True, exist_ok=True)
        SUBSCRIBERS_PATH.write_text(json.dumps({"emails": []}, indent=2))


def load_subscribers() -> list[str]:
    _ensure_store()
    payload = json.loads(SUBSCRIBERS_PATH.read_text())
    emails = payload.get("emails", [])
    return [str(email).strip().lower() for email in emails if str(email).strip()]


def save_subscribers(emails: list[str]) -> None:
    unique = []
    seen = set()
    for email in emails:
        normalized = email.strip().lower()
        if normalized and normalized not in seen:
            seen.add(normalized)
            unique.append(normalized)
    SUBSCRIBERS_PATH.write_text(json.dumps({"emails": unique[:MAX_SUBSCRIBERS]}, indent=2))


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
