"""Orchestrate preprocess → staged LLM → ambiguity → normalize → venue → review → compatibility."""

from __future__ import annotations

import os
import time
from datetime import date
from typing import Any, Dict, List

from ..schemas import ExtractionRequest, ExtractionResponse
from ..schemas_extraction import PipelineTrace, PipelineTraceStage
from .ambiguity import apply_ambiguity_rules
from .compatibility import (
    _expand_multi_date_events,
    dict_to_rich_candidate,
    non_event_from_dict,
    rich_to_legacy,
)
from .llm.stages import run_stage1, run_stage2
from .preprocess import preprocess_ocr
from .review import build_extraction_summary
from .venue import NoopVenueResolver, VenueResolver


def run_pipeline(
    payload: ExtractionRequest,
    *,
    resolver: VenueResolver | None = None,
) -> ExtractionResponse:
    resolver = resolver or NoopVenueResolver()
    ref = date.today().isoformat()
    trace_stages: List[PipelineTraceStage] = []
    t_all = time.perf_counter()

    t0 = time.perf_counter()
    doc = preprocess_ocr(payload.ocrText)
    trace_stages.append(
        PipelineTraceStage(name="preprocess", durationMs=(time.perf_counter() - t0) * 1000, detail={"lines": len(doc.lines)})
    )

    t0 = time.perf_counter()
    stage1: Dict[str, Any] = run_stage1(doc, reference_date_iso=ref, source_hint=payload.sourceHint)
    trace_stages.append(
        PipelineTraceStage(
            name="stage1_document",
            durationMs=(time.perf_counter() - t0) * 1000,
            detail={"chunks": len(stage1.get("chunks") or []), "segments": len(stage1.get("eventSegments") or [])},
        )
    )

    t0 = time.perf_counter()
    stage2: Dict[str, Any] = run_stage2(doc, stage1, reference_date_iso=ref, source_hint=payload.sourceHint)
    trace_stages.append(
        PipelineTraceStage(
            name="stage2_fields",
            durationMs=(time.perf_counter() - t0) * 1000,
            detail={"events": len(stage2.get("events") or [])},
        )
    )

    raw_events: List[Dict[str, Any]] = list(stage2.get("events") or [])
    processed: List[Dict[str, Any]] = []
    for ev in raw_events:
        processed.append(apply_ambiguity_rules(dict(ev)))

    processed = _expand_multi_date_events(processed)

    rich_list = []
    legacy_list = []
    for ev in processed:
        rich, _ = dict_to_rich_candidate(ev, resolver)
        rich_list.append(rich)
        legacy_list.append(rich_to_legacy(rich))

    non_events: List[Any] = []
    for row in stage2.get("nonEvents") or []:
        try:
            non_events.append(non_event_from_dict(dict(row)))
        except Exception:
            continue

    if not non_events:
        for row in stage1.get("nonEvents") or []:
            r = dict(row)
            if not r.get("summary") and not r.get("lineIds"):
                continue
            try:
                non_events.append(
                    non_event_from_dict(
                        {
                            "kind": r.get("kind") or "general_note",
                            "title": "",
                            "summary": str(r.get("summary") or ""),
                            "lineIds": r.get("lineIds") or [],
                            "dueDate": r.get("dueDate"),
                            "confidence": 0.45,
                        }
                    )
                )
            except Exception:
                continue

    doc_notes: List[str] = list(stage1.get("documentNotes") or [])
    review = build_extraction_summary([r.model_dump() for r in rich_list], doc_notes)

    trace_stages.append(
        PipelineTraceStage(
            name="total",
            durationMs=(time.perf_counter() - t_all) * 1000,
            detail={"candidates": len(legacy_list)},
        )
    )

    return ExtractionResponse(
        candidates=legacy_list,
        events=rich_list,
        nonEventCandidates=non_events,
        review=review,
        extractionVersion="2",
        pipelineTrace=PipelineTrace(
            stages=trace_stages,
            model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
        ),
    )
