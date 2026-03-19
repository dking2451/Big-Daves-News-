from datetime import datetime
from typing import List

from .schemas import EventCandidate


VALID_CATEGORIES = {"school", "sports", "medical", "social", "other"}


def normalize_candidates(raw_candidates: List[dict]) -> List[EventCandidate]:
    normalized: List[EventCandidate] = []
    for item in raw_candidates:
        category = str(item.get("category", "other")).lower().strip()
        if category not in VALID_CATEGORIES:
            category = "other"

        date_value = _clean_optional(item.get("date"))
        start_value = _clean_optional(item.get("startTime"))
        end_value = _clean_optional(item.get("endTime"))

        date_value = date_value if _is_valid_date(date_value) else None
        start_value = start_value if _is_valid_time(start_value) else None
        end_value = end_value if _is_valid_time(end_value) else None

        # Ambiguity policy: when time is unclear/missing, ambiguityFlag must be true.
        ambiguity = bool(item.get("ambiguityFlag", False)) or start_value is None or end_value is None

        candidate = EventCandidate(
            title=str(item.get("title", "")).strip() or "Untitled Event",
            childName=str(item.get("childName", "")).strip(),
            category=category,
            date=date_value,
            startTime=start_value,
            endTime=end_value,
            location=str(item.get("location", "")).strip(),
            notes=str(item.get("notes", "")).strip(),
            confidence=_safe_confidence(item.get("confidence")),
            ambiguityFlag=ambiguity,
        )
        normalized.append(candidate)
    return normalized


def _clean_optional(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None


def _safe_confidence(value: object) -> float:
    try:
        num = float(value)
        if num < 0:
            return 0.0
        if num > 1:
            return 1.0
        return num
    except (TypeError, ValueError):
        return 0.0


def _is_valid_date(value: str | None) -> bool:
    if value is None:
        return False
    try:
        datetime.strptime(value, "%Y-%m-%d")
        return True
    except ValueError:
        return False


def _is_valid_time(value: str | None) -> bool:
    if value is None:
        return False
    try:
        datetime.strptime(value, "%H:%M")
        return True
    except ValueError:
        return False
