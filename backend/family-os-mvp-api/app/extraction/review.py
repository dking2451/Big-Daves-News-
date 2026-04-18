"""Stage 8: review metadata for UI — why review, suggested actions."""

from __future__ import annotations

from typing import Any, Dict, List

from ..schemas_extraction import EventReviewHints, ExtractionReviewSummary, ReviewStatus
from .confidence import review_status_for_score


def build_event_review(event: Dict[str, Any], confidence: float, ambiguity: bool) -> EventReviewHints:
    status = review_status_for_score(confidence, ambiguity)
    reasons: List[str] = list(event.get("ambiguityReasons") or [])
    actions: List[str] = []

    if status == ReviewStatus.low_confidence_manual_fix:
        actions.append("Confirm date, time, and location against the original flyer.")
    elif status == ReviewStatus.medium_confidence_review:
        actions.append("Quick review: verify times and address before saving.")

    if event.get("unresolvedFields"):
        actions.append(f"Unresolved fields: {', '.join(event['unresolvedFields'])}.")

    if event.get("childNeedsAssignment"):
        actions.append("Assign which child this event applies to.")

    return EventReviewHints(status=status, reasons=reasons, suggestedActions=actions)


def build_extraction_summary(events: List[Dict[str, Any]], doc_notes: List[str]) -> ExtractionReviewSummary:
    needing = sum(1 for e in events if e.get("reviewRequired") or e.get("ambiguityFlag"))
    overall = ReviewStatus.medium_confidence_review
    if not events:
        overall = ReviewStatus.low_confidence_manual_fix
    elif needing == 0:
        overall = ReviewStatus.high_confidence_auto_ready
    elif needing >= len(events) and len(events) > 0:
        overall = ReviewStatus.low_confidence_manual_fix

    return ExtractionReviewSummary(
        documentSummary="; ".join(doc_notes[:3]) if doc_notes else "",
        overallStatus=overall,
        eventsNeedingReview=needing,
        pipelineNotes=list(doc_notes or []),
    )
