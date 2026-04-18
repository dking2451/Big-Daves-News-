"""Backward-compatible re-export; canonical implementation lives in `extraction.normalize`."""

from .extraction.normalize import normalize_candidates

__all__ = ["normalize_candidates"]
