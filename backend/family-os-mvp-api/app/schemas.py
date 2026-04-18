from typing import List, Optional

from pydantic import BaseModel, Field, field_validator

from .schemas_extraction import (
    ExtractionReviewSummary,
    NonEventCandidate,
    PipelineTrace,
    RichEventCandidate,
)


class ExtractionRequest(BaseModel):
    ocrText: str = Field(min_length=1)
    sourceHint: Optional[str] = None

    @field_validator("ocrText")
    @classmethod
    def validate_text(cls, value: str) -> str:
        trimmed = value.strip()
        if not trimmed:
            raise ValueError("ocrText cannot be blank")
        return trimmed


class EventCandidate(BaseModel):
    title: str
    childName: str = ""
    childNeedsAssignment: bool = Field(
        default=False,
        description="True if no specific child is named on the flyer — user should assign in review.",
    )
    category: str = "other"
    date: Optional[str] = None  # YYYY-MM-DD
    startTime: Optional[str] = None  # HH:mm
    endTime: Optional[str] = None  # HH:mm
    location: str = ""
    notes: str = ""
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    ambiguityFlag: bool = False


class ExtractionResponse(BaseModel):
    """Legacy `candidates` remains the primary contract for iOS; v2 adds optional rich payloads."""

    candidates: List[EventCandidate]
    events: Optional[List[RichEventCandidate]] = None
    nonEventCandidates: List[NonEventCandidate] = Field(default_factory=list)
    review: Optional[ExtractionReviewSummary] = None
    extractionVersion: str = "1"
    pipelineTrace: Optional[PipelineTrace] = None


class UploadResponse(BaseModel):
    uploadId: str
    filename: str
    contentType: str
    sizeBytes: int


class ErrorEnvelope(BaseModel):
    error: dict
