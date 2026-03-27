"""
Persistent TMDB TV id + canonical poster cache for Watch catalogue rows.

In-memory ingest lists are short-lived; SQLite lets us reuse stable tmdb_tv_id
across cache refreshes so poster resolution can skip risky title search.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from app.db import execute_query, get_connection
from app.models import WatchShow
from app.watch_feedback import normalize_show_id
from app.watch_poster_resolution import (
    PosterResolveOutcome,
    ingest_titles_coherent_for_poster_mapping,
    tmdb_tv_id_for_show,
)

logger = logging.getLogger(__name__)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def merge_catalog_into_show(show: WatchShow) -> None:
    """
    Load stored tmdb_tv_id and TMDB cache columns before poster resolution.
    Prefers catalog TMDB poster URL when present (stable cache).
    Never overwrites curated synopsis / product release copy.
    """
    sid = normalize_show_id(show.show_id or "")
    if not sid:
        return
    try:
        with get_connection() as conn:
            row = execute_query(
                conn,
                """
                SELECT title, tmdb_tv_id, poster_url, poster_confidence, poster_resolution_path, poster_status,
                       backdrop_url, tmdb_first_air_date, tmdb_canonical_title, tmdb_last_refreshed_at,
                       tmdb_match_confidence
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

    def _col(name: str, idx: int, default: Any = None) -> Any:
        if hasattr(row, "keys"):
            try:
                return row[name]
            except (KeyError, IndexError, TypeError):
                return default
        return row[idx] if len(row) > idx else default

    stored_cat_title = str(_col("title", 0) or "").strip()
    ingest_title = (show.title or "").strip()
    if (
        stored_cat_title
        and ingest_title
        and not ingest_titles_coherent_for_poster_mapping(ingest_title, stored_cat_title)
    ):
        logger.warning(
            "watch_catalog merge skipped (ingest vs stored catalog title mismatch) show_id=%s stored=%r ingest=%r",
            sid,
            stored_cat_title[:80],
            ingest_title[:80],
        )
        return

    raw_id = _col("tmdb_tv_id", 1)
    purl = str(_col("poster_url", 2) or "").strip()
    backdrop = str(_col("backdrop_url", 6) or "").strip()
    tmdb_fa = str(_col("tmdb_first_air_date", 7) or "").strip()
    canon_title = str(_col("tmdb_canonical_title", 8) or "").strip()
    last_ref = str(_col("tmdb_last_refreshed_at", 9) or "").strip()
    match_conf = _col("tmdb_match_confidence", 10)

    try:
        tid = int(raw_id) if raw_id is not None else None
    except (TypeError, ValueError):
        tid = None
    show_tid = getattr(show, "tmdb_tv_id", None)
    try:
        show_tid_int = int(show_tid) if show_tid is not None else None
    except (TypeError, ValueError):
        show_tid_int = None
    # Catalog is authoritative for stable TMDB id when a row exists.
    if tid is not None and (show_tid_int in (None, 0) or show_tid_int != tid):
        show.tmdb_tv_id = tid
        show_tid_int = tid
        logger.info(
            "watch_catalog merged tmdb_tv_id into show show_id=%s tmdb_tv_id=%s title=%s",
            sid,
            tid,
            (show.title or "")[:80],
        )

    # Never apply a cached TMDB poster from a different tmdb_tv_id than the show (prevents bad-row bleed).
    if purl.startswith("https://image.tmdb.org/") and tid is not None and show_tid_int is not None and tid != show_tid_int:
        logger.debug(
            "watch_catalog skip poster merge (id mismatch) show_id=%s catalog_tmdb=%s show_tmdb=%s",
            sid,
            tid,
            show_tid_int,
        )
    elif purl.startswith("https://image.tmdb.org/"):
        show.poster_url = purl
    elif not str(show.poster_url or "").strip():
        show.poster_url = purl

    if backdrop:
        show.tmdb_backdrop_url = backdrop
    if canon_title:
        show.tmdb_canonical_title = canon_title
    if tmdb_fa:
        show.tmdb_catalog_first_air_date = tmdb_fa
    if last_ref:
        show.tmdb_last_refreshed_at = last_ref

    pc = _col("poster_confidence", 3)
    if pc is not None:
        try:
            show.poster_confidence = int(pc)
        except (TypeError, ValueError):
            pass
    elif match_conf is not None:
        try:
            show.poster_confidence = int(match_conf)
        except (TypeError, ValueError):
            pass

    prp = str(_col("poster_resolution_path", 4) or "").strip()
    if prp:
        show.poster_resolution_path = prp
    pst = str(_col("poster_status", 5) or "").strip()
    if pst:
        show.poster_status = pst


