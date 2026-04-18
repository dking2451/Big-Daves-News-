"""Stage C: event boundaries — implemented by `llm.stages.run_stage1` (document + segments)."""

from .llm.stages import run_stage1 as segment_document

__all__ = ["segment_document"]
