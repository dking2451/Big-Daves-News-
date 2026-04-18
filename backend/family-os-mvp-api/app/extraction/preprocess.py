"""Stage A: OCR cleanup, line preservation, stable line ids."""

from __future__ import annotations

import re
from typing import List

from .types import Line, PreprocessedDoc


def _clean_line(text: str) -> str:
    s = text.replace("\r\n", "\n").replace("\r", "\n")
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\u00a0", " ", s)
    return s.strip()


def preprocess_ocr(ocr_text: str) -> PreprocessedDoc:
    """
    Split into non-empty lines, assign L0..Ln ids, mild noise cleanup.
    Preserves order; does not merge blocks (segmentation LLM handles structure).
    """
    raw = ocr_text.strip()
    parts = raw.split("\n")
    lines: List[Line] = []
    idx = 0
    for part in parts:
        cleaned = _clean_line(part)
        if not cleaned:
            continue
        lines.append(Line(id=f"L{idx}", text=cleaned))
        idx += 1
    if not lines and raw:
        lines.append(Line(id="L0", text=_clean_line(raw)))
    return PreprocessedDoc(lines=lines, raw=raw)
