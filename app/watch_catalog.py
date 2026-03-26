"""
Persistent TMDB TV id + canonical poster cache for Watch catalogue rows.

In-memory ingest lists are short-lived; SQLite lets us reuse stable tmdb_tv_id
across cache refreshes so poster resolution can skip risky title search.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from app.db import execute_query, get_connection
from app.models import WatchShow
from app.watch_feedback import normalize_show_id
from app.watch_poster_resolution import PosterResolveOutcome, tmdb_tv_id_for_show

logger = logging.getLogger(__name__)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def merge_catalog_into_show(show: WatchShow) -> None:
    """
    Load stored tmdb_tv_id (and optional trusted poster URL) before poster resolution.
    Never overwrites an existing id on the show object.
    """
    sid = normalize_show_id(show.show_id or "")
    if not sid:
        return
    try:
        with get_connection() as conn:
            row = execute_query(
                conn,
                """
                SELECT tmdb_tv_id, poster_url, poster_confidence, poster_resolution_path, poster_status
                FROM watch_catalog
                WHERE show_id = ?
                LIMIT 1
                """,
                (sid,),
            ).fetchone()
    except Exception as exc:
        logger.debug("watch_catalog merge skipped show_id=%s err=%s", sid, exc)
        return
    if not row:
        return
    raw_id = row["tmdb_tv_id"] if hasattr(row, "keys") else row[0]
    purl = row["poster_url"] if hasattr(row, "keys") else row[1]
    try:
        tid = int(raw_id) if raw_id is not None else None
    except (TypeError, ValueError):
        tid = None
    if tid is not None and getattr(show, "tmdb_tv_id", None) in (None, 0):
        show.tmdb_tv_id = tid
        logger.info(
            "watch_catalog merged tmdb_tv_id into show show_id=%s tmdb_tv_id=%s title=%s",
            sid,
            tid,
            (show.title or "")[:80],
        )
    url = str(purl or "").strip()
    if url.startswith("https://image.tmdb.org/") and not str(show.poster_url or "").strip():
        show.poster_url = url


def persist_watch_catalog_row(show: WatchShow, outcome: PosterResolveOutcome | None = None) -> None:
    """
    Upsert stable TMDB id and trusted poster fields after a successful resolution.
    Persists tmdb_tv_id whenever present and resolution was not a pure rejection without id.
    """
    sid = normalize_show_id(show.show_id or "")
    if not sid:
        return
    tid = getattr(show, "tmdb_tv_id", None)
    if tid is None:
        tid = tmdb_tv_id_for_show(show)
    if tid is None:
        return
    try:
        tid = int(tid)
    except (TypeError, ValueError):
        return

    title = (show.title or "")[:200]
    purl = str(getattr(show, "poster_url", "") or "")[:800]
    conf = getattr(show, "poster_confidence", None)
    if conf is None and outcome is not None:
        conf = outcome.confidence
    path = str(getattr(show, "poster_resolution_path", "") or "")
    if not path and outcome is not None:
        path = outcome.resolution_path
    status = str(getattr(show, "poster_status", "") or "")
    if not status and outcome is not None:
        from app.watch_poster_resolution import poster_status_for_outcome

        status = poster_status_for_outcome(outcome)

    now = _now_iso()
    try:
        with get_connection() as conn:
            execute_query(
                conn,
                """
                INSERT INTO watch_catalog(
                    show_id, title, tmdb_tv_id, poster_url, poster_confidence,
                    poster_resolution_path, poster_status, updated_at_utc
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(show_id) DO UPDATE SET
                    title = excluded.title,
                    tmdb_tv_id = excluded.tmdb_tv_id,
                    poster_url = CASE
                        WHEN excluded.poster_url != '' THEN excluded.poster_url
                        ELSE watch_catalog.poster_url
                    END,
                    poster_confidence = COALESCE(excluded.poster_confidence, watch_catalog.poster_confidence),
                    poster_resolution_path = CASE
                        WHEN excluded.poster_resolution_path != '' THEN excluded.poster_resolution_path
                        ELSE watch_catalog.poster_resolution_path
                    END,
                    poster_status = CASE
                        WHEN excluded.poster_status != '' THEN excluded.poster_status
                        ELSE watch_catalog.poster_status
                    END,
                    updated_at_utc = excluded.updated_at_utc
                """,
                (
                    sid,
                    title,
                    tid,
                    purl,
                    conf,
                    path,
                    status,
                    now,
                ),
            )
            conn.commit()
        logger.info(
            "watch_catalog persisted show_id=%s tmdb_tv_id=%s path=%s trusted=%s",
            sid,
            tid,
            path,
            bool(getattr(show, "poster_trusted", False)),
        )
    except Exception as exc:
        logger.warning("watch_catalog persist failed show_id=%s: %s", sid, exc)


def distinct_show_ids_from_user_tables() -> list[str]:
    """Show ids referenced by seen / reactions / watchlist (for backfill scope)."""
    out: list[str] = []
    try:
        with get_connection() as conn:
            rows = execute_query(
                conn,
                """
                SELECT show_id FROM watch_seen
                UNION
                SELECT show_id FROM watch_reactions
                UNION
                SELECT show_id FROM watch_watchlist
                """,
                (),
            ).fetchall()
    except Exception as exc:
        logger.warning("watch_catalog distinct_show_ids: %s", exc)
        return []
    seen: set[str] = set()
    for row in rows or []:
        sid = row["show_id"] if hasattr(row, "keys") else row[0]
        s = normalize_show_id(str(sid))
        if s and s not in seen:
            seen.add(s)
            out.append(s)
    return out


def backfill_missing_tmdb_tv_ids(
    *,
    dry_run: bool = False,
    timeout_seconds: float = 6.0,
) -> dict[str, object]:
    """
    Resolve TMDB ids for curated fallback catalogue rows using the same resolver as production.
    Uses FALLBACK_WATCH_SHOWS (static list). Run after deploy to warm SQLite watch_catalog.
    """
    import os

    from app.watch import FALLBACK_WATCH_SHOWS
    from app.watch_poster_resolution import apply_resolution_to_show, resolve_watch_poster

    api_key = os.getenv("TMDB_API_KEY", "").strip()
    results: list[dict[str, object]] = []
    candidates: list[WatchShow] = list(FALLBACK_WATCH_SHOWS)

    for show in candidates:
        merge_catalog_into_show(show)
        outcome = resolve_watch_poster(show, api_key=api_key, timeout_seconds=timeout_seconds)
        if dry_run:
            results.append(
                {
                    "show_id": show.show_id,
                    "dry_run": True,
                    "would_accept": outcome.trusted,
                    "tmdb_tv_id": outcome.tmdb_tv_id,
                    "confidence": outcome.confidence,
                    "path": outcome.resolution_path,
                }
            )
            continue
        apply_resolution_to_show(show, outcome, poster_source_tag=outcome.resolution_path)
        persist_watch_catalog_row(show, outcome=outcome)
        results.append(
            {
                "show_id": show.show_id,
                "accepted": outcome.trusted,
                "tmdb_tv_id": outcome.tmdb_tv_id,
                "confidence": outcome.confidence,
                "path": outcome.resolution_path,
            }
        )
    return {"count": len(results), "results": results}
