"""Internal types for the v2 extraction pipeline."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List


@dataclass
class Line:
    """Single preprocessed line with stable id for evidence."""

    id: str
    text: str


@dataclass
class PreprocessedDoc:
    """OCR after cleanup with numbered lines."""

    lines: List[Line]
    raw: str

    def line_map_text(self) -> str:
        """Human-readable numbered lines for LLM."""
        return "\n".join(f"{ln.id}: {ln.text}" for ln in self.lines)


@dataclass
class Segment:
    """One event boundary candidate (line id range)."""

    segment_id: str
    start_line_idx: int
    end_line_idx: int
    kind: str = "event"
    notes: str = ""


@dataclass
class PipelineContext:
    """Shared context across stages."""

    source_hint: str | None = None
    reference_date_iso: str = ""
    trace: list = field(default_factory=list)
