"""
Mocked TMDB/TVMaze HTTP tests: verify wrong merged ids are rejected and search can recover correct art.

Run: PYTHONPATH=. python3 -m unittest tests.test_watch_poster_resolution_integration -v
"""

from __future__ import annotations

import unittest
from unittest.mock import patch

from app.models import WatchShow
from app.watch_poster_resolution import (
    resolve_watch_poster,
    try_resolve_from_fresh_catalog_cache,
)
from datetime import datetime, timezone


def _fresh_ts() -> str:
    return datetime.now(timezone.utc).isoformat()


class MockTMDBResponses:
    """Route fake JSON by URL substring (minimal shapes for resolver)."""

    HOTD_ID = 94997
    SILO_ID = 114478

    @staticmethod
    def tv_hotd() -> dict:
        return {
            "name": "House of the Dragon",
            "first_air_date": "2022-08-21",
            "poster_path": "/house_of_dragon.jpg",
            "backdrop_path": "/hod_backdrop.jpg",
        }

    @staticmethod
    def tv_silo() -> dict:
        return {
            "name": "Silo",
            "first_air_date": "2023-05-05",
            "poster_path": "/silo.jpg",
            "backdrop_path": "/silo_back.jpg",
        }

    @staticmethod
    def search_silo_results() -> dict:
        return {
            "results": [
                {
                    "id": MockTMDBResponses.SILO_ID,
                    "name": "Silo",
                    "original_name": "Silo",
                    "first_air_date": "2023-05-05",
                    "genre_ids": [18],
                    "original_language": "en",
                    "origin_country": ["US"],
                }
            ]
        }

    @staticmethod
    def tvmaze_aligned() -> list:
        return [{"show": {"name": "Silo", "premiered": "2023-05-05"}}]


def _http_router(url: str, *args, **kwargs) -> object:
    u = str(url)
    if "api.themoviedb.org/3/tv/" in u and f"/tv/{MockTMDBResponses.HOTD_ID}" in u.replace("?api_key", ""):
        # /3/tv/94997?...
        if u.split("api.themoviedb.org/3/tv/")[1].split("?")[0].startswith(str(MockTMDBResponses.HOTD_ID)):
            return MockTMDBResponses.tv_hotd()
    if "api.themoviedb.org/3/tv/" in u:
        rest = u.split("api.themoviedb.org/3/tv/")[1].split("?")[0]
        if rest == str(MockTMDBResponses.SILO_ID):
            return MockTMDBResponses.tv_silo()
    if "api.themoviedb.org/3/search/tv" in u:
        return MockTMDBResponses.search_silo_results()
    if "api.tvmaze.com" in u:
        return MockTMDBResponses.tvmaze_aligned()
    raise AssertionError(f"Unexpected URL in mock: {u[:120]}")


class WrongMergedIdRecoveryTests(unittest.TestCase):
    """Silo + wrong TMDB id (HoD) must not return House of the Dragon poster."""

    @patch("app.watch_poster_resolution._http_get_json", side_effect=_http_router)
    def test_rejects_hod_id_then_resolves_silo_via_search(self, _mock: object) -> None:
        show = WatchShow(
            show_id="tvmaze-999999",
            title="Silo",
            poster_url="",
            synopsis="",
            release_date="2023-05-05",
            tmdb_tv_id=MockTMDBResponses.HOTD_ID,
        )
        outcome = resolve_watch_poster(
            show,
            api_key="fake-key",
            timeout_seconds=2.0,
            skip_catalog_fast_path=True,
        )
        self.assertTrue(outcome.trusted)
        self.assertEqual(outcome.tmdb_tv_id, MockTMDBResponses.SILO_ID)
        self.assertIn("silo.jpg", outcome.poster_url)
        self.assertEqual(outcome.candidate_name, "Silo")
        self.assertIn("tmdb_id_title_mismatch", " ".join(outcome.debug_notes))


class CatalogCacheCoherenceTests(unittest.TestCase):
    @patch("app.watch_poster_resolution._http_get_json", side_effect=_http_router)
    def test_fresh_cache_skipped_when_canon_disagrees_with_ingest(self, _mock: object) -> None:
        show = WatchShow(
            show_id="tvmaze-1",
            title="Silo",
            poster_url="https://image.tmdb.org/t/p/w500/wrong.jpg",
            synopsis="",
            tmdb_tv_id=MockTMDBResponses.HOTD_ID,
            tmdb_canonical_title="House of the Dragon",
            tmdb_last_refreshed_at=_fresh_ts(),
            poster_confidence=100,
        )
        cached = try_resolve_from_fresh_catalog_cache(show)
        self.assertIsNone(cached)


class HijackSearchPathTests(unittest.TestCase):
    """Non-ambiguous title can pass with search + detail when id path absent."""

    @staticmethod
    def _http_hijack(url: str, *args, **kwargs) -> object:
        u = str(url)
        if "search/tv" in u:
            return {
                "results": [
                    {
                        "id": 201834,
                        "name": "Hijack",
                        "original_name": "Hijack",
                        "first_air_date": "2023-06-28",
                        "genre_ids": [18],
                        "original_language": "en",
                        "origin_country": ["GB"],
                    }
                ]
            }
        if "api.themoviedb.org/3/tv/201834" in u:
            return {
                "name": "Hijack",
                "first_air_date": "2023-06-28",
                "poster_path": "/hijack.jpg",
                "backdrop_path": "/b.jpg",
            }
        if "api.tvmaze.com" in u:
            return [{"show": {"name": "Hijack", "premiered": "2023-06-28"}}]
        raise AssertionError(f"Unexpected URL: {u[:100]}")

    @patch("app.watch_poster_resolution._http_get_json", side_effect=_http_hijack)
    def test_hijack_resolves_trusted(self, _mock: object) -> None:
        show = WatchShow(
            show_id="tvmaze-2",
            title="Hijack",
            poster_url="",
            synopsis="",
            release_date="2023-06-28",
        )
        outcome = resolve_watch_poster(
            show,
            api_key="k",
            timeout_seconds=2.0,
            skip_catalog_fast_path=True,
        )
        self.assertTrue(outcome.trusted)
        self.assertEqual(outcome.resolution_path, "tmdb_search")
        self.assertIn("hijack.jpg", outcome.poster_url)


if __name__ == "__main__":
    unittest.main()
