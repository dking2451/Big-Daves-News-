import re
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
        start_raw = _clean_optional(item.get("startTime"))
        end_raw = _clean_optional(item.get("endTime"))

        date_value = date_value if _is_valid_date(date_value) else None
        start_value = _normalize_time_to_hhmm(start_raw)
        end_value = _normalize_time_to_hhmm(end_raw)

        # Ambiguity when start is missing or unknown; missing end is OK (games often list start only).
        ambiguity = bool(item.get("ambiguityFlag", False)) or start_value is None

        title_clean = str(item.get("title", "")).strip() or "Untitled Event"
        child_clean = str(item.get("childName", "")).strip()
        needs_child = bool(item.get("childNeedsAssignment", False))

        # Heuristic: team / event titles were sometimes copied into childName — same as title is never a person.
        if child_clean and child_clean.casefold() == title_clean.casefold():
            child_clean = ""
            needs_child = True

        candidate = EventCandidate(
            title=title_clean,
            childName=child_clean,
            childNeedsAssignment=needs_child,
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


def _normalize_time_to_hhmm(value: str | None) -> str | None:
    """Accept 24h (17:30), 12h (5:30 PM / 5:30PM), and normalize to HH:mm for API + iOS parsers."""
    if value is None:
        return None
    s = str(value).strip().strip("\"'")
    if not s:
        return None
    s = re.sub(r"\s+", " ", s)
    for fmt in ("%H:%M", "%H:%M:%S"):
        try:
            return datetime.strptime(s, fmt).strftime("%H:%M")
        except ValueError:
            pass
    compact = re.sub(r"\s+", "", s.upper())
    m = re.match(r"^(\d{1,2}):(\d{2})(AM|PM)$", compact)
    if m:
        h, mi = int(m.group(1)), int(m.group(2))
        ap = m.group(3)
        if not (1 <= h <= 12 and 0 <= mi <= 59):
            return None
        is_pm = ap == "PM"
        if is_pm:
            h24 = 12 if h == 12 else h + 12
        else:
            h24 = 0 if h == 12 else h
        return f"{h24:02d}:{mi:02d}"
    return None
