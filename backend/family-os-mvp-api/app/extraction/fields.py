"""Stage D: field extraction — implemented by `llm.stages.run_stage2` (per-document batch)."""

from .llm.stages import run_stage2 as extract_fields_for_segments

__all__ = ["extract_fields_for_segments"]
