"""Map rich pipeline rows to legacy `EventCandidate` + Pydantic rich models."""

from __future__ import annotations

from typing import Any, Dict, List, Tuple

from ..schemas import EventCandidate
from ..schemas_extraction import (
    FieldEvidence,
    NonEventCandidate,
    NonEventKind,
    RecurrencePayload,
    ReviewStatus,
    RichEventCandidate,
    SourceType,
    VenueCandidate,
)
from .ambiguity import evidence_dicts_to_models
from .confidence import score_event
from .normalize import normalize_end_date, normalize_time_to_hhmm
from .review import build_event_review
from .venue import NoopVenueResolver, VenueResolver, apply_venue_resolution


def _source_type(s: str) -> SourceType:
    try:
        return SourceType(s)
    except ValueError:
        return SourceType.unknown


def _recurrence_from_dict(r: Dict[str, Any] | None) -> RecurrencePayload | None:
    if not r:
        return None
    from ..schemas_extraction import RecurrenceKind

    kind_str = str(r.get("kind") or "unknown")
    try:
        kind = RecurrenceKind(kind_str)
    except ValueError:
        kind = RecurrenceKind.unknown
    return RecurrencePayload(
        kind=kind,
        humanReadable=str(r.get("humanReadable") or ""),
        rrule=r.get("rrule"),
        seasonStart=r.get("seasonStart"),
        seasonEnd=r.get("seasonEnd"),
        byDay=[str(x) for x in (r.get("byDay") or [])],
        extraDates=[str(x) for x in (r.get("extraDates") or [])],
    )


def _expand_multi_date_events(raw_events: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Split rows with extraDates into one dict per concrete date when needed for legacy."""
    out: List[Dict[str, Any]] = []
    for ev in raw_events:
        extras = (ev.get("recurrence") or {}).get("extraDates") or []
        if isinstance(extras, list) and len(extras) > 1:
            for d in extras:
                clone = dict(ev)
                rec = dict(ev.get("recurrence") or {})
                rec["extraDates"] = []
                rec["kind"] = "single"
                clone["date"] = d
                clone["recurrence"] = rec
                out.append(clone)
        else:
            out.append(ev)
    return out


def dict_to_rich_candidate(
    ev: Dict[str, Any],
    resolver: VenueResolver,
) -> Tuple[RichEventCandidate, Dict[str, Any]]:
    """Returns rich model + normalized dict for confidence (with venue attached)."""
    ev = dict(ev)
    location_raw = str(ev.get("locationRaw") or "").strip()

    venue: VenueCandidate | None = apply_venue_resolution(location_raw, resolver)
    if venue is None and location_raw:
        venue = NoopVenueResolver().resolve(location_raw)

    start = normalize_time_to_hhmm(_opt(ev.get("startTime")))
    end = normalize_time_to_hhmm(_opt(ev.get("endTime")))
    date_v = _opt(ev.get("date"))
    end_date_v = normalize_end_date(_opt(ev.get("endDate")))

    evidence = evidence_dicts_to_models(list(ev.get("evidence") or []))
    recurrence = _recurrence_from_dict(ev.get("recurrence"))

    base_conf = score_event(ev, base=float(ev.get("modelConfidence") or 0.55))

    ambiguity = bool(ev.get("ambiguityFlag")) or start is None or bool(ev.get("ambiguityReasons"))
    if ev.get("timeQualifier") in ("vague", "unknown") and not start:
        ambiguity = True

    review_hints = build_event_review(ev, base_conf, ambiguity)

    rich = RichEventCandidate(
        title=str(ev.get("title") or "Untitled Event").strip() or "Untitled Event",
        childName=str(ev.get("childName") or "").strip(),
        childNeedsAssignment=_child_needs_assignment(ev),
        category=_category(ev.get("category")),
        date=date_v if _valid_iso_date(date_v) else None,
        endDate=end_date_v,
        startTime=start,
        endTime=end,
        locationRaw=location_raw,
        locationResolved=venue,
        notes=str(ev.get("notes") or "").strip(),
        organizerContact=str(ev.get("organizerContact") or "").strip(),
        confidence=base_conf,
        ambiguityFlag=ambiguity,
        ambiguityReasons=list(ev.get("ambiguityReasons") or []),
        reviewRequired=review_hints.status != ReviewStatus.high_confidence_auto_ready,
        evidenceSpans=evidence,
        inferredFields=list(ev.get("inferredFields") or []),
        unresolvedFields=list(ev.get("unresolvedFields") or []),
        sourceType=_source_type(str(ev.get("sourceType") or "unknown")),
        recurrence=recurrence,
        review=review_hints,
    )
    meta = {"confidence": base_conf, "ambiguity": ambiguity}
    return rich, meta


def rich_to_legacy(rich: RichEventCandidate) -> EventCandidate:
    """Single legacy row; `location` mirrors `locationRaw`."""
    return EventCandidate(
        title=rich.title,
        childName=rich.childName,
        childNeedsAssignment=rich.childNeedsAssignment,
        category=rich.category if rich.category in {"school", "sports", "medical", "social", "other"} else "other",
        date=rich.date,
        startTime=rich.startTime,
        endTime=rich.endTime,
        location=rich.locationRaw,
        notes=rich.notes,
        confidence=rich.confidence,
        ambiguityFlag=rich.ambiguityFlag,
    )


def _opt(v: Any) -> str | None:
    if v is None:
        return None
    s = str(v).strip()
    return s if s else None


def _valid_iso_date(s: str | None) -> bool:
    if not s:
        return False
    from datetime import datetime

    try:
        datetime.strptime(s, "%Y-%m-%d")
        return True
    except ValueError:
        return False


def non_event_from_dict(row: Dict[str, Any]) -> NonEventCandidate:
    kind_str = str(row.get("kind") or "general_note")
    try:
        kind = NonEventKind(kind_str)
    except ValueError:
        kind = NonEventKind.general_note
    line_ids = [str(x) for x in (row.get("lineIds") or [])]
    fe = FieldEvidence(field="summary", text=str(row.get("summary") or ""), lineIds=line_ids)
    return NonEventCandidate(
        kind=kind,
        title=str(row.get("title") or ""),
        summary=str(row.get("summary") or ""),
        rawText=str(row.get("rawText") or row.get("summary") or ""),
        dueDate=_opt(row.get("dueDate")),
        evidenceSpans=[fe],
        confidence=float(row.get("confidence") or 0.5),
    )


def _child_needs_assignment(ev: Dict[str, Any]) -> bool:
    if "childNeedsAssignment" in ev:
        return bool(ev.get("childNeedsAssignment"))
    return not bool(str(ev.get("childName") or "").strip())


_VALID_CAT = {"school", "sports", "medical", "social", "other"}


def _category(raw: Any) -> str:
    c = str(raw or "other").lower().strip()
    return c if c in _VALID_CAT else "other"
