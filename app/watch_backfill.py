"""
Full TMDB backfill for watch_catalog: resolve missing ids, refresh stale trusted metadata.

Safe to rerun: each row is independent; low-confidence matches are never persisted as trusted.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from typing import Any

from app.db import execute_query, get_connection
from app.models import WatchShow
from app.watch import FALLBACK_WATCH_SHOWS
from app.watch_catalog import (
    fetch_all_watch_catalog_rows,
    merge_catalog_into_show,
    persist_watch_catalog_row,
)
from app.watch_feedback import normalize_show_id
from app.watch_poster_resolution import apply_resolution_to_show, resolve_watch_poster

logger = logging.getLogger(__name__)


def _show_from_catalog_row(row: dict[str, Any]) -> WatchShow:
    tid = row.get("tmdb_tv_id")
    try:
        tid_int = int(tid) if tid is not None else None
    except (TypeError, ValueError):
        tid_int = None
    fa = str(row.get("tmdb_first_air_date") or "").strip()
    return WatchShow(
        show_id=str(row.get("show_id") or ""),
        title=str(row.get("title") or ""),
        poster_url=str(row.get("poster_url") or ""),
        synopsis="",
        release_date=fa[:32],
        tmdb_tv_id=tid_int,
        poster_confidence=row.get("poster_confidence"),
        poster_resolution_path=str(row.get("poster_resolution_path") or ""),
        poster_status=str(row.get("poster_status") or ""),
        tmdb_backdrop_url=str(row.get("backdrop_url") or ""),
        tmdb_canonical_title=str(row.get("tmdb_canonical_title") or ""),
        tmdb_catalog_first_air_date=fa,
        tmdb_last_refreshed_at=str(row.get("tmdb_last_refreshed_at") or ""),
    )


def _fallback_show_by_id(show_id: str) -> WatchShow | None:
    sid = normalize_show_id(show_id)
    for s in FALLBACK_WATCH_SHOWS:
        if normalize_show_id(s.show_id) == sid:
            return s
    return None


@dataclass
class BackfillStats:
    scanned: int = 0
    already_had_tmdb_id: int = 0
    newly_resolved_id: int = 0
    rejected_low_confidence: int = 0
    still_unresolved: int = 0
    poster_refreshed: int = 0
    tmdb_api_errors: int = 0
    skipped_filter: int = 0

    errors: list[str] = field(default_factory=list)


def run_full_watch_catalog_backfill(
    *,
    dry_run: bool = False,
    limit: int | None = None,
    only_show_ids: list[str] | None = None,
    only_title_contains: str | None = None,
    timeout_seconds: float = 8.0,
) -> dict[str, Any]:
    """
    Scan all watch_catalog rows; resolve missing tmdb_tv_id; refresh canonical TMDB data by id.

    Uses skip_catalog_fast_path so each row hits TMDB when needed (no runtime cache shortcut).
    """
    api_key = os.getenv("TMDB_API_KEY", "").strip()
    if not api_key:
        return {"success": False, "message": "TMDB_API_KEY is not set.", "stats": {}}

    rows = fetch_all_watch_catalog_rows()
    stats = BackfillStats()
    only_ids = {normalize_show_id(x) for x in (only_show_ids or []) if normalize_show_id(x)}
    title_filter = (only_title_contains or "").strip().lower()
    results: list[dict[str, Any]] = []

    processed = 0
    for row in rows:
        sid = str(row.get("show_id") or "")
        if only_ids and normalize_show_id(sid) not in only_ids:
            stats.skipped_filter += 1
            continue
        title = str(row.get("title") or "")
        if title_filter and title_filter not in title.lower():
            stats.skipped_filter += 1
            continue

        if limit is not None and processed >= limit:
            break
        processed += 1
        stats.scanned += 1

        old_tid = row.get("tmdb_tv_id")
        try:
            old_tid_int = int(old_tid) if old_tid is not None else None
        except (TypeError, ValueError):
            old_tid_int = None
        if old_tid_int is not None:
            stats.already_had_tmdb_id += 1

        show = _show_from_catalog_row(row)
        merge_catalog_into_show(show)
        old_poster = str(row.get("poster_url") or "").strip()

        try:
            outcome = resolve_watch_poster(
                show,
                api_key=api_key,
                timeout_seconds=timeout_seconds,
                skip_catalog_fast_path=True,
            )
        except Exception as exc:
            stats.tmdb_api_errors += 1
            stats.errors.append(f"{sid}: {exc!s}")
            logger.warning("watch_backfill tmdb_error show_id=%s err=%s", sid, exc)
            results.append(
                {
                    "show_id": sid,
                    "title": title,
                    "accepted": False,
                    "error": str(exc)[:300],
                }
            )
            continue

        new_tid = outcome.tmdb_tv_id
        if old_tid_int is None and new_tid is not None:
            stats.newly_resolved_id += 1
        if not outcome.trusted:
            if "low_confidence" in (outcome.rejection_reason or "") or outcome.resolution_path == "rejected_low_confidence":
                stats.rejected_low_confidence += 1
            elif outcome.tmdb_tv_id is None:
                stats.still_unresolved += 1
        new_poster = str(outcome.poster_url or "").strip()
        if outcome.trusted and new_poster and new_poster != old_poster:
            stats.poster_refreshed += 1

        logger.info(
            "watch_backfill_row title=%r show_id=%s old_tmdb=%s new_tmdb=%s candidate_title=%r "
            "candidate_year=%s confidence=%s accepted=%s path=%s reject=%s",
            (title or "")[:120],
            sid,
            old_tid_int,
            new_tid,
            (outcome.candidate_name or "")[:120],
            (outcome.candidate_first_air or "")[:4],
            outcome.confidence,
            outcome.trusted,
            outcome.resolution_path,
            (outcome.rejection_reason or "")[:200],
        )

        results.append(
            {
                "show_id": sid,
                "title": title,
                "old_tmdb_tv_id": old_tid_int,
                "new_tmdb_tv_id": new_tid,
                "candidate_title": outcome.candidate_name,
                "candidate_first_air": outcome.candidate_first_air,
                "confidence": outcome.confidence,
                "accepted": outcome.trusted,
                "resolution_path": outcome.resolution_path,
                "rejection_reason": outcome.rejection_reason,
            }
        )

        if dry_run:
            continue

        apply_resolution_to_show(show, outcome, poster_source_tag=outcome.resolution_path)
        persist_watch_catalog_row(show, outcome=outcome)

    summary = {
        "scanned": stats.scanned,
        "already_had_tmdb_tv_id": stats.already_had_tmdb_id,
        "newly_resolved_tmdb_id": stats.newly_resolved_id,
        "rejected_low_confidence": stats.rejected_low_confidence,
        "still_unresolved": stats.still_unresolved,
        "poster_urls_refreshed": stats.poster_refreshed,
        "tmdb_api_errors": stats.tmdb_api_errors,
        "skipped_by_filter": stats.skipped_filter,
    }
    logger.info("watch_backfill_summary %s", summary)
    return {
        "success": True,
        "dry_run": dry_run,
        "stats": summary,
        "results": results,
        "errors": stats.errors[:50],
    }


def inspect_show_resolution(
    show_id: str,
    *,
    timeout_seconds: float = 8.0,
    skip_catalog_fast_path: bool = False,
) -> dict[str, Any]:
    """Resolve one show_id for spot-checks (reads watch_catalog row if present)."""
    api_key = os.getenv("TMDB_API_KEY", "").strip()
    if not api_key:
        return {"success": False, "message": "TMDB_API_KEY is not set."}
    sid = normalize_show_id(show_id)
    catalog_row: dict[str, Any] | None = None
    try:
        with get_connection() as conn:
            r = execute_query(
                conn,
                """
                SELECT show_id, title, tmdb_tv_id, poster_url, poster_confidence,
                       poster_resolution_path, poster_status, updated_at_utc,
                       backdrop_url, tmdb_first_air_date, tmdb_canonical_title,
                       tmdb_last_refreshed_at, tmdb_match_confidence
                FROM watch_catalog WHERE show_id = ? LIMIT 1
                """,
                (sid,),
            ).fetchone()
        if r:
            if hasattr(r, "keys"):
                catalog_row = {k: r[k] for k in r.keys()}
    except Exception as exc:
        return {"success": False, "message": str(exc)}

    if catalog_row:
        show = _show_from_catalog_row(catalog_row)
    else:
        fb = _fallback_show_by_id(sid)
        if fb is None:
            return {"success": False, "message": f"No watch_catalog row or fallback for show_id={sid!r}."}
        show = fb

    merge_catalog_into_show(show)
    outcome = resolve_watch_poster(
        show,
        api_key=api_key,
        timeout_seconds=timeout_seconds,
        skip_catalog_fast_path=skip_catalog_fast_path,
    )
    return {
        "success": True,
        "show_id": show.show_id,
        "title": show.title,
        "outcome": {
            "trusted": outcome.trusted,
            "tmdb_tv_id": outcome.tmdb_tv_id,
            "confidence": outcome.confidence,
            "resolution_path": outcome.resolution_path,
            "poster_url": outcome.poster_url,
            "backdrop_url": outcome.backdrop_url,
            "candidate_name": outcome.candidate_name,
            "candidate_first_air": outcome.candidate_first_air,
            "rejection_reason": outcome.rejection_reason,
            "debug_notes": outcome.debug_notes,
        },
        "catalog_row": catalog_row,
    }
