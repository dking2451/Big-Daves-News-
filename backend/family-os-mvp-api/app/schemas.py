from typing import List, Optional

from pydantic import BaseModel, Field


class ExtractionRequest(BaseModel):
    ocrText: str = Field(min_length=1)
    sourceHint: Optional[str] = None


class EventCandidate(BaseModel):
    title: str
    childName: str = ""
    category: str = "other"
    date: Optional[str] = None  # YYYY-MM-DD
    startTime: Optional[str] = None  # HH:mm
    endTime: Optional[str] = None  # HH:mm
    location: str = ""
    notes: str = ""
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    ambiguityFlag: bool = False


class ExtractionResponse(BaseModel):
    candidates: List[EventCandidate]


class UploadResponse(BaseModel):
    uploadId: str
    filename: str
    contentType: str
    sizeBytes: int


class ErrorEnvelope(BaseModel):
    error: dict
