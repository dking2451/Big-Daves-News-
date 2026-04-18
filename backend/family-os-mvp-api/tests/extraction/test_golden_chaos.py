"""
Golden-style scenarios for messy parent inputs (deterministic layers only; no live LLM).

These strings document expected pipeline stress cases; extend with mocked stage1/2 when needed.
"""

import pytest

from app.extraction.ambiguity import apply_ambiguity_rules
from app.extraction.confidence import score_event
from app.extraction.preprocess import preprocess_ocr


# Examples from product spec — kept as documentation + preprocess smoke checks.
FLYER_OPEN_GYM = """Fridays 6:30–9 PM, Starts April 4, East Cardinal MS Gym, $5 cash, Ages 13–18"""
MOVIE_VAGUE = """Movie starts after sunset (~8ish), City Hall Plaza Park, April 12"""
TWO_DATES = """April 6 & April 8, 6–8 PM, Gabe Nesbitt Community Park"""
CAMP_RANGE = """June 10–12, 9 AM–12 PM, Z-Plex"""
RECURRING = """Tues / Thurs evenings, Fields @ HS, March 23 – May 18"""
DEADLINE = """Register by 3/15"""
BRING = """Bring chairs + blankets"""
NO_LUNCH = """No lunch included"""
HANDWRITTEN = """Emma soccer!!\nOfficial schedule below\nSaturday 9 AM Field 2"""
CONFLICT = """Game time 9:00 AM\nArrive 8:30 AM for photos\nCoach note: also 10:00 AM scrimmage"""


@pytest.mark.parametrize(
    "text,min_lines",
    [
        (FLYER_OPEN_GYM, 1),
        (MOVIE_VAGUE, 1),
        (TWO_DATES, 1),
        (CAMP_RANGE, 1),
        (RECURRING, 1),
        (DEADLINE, 1),
        (BRING, 1),
        (NO_LUNCH, 1),
        (HANDWRITTEN, 3),
        (CONFLICT, 3),
    ],
)
def test_preprocess_preserves_lines(text, min_lines):
    doc = preprocess_ocr(text)
    assert len(doc.lines) >= min_lines


def test_confidence_penalizes_vague_time():
    ev = {
        "timeQualifier": "vague",
        "locationQualifier": "full",
        "evidence": [{"field": "title", "binding": "explicit"}],
        "ambiguityReasons": [],
        "inferredFields": [],
        "unresolvedFields": [],
        "recurrence": {"kind": "single"},
        "modelConfidence": 0.85,
    }
    s = score_event(ev, base=0.85)
    assert s < 0.75


def test_ambiguity_marks_recurring_without_date():
    ev = apply_ambiguity_rules(
        {
            "title": "Practice",
            "date": None,
            "recurrence": {"kind": "recurrence_pattern", "humanReadable": "Mon/Wed"},
            "evidence": [],
        }
    )
    assert "date" in ev["unresolvedFields"]