def persist_watch_catalog_row(show: WatchShow, outcome: PosterResolveOutcome | None = None) -> None:
    """
    Upsert stable TMDB id and trusted poster fields after a successful resolution.
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

    backdrop = str(getattr(show, "tmdb_backdrop_url", "") or "")[:800]
    canon_title = str(getattr(show, "tmdb_canonical_title", "") or "")[:200]
    tmdb_fa = str(getattr(show, "tmdb_catalog_first_air_date", "") or "")[:32]

    now = _now_iso()
    last_ref = str(getattr(show, "tmdb_last_refreshed_at", "") or "").strip()
    if outcome is not None and outcome.resolution_path == "tmdb_cached":
        try:
            with get_connection() as conn:
                prev = execute_query(
                    conn,
                    "SELECT tmdb_last_refreshed_at FROM watch_catalog WHERE show_id = ? LIMIT 1",
                    (sid,),
                ).fetchone()
                if prev:
                    pr = prev["tmdb_last_refreshed_at"] if hasattr(prev, "keys") else prev[0]
                    if pr:
                        last_ref = str(pr).strip()
        except Exception:
            pass
    elif outcome is not None and outcome.trusted and outcome.resolution_path not in ("tmdb_cached",):
        last_ref = now

    match_conf = conf

    try:
        with get_connection() as conn:
            try:
                prev_row = execute_query(
                    conn, "SELECT title FROM watch_catalog WHERE show_id = ? LIMIT 1", (sid,)
                ).fetchone()
                prev_title = ""
                if prev_row:
                    prev_title = str(
                        prev_row["title"] if hasattr(prev_row, "keys") else prev_row[0] or ""
                    ).strip()
                if (
                    prev_title
                    and title.strip()
                    and not ingest_titles_coherent_for_poster_mapping(title, prev_title)
                ):
                    execute_query(
                        conn,
                        """
                        UPDATE watch_catalog SET
                            tmdb_tv_id = NULL,
                            poster_url = '',
                            poster_resolution_path = '',
                            poster_status = '',
                            poster_confidence = NULL,
                            tmdb_canonical_title = '',
                            tmdb_last_refreshed_at = '',
                            backdrop_url = '',
                            tmdb_first_air_date = '',
                            tmdb_match_confidence = NULL
                        WHERE show_id = ?
                        """,
                        (sid,),
                    )
                    logger.info(
                        "watch_catalog cleared TMDB cache after ingest title drift show_id=%s prev=%r new=%r",
                        sid,
                        prev_title[:80],
                        title[:80],
                    )
            except Exception as exc:
                logger.debug("watch_catalog title drift pre-check show_id=%s err=%s", sid, exc)

            execute_query(
                conn,
                """
                INSERT INTO watch_catalog(
                    show_id, title, tmdb_tv_id, poster_url, poster_confidence,
                    poster_resolution_path, poster_status, updated_at_utc,
                    backdrop_url, tmdb_first_air_date, tmdb_canonical_title,
                    tmdb_last_refreshed_at, tmdb_match_confidence
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    backdrop_url = CASE
                        WHEN excluded.backdrop_url != '' THEN excluded.backdrop_url
                        ELSE watch_catalog.backdrop_url
                    END,
                    tmdb_first_air_date = CASE
                        WHEN excluded.tmdb_first_air_date != '' THEN excluded.tmdb_first_air_date
                        ELSE watch_catalog.tmdb_first_air_date
                    END,
                    tmdb_canonical_title = CASE
                        WHEN excluded.tmdb_canonical_title != '' THEN excluded.tmdb_canonical_title
                        ELSE watch_catalog.tmdb_canonical_title
                    END,
                    tmdb_last_refreshed_at = CASE
                        WHEN excluded.tmdb_last_refreshed_at != '' THEN excluded.tmdb_last_refreshed_at
                        ELSE watch_catalog.tmdb_last_refreshed_at
                    END,
                    tmdb_match_confidence = COALESCE(excluded.tmdb_match_confidence, watch_catalog.tmdb_match_confidence),
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
                    backdrop,
                    tmdb_fa,
                    canon_title,
                    last_ref,
                    match_conf,
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


def fetch_all_watch_catalog_rows() -> list[dict[str, Any]]:
    """All watch_catalog rows for admin/backfill."""
    try:
        with get_connection() as conn:
            rows = execute_query(
                conn,
                """
                SELECT show_id, title, tmdb_tv_id, poster_url, poster_confidence,
                       poster_resolution_path, poster_status, updated_at_utc,
                       backdrop_url, tmdb_first_air_date, tmdb_canonical_title,
                       tmdb_last_refreshed_at, tmdb_match_confidence
                FROM watch_catalog
                ORDER BY show_id
                """,
                (),
            ).fetchall()
    except Exception as exc:
        logger.warning("fetch_all_watch_catalog_rows: %s", exc)
        return []
    out: list[dict[str, Any]] = []
    for row in rows or []:
        if hasattr(row, "keys"):
            out.append({k: row[k] for k in row.keys()})
        else:
            out.append(
                {
                    "show_id": row[0],
                    "title": row[1],
                    "tmdb_tv_id": row[2],
                    "poster_url": row[3],
                    "poster_confidence": row[4],
                    "poster_resolution_path": row[5],
                    "poster_status": row[6],
                    "updated_at_utc": row[7],
                    "backdrop_url": row[8] if len(row) > 8 else "",
                    "tmdb_first_air_date": row[9] if len(row) > 9 else "",
                    "tmdb_canonical_title": row[10] if len(row) > 10 else "",
                    "tmdb_last_refreshed_at": row[11] if len(row) > 11 else "",
                    "tmdb_match_confidence": row[12] if len(row) > 12 else None,
                }
            )
    return out


def fetch_watch_catalog_title_mismatches(*, limit: int = 200) -> list[dict[str, Any]]:
    """
    Rows where stored catalog title and TMDB canonical title disagree (likely wrong poster mapping).
    Used for admin / ops triage.
    """
    cap = max(1, min(limit, 2000))
    try:
        rows = fetch_all_watch_catalog_rows()
    except Exception:
        return []
    out: list[dict[str, Any]] = []
    for row in rows:
        title = str(row.get("title") or "").strip()
        canon = str(row.get("tmdb_canonical_title") or "").strip()
        if not title or not canon:
            continue
        if ingest_titles_coherent_for_poster_mapping(title, canon):
            continue
        out.append(
            {
                "show_id": row.get("show_id"),
                "title": title,
                "tmdb_canonical_title": canon,
                "tmdb_tv_id": row.get("tmdb_tv_id"),
                "poster_resolution_path": row.get("poster_resolution_path"),
            }
        )
        if len(out) >= cap:
            break
    return out


def repair_catalog_from_curated_fallback(*, dry_run: bool = False) -> dict[str, object]:
    """
    Overwrite watch_catalog rows that match FALLBACK_WATCH_SHOWS with curated tmdb_tv_id + poster_url.

    Use after correcting TMDB IDs in app.watch.FALLBACK_WATCH_SHOWS so SQLite matches the static list.
    """
    from app.watch import FALLBACK_WATCH_SHOWS

    now = _now_iso()
    out: list[dict[str, object]] = []
    for show in FALLBACK_WATCH_SHOWS:
        sid = normalize_show_id(show.show_id or "")
        tid = getattr(show, "tmdb_tv_id", None)
        if not sid or tid is None:
            continue
        try:
            tid_int = int(tid)
        except (TypeError, ValueError):
            continue
        purl = str(getattr(show, "poster_url", "") or "")[:800]
        title = (show.title or "")[:200]
        if dry_run:
            out.append({"show_id": sid, "would_set_tmdb_tv_id": tid_int, "would_set_poster": purl[:60]})
            continue
        try:
            with get_connection() as conn:
                execute_query(
                    conn,
                    """
                    INSERT INTO watch_catalog(
                        show_id, title, tmdb_tv_id, poster_url, poster_confidence,
                        poster_resolution_path, poster_status, updated_at_utc,
                        backdrop_url, tmdb_first_air_date, tmdb_canonical_title,
                        tmdb_last_refreshed_at, tmdb_match_confidence
                    )
                    VALUES (?, ?, ?, ?, NULL, '', '', ?, '', '', '', '', NULL)
                    ON CONFLICT(show_id) DO UPDATE SET
                        title = excluded.title,
                        tmdb_tv_id = excluded.tmdb_tv_id,
                        poster_url = excluded.poster_url,
                        updated_at_utc = excluded.updated_at_utc
                    """,
                    (sid, title, tid_int, purl, now),
                )
                conn.commit()
            out.append({"show_id": sid, "tmdb_tv_id": tid_int, "ok": True})
        except Exception as exc:
            out.append({"show_id": sid, "ok": False, "error": str(exc)[:200]})
    return {"count": len(out), "results": out, "dry_run": dry_run}


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
