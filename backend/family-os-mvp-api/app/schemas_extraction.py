"""Rich extraction models (v2 pipeline). Legacy flat `EventCandidate` stays in `schemas.py`."""

from __future__ import annotations

from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class FieldBinding(str, Enum):
    """How a field value was obtained."""

    explicit = "explicit"
    inferred = "inferred"
    unresolved = "unresolved"
    conflicting = "conflicting"
    vague = "vague"


class ReviewStatus(str, Enum):
    """UI-oriented review bucket."""

    high_confidence_auto_ready = "high_confidence_auto_ready"
    medium_confidence_review = "medium_confidence_review"
    low_confidence_manual_fix = "low_confidence_manual_fix"


class NonEventKind(str, Enum):
    """Non-calendar row classification."""

    registration_deadline = "registration_deadline"
    sign_up_reminder = "sign_up_reminder"
    equipment_reminder = "equipment_reminder"
    contact_block = "contact_block"
    pricing_info = "pricing_info"
    general_note = "general_note"
    unrelated = "unrelated"


class SourceType(str, Enum):
    """Provenance of the extraction row."""

    flyer = "flyer"
    email = "email"
    chat = "chat"
    screenshot = "screenshot"
    pasted_text = "pasted_text"
    unknown = "unknown"


class RecurrenceKind(str, Enum):
    """Temporal shape for an event row."""

    single = "single"
    multi_day_range = "multi_day_range"
    recurrence_pattern = "recurrence_pattern"
    two_specific_dates = "two_specific_dates"
    season_window = "season_window"
    deadline_only = "deadline_only"
    unknown = "unknown"


class FieldEvidence(BaseModel):
    """Snippet + optional line references into preprocessed OCR."""

    field: str = Field(description="Logical field name, e.g. title, startTime")
    text: str = Field(default="", description="Verbatim or near-verbatim supporting snippet")
    lineIds: List[str] = Field(default_factory=list, description="e.g. L3, L4 from preprocess")
    binding: FieldBinding = Field(default=FieldBinding.explicit)


class VenueCandidate(BaseModel):
    """Optional geocoding / name normalization — never replaces raw text."""

    rawQuery: str = ""
    normalizedName: Optional[str] = None
    formattedAddress: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    unresolved: bool = True


class RecurrencePayload(BaseModel):
    """Structured recurrence when not a single calendar row."""

    kind: RecurrenceKind = RecurrenceKind.unknown
    humanReadable: str = ""
    rrule: Optional[str] = None
    seasonStart: Optional[str] = None
    seasonEnd: Optional[str] = None
    byDay: List[str] = Field(default_factory=list)
    extraDates: List[str] = Field(default_factory=list, description="ISO YYYY-MM-DD")


class NonEventCandidate(BaseModel):
    """Deadlines, reminders, contacts — not forced into calendar events."""

    kind: NonEventKind = NonEventKind.general_note
    title: str = ""
    summary: str = ""
    rawText: str = ""
    dueDate: Optional[str] = None
    evidenceSpans: List[FieldEvidence] = Field(default_factory=list)
    confidence: float = Field(default=0.5, ge=0.0, le=1.0)


class EventReviewHints(BaseModel):
    """Per-event review UX."""

    status: ReviewStatus = ReviewStatus.medium_confidence_review
    reasons: List[str] = Field(default_factory=list)
    suggestedActions: List[str] = Field(default_factory=list)


class RichEventCandidate(BaseModel):
    """Full extraction row with evidence and ambiguity tracking."""

    title: str
    childName: str = ""
    childNeedsAssignment: bool = False
    category: str = "other"
    date: Optional[str] = None
    endDate: Optional[str] = None
    startTime: Optional[str] = None
    endTime: Optional[str] = None
    locationRaw: str = ""
    locationResolved: Optional[VenueCandidate] = None
    notes: str = ""
    organizerContact: str = ""
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    ambiguityFlag: bool = False
    ambiguityReasons: List[str] = Field(default_factory=list)
    reviewRequired: bool = False
    evidenceSpans: List[FieldEvidence] = Field(default_factory=list)
    inferredFields: List[str] = Field(default_factory=list)
    unresolvedFields: List[str] = Field(default_factory=list)
    sourceType: SourceType = SourceType.unknown
    recurrence: Optional[RecurrencePayload] = None
    review: Optional[EventReviewHints] = None


class ExtractionReviewSummary(BaseModel):
    """Top-level review metadata for the response."""

    documentSummary: str = ""
    overallStatus: ReviewStatus = ReviewStatus.medium_confidence_review
    eventsNeedingReview: int = 0
    pipelineNotes: List[str] = Field(default_factory=list)


class PipelineTraceStage(BaseModel):
    name: str
    durationMs: float = 0.0
    detail: Dict[str, Any] = Field(default_factory=dict)


class PipelineTrace(BaseModel):
    stages: List[PipelineTraceStage] = Field(default_factory=list)
    model: str = ""
