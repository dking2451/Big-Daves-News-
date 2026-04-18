"""Stage 1: document chunks + event segments. Stage 2: field extraction with evidence."""

from __future__ import annotations

from typing import Any, Dict, List

from ..types import PreprocessedDoc
from .client import chat_json
from .prompts import STAGE1_SYSTEM, STAGE2_SYSTEM


def run_stage1(
    doc: PreprocessedDoc,
    *,
    reference_date_iso: str,
    source_hint: str | None,
) -> Dict[str, Any]:
    user = (
        f"Reference date: {reference_date_iso}\n"
        f"Source hint: {source_hint or 'none'}\n\n"
        "Numbered lines (use these ids only):\n"
        f"{doc.line_map_text()}"
    )
    return chat_json(system=STAGE1_SYSTEM, user=user, temperature=0.1)


def run_stage2(
    doc: PreprocessedDoc,
    stage1: Dict[str, Any],
    *,
    reference_date_iso: str,
    source_hint: str | None,
) -> Dict[str, Any]:
    user = (
        f"Reference date: {reference_date_iso}\n"
        f"Source hint: {source_hint or 'none'}\n\n"
        "Full line map:\n"
        f"{doc.line_map_text()}\n\n"
        "Stage1 eventSegments JSON:\n"
        f"{_safe_json(stage1)}"
    )
    return chat_json(system=STAGE2_SYSTEM, user=user, temperature=0.1)


def _safe_json(obj: Any) -> str:
    import json

    try:
        return json.dumps(obj, ensure_ascii=False, indent=2)
    except Exception:
        return str(obj)
