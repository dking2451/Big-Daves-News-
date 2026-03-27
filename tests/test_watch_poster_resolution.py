"""Unit tests for Watch poster title coherence and triage helpers (no TMDB HTTP)."""

from __future__ import annotations

import unittest

from app.models import WatchShow
from app.watch_poster_resolution import (
    PosterResolveOutcome,
    classify_watch_poster_failure_mode,
    effective_accept_min_strict,
    ingest_titles_coherent_for_poster_mapping,
    is_ambiguous_short_title,
)


class IngestTitleCoherenceTests(unittest.TestCase):
    def test_unrelated_titles_reject(self) -> None:
        self.assertFalse(
            ingest_titles_coherent_for_poster_mapping("Silo", "House of the Dragon")
        )

    def test_exact_match(self) -> None:
        self.assertTrue(ingest_titles_coherent_for_poster_mapping("Severance", "Severance"))

    def test_substring_still_related(self) -> None:
        self.assertTrue(
            ingest_titles_coherent_for_poster_mapping("Hijack", "Hijack (2023)")
        )


class AmbiguousShortTitleTests(unittest.TestCase):
    def test_silo_is_short(self) -> None:
        show = WatchShow(
            show_id="tvmaze-1",
            title="Silo",
            poster_url="",
            synopsis="",
        )
        self.assertTrue(is_ambiguous_short_title(show))
        self.assertEqual(effective_accept_min_strict(show), 90)

    def test_longer_title_not_short(self) -> None:
        show = WatchShow(
            show_id="tvmaze-2",
            title="The Last of Us",
            poster_url="",
            synopsis="",
        )
        self.assertFalse(is_ambiguous_short_title(show))
        self.assertEqual(effective_accept_min_strict(show), 85)


class ClassifyFailureModeTests(unittest.TestCase):
    def test_no_api_key(self) -> None:
        out = PosterResolveOutcome(
            poster_url="",
            tmdb_tv_id=None,
            confidence=0,
            resolution_path="placeholder",
            trusted=False,
            rejection_reason="no_api_key",
        )
        self.assertEqual(
            classify_watch_poster_failure_mode(
                api_key_present=False, catalog_row=None, outcome=out
            ),
            "no_api_key",
        )

    def test_ok_trusted(self) -> None:
        out = PosterResolveOutcome(
            poster_url="https://image.tmdb.org/t/p/w500/x.jpg",
            tmdb_tv_id=1,
            confidence=100,
            resolution_path="tmdb_tv_id",
            trusted=True,
            candidate_name="Silo",
        )
        self.assertEqual(
            classify_watch_poster_failure_mode(
                api_key_present=True,
                catalog_row={"title": "Silo", "tmdb_canonical_title": "Silo"},
                outcome=out,
            ),
            "ok_trusted",
        )

    def test_db_canon_stale_but_resolve_matches_ingest(self) -> None:
        out = PosterResolveOutcome(
            poster_url="https://image.tmdb.org/t/p/w500/x.jpg",
            tmdb_tv_id=1,
            confidence=100,
            resolution_path="tmdb_tv_id",
            trusted=True,
            candidate_name="Silo",
            tmdb_canonical_title="Silo",
        )
        mode = classify_watch_poster_failure_mode(
            api_key_present=True,
            catalog_row={"title": "Silo", "tmdb_canonical_title": "House of the Dragon"},
            outcome=out,
        )
        self.assertEqual(mode, "ok_trusted_db_canon_stale")

    def test_trusted_but_resolved_name_conflicts_ingest(self) -> None:
        out = PosterResolveOutcome(
            poster_url="https://image.tmdb.org/t/p/w500/x.jpg",
            tmdb_tv_id=1,
            confidence=100,
            resolution_path="tmdb_tv_id",
            trusted=True,
            candidate_name="House of the Dragon",
            tmdb_canonical_title="House of the Dragon",
        )
        mode = classify_watch_poster_failure_mode(
            api_key_present=True,
            catalog_row={"title": "Silo", "tmdb_canonical_title": "House of the Dragon"},
            outcome=out,
        )
        self.assertEqual(mode, "trusted_ingest_vs_resolved_name_mismatch")


if __name__ == "__main__":
    unittest.main()
