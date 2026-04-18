"""Stage G: explainable confidence — not only 'more fields filled'."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from ..schemas_extraction import RecurrenceKind, ReviewStatus


def score_event(event: Dict[str, Any], *, base: Optional[float] = None) -> float:
    """
    Penalize vague time, partial location, inferred year, conflicts, low evidence.
    Start from model confidence or neutral mid-band.
    """
    score = float(base) if base is not None else float(event.get("modelConfidence") or 0.55)
    score = max(0.0, min(1.0, score))

    tq = str(event.get("timeQualifier") or "").lower()
    if tq in ("vague", "unknown"):
        score -= 0.18
    elif tq == "approximate":
        score -= 0.10

    lq = str(event.get("locationQualifier") or "").lower()
    if lq == "partial":
        score -= 0.12
    elif lq == "unknown":
        score -= 0.08

    if event.get("ambiguityReasons"):
        score -= 0.06 * min(3, len(event["ambiguityReasons"]))

    inferred = event.get("inferredFields") or []
    score -= 0.04 * min(4, len(inferred))

    unresolved = event.get("unresolvedFields") or []
    score -= 0.05 * min(5, len(unresolved))

    ev: List[Any] = event.get("evidence") or []
    if len(ev) < 2 and (event.get("title") or "").strip():
        score -= 0.06

    rec = event.get("recurrence") or {}
    try:
        rk = RecurrenceKind(str(rec.get("kind") or "unknown"))
    except ValueError:
        rk = RecurrenceKind.unknown
    if rk in (
        RecurrenceKind.recurrence_pattern,
        RecurrenceKind.season_window,
        RecurrenceKind.two_specific_dates,
    ):
        score -= 0.05

    return max(0.05, min(0.98, score))


def review_status_for_score(confidence: float, ambiguity: bool) -> ReviewStatus:
    if ambiguity and confidence < 0.45:
        return ReviewStatus.low_confidence_manual_fix
    if confidence >= 0.72 and not ambiguity:
        return ReviewStatus.high_confidence_auto_ready
    if confidence < 0.45:
        return ReviewStatus.low_confidence_manual_fix
    return ReviewStatus.medium_confidence_review
