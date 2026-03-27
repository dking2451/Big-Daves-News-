from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from app.db import execute_query, get_connection


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalize_device_id(raw: str) -> str:
    cleaned = "".join(ch for ch in (raw or "").strip() if ch.isalnum() or ch in ("-", "_"))
    return cleaned[:64]


def normalize_show_id(raw: str) -> str:
    cleaned = "".join(ch for ch in (raw or "").strip() if ch.isalnum() or ch in ("-", "_"))
    return cleaned[:120]


def set_watch_progress(device_id: str, show_id: str, state: str) -> tuple[bool, str]:
    """Persist watch progression: not_started (no row), watching, or finished."""
    normalized_device = normalize_device_id(device_id)
    normalized_show = normalize_show_id(show_id)
    st = (state or "").strip().lower()
    if not normalized_device or not normalized_show:
        return False, "Invalid device_id or show_id."
    if st not in {"not_started", "watching", "finished"}:
        return False, "watch_state must be not_started, watching, or finished."
    with get_connection() as conn:
        if st == "not_started":
            execute_query(
                conn,
                "DELETE FROM watch_seen WHERE device_id = ? AND show_id = ?",
                (normalized_device, normalized_show),
            )
        else:
            now = _now_iso()
            existing = execute_query(
                conn,
                "SELECT device_id FROM watch_seen WHERE device_id = ? AND show_id = ? LIMIT 1",
                (normalized_device, normalized_show),
            ).fetchone()
            if existing:
                execute_query(
                    conn,
                    """
                    UPDATE watch_seen
                    SET progress_state = ?, updated_at_utc = ?
                    WHERE device_id = ? AND show_id = ?
                    """,
                    (st, now, normalized_device, normalized_show),
                )
            else:
                execute_query(
                    conn,
                    """
                    INSERT INTO watch_seen(
                        device_id, show_id, created_at_utc, updated_at_utc, progress_state
                    )
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (normalized_device, normalized_show, now, now, st),
                )
        conn.commit()
    return True, "Updated watch progress."


def set_watch_seen(device_id: str, show_id: str, seen: bool) -> tuple[bool, str]:
    """Backward compatible: seen True -> finished, False -> not_started."""
    return set_watch_progress(device_id, show_id, "finished" if seen else "not_started")


def get_watch_progress_map(device_id: str) -> dict[str, str]:
    """show_id -> watching | finished. Omitted keys mean not_started."""
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return {}
    with get_connection() as conn:
        try:
            rows = execute_query(
                conn,
                """
                SELECT show_id, progress_state
                FROM watch_seen
                WHERE device_id = ?
                """,
                (normalized_device,),
            ).fetchall()
        except Exception:
            rows = execute_query(
                conn,
                "SELECT show_id FROM watch_seen WHERE device_id = ?",
                (normalized_device,),
            ).fetchall()
            result_legacy: dict[str, str] = {}
            for row in rows or []:
                sid = str(row["show_id"]) if hasattr(row, "keys") else str(row[0])
                result_legacy[sid] = "finished"
            return result_legacy
    result: dict[str, str] = {}
    for row in rows or []:
        sid = str(row["show_id"]) if hasattr(row, "keys") else str(row[0])
        raw = str(row["progress_state"]) if hasattr(row, "keys") else "finished"
        st = raw.strip().lower()
        if st not in {"watching", "finished"}:
            st = "finished"
        result[sid] = st
    return result


def set_watch_reaction(device_id: str, show_id: str, reaction: str) -> tuple[bool, str]:
    normalized_device = normalize_device_id(device_id)
    normalized_show = normalize_show_id(show_id)
    normalized_reaction = (reaction or "").strip().lower()
    if not normalized_device or not normalized_show:
        return False, "Invalid device_id or show_id."
    if normalized_reaction not in {"up", "down", "none"}:
        return False, "Reaction must be up, down, or none."

    with get_connection() as conn:
        if normalized_reaction == "none":
            execute_query(
                conn,
                "DELETE FROM watch_reactions WHERE device_id = ? AND show_id = ?",
                (normalized_device, normalized_show),
            )
        else:
            now = _now_iso()
            existing = execute_query(
                conn,
                "SELECT device_id FROM watch_reactions WHERE device_id = ? AND show_id = ? LIMIT 1",
                (normalized_device, normalized_show),
            ).fetchone()
            if existing:
                execute_query(
                    conn,
                    """
                    UPDATE watch_reactions
                    SET reaction = ?, updated_at_utc = ?
                    WHERE device_id = ? AND show_id = ?
                    """,
                    (normalized_reaction, now, normalized_device, normalized_show),
                )
            else:
                execute_query(
                    conn,
                    """
                    INSERT INTO watch_reactions(device_id, show_id, reaction, created_at_utc, updated_at_utc)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (normalized_device, normalized_show, normalized_reaction, now, now),
                )
        conn.commit()
    return True, "Updated reaction."


def set_watch_saved(device_id: str, show_id: str, saved: bool) -> tuple[bool, str]:
    normalized_device = normalize_device_id(device_id)
    normalized_show = normalize_show_id(show_id)
    if not normalized_device or not normalized_show:
        return False, "Invalid device_id or show_id."
    with get_connection() as conn:
        if saved:
            now = _now_iso()
            existing = execute_query(
                conn,
                "SELECT device_id FROM watch_watchlist WHERE device_id = ? AND show_id = ? LIMIT 1",
                (normalized_device, normalized_show),
            ).fetchone()
            if existing:
                execute_query(
                    conn,
                    "UPDATE watch_watchlist SET updated_at_utc = ? WHERE device_id = ? AND show_id = ?",
                    (now, normalized_device, normalized_show),
                )
            else:
                execute_query(
                    conn,
                    """
                    INSERT INTO watch_watchlist(device_id, show_id, created_at_utc, updated_at_utc)
                    VALUES (?, ?, ?, ?)
                    """,
                    (normalized_device, normalized_show, now, now),
                )
        else:
            execute_query(
                conn,
                "DELETE FROM watch_watchlist WHERE device_id = ? AND show_id = ?",
                (normalized_device, normalized_show),
            )
        conn.commit()
    return True, "Updated watchlist."


def get_watch_seen_set(device_id: str) -> set[str]:
    """Finished shows only (API `seen` / hide_finished semantics)."""
    return {sid for sid, st in get_watch_progress_map(device_id).items() if st == "finished"}


def get_watch_user_reactions(device_id: str) -> dict[str, str]:
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return {}
    with get_connection() as conn:
        rows = execute_query(
            conn,
            "SELECT show_id, reaction FROM watch_reactions WHERE device_id = ?",
            (normalized_device,),
        ).fetchall()
    result: dict[str, str] = {}
    for row in rows:
        show_id = str(row["show_id"]) if hasattr(row, "keys") else str(row[0])
        reaction = str(row["reaction"]) if hasattr(row, "keys") else str(row[1])
        if reaction in {"up", "down"}:
            result[show_id] = reaction
    return result


def get_watch_saved_set(device_id: str) -> set[str]:
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return set()
    with get_connection() as conn:
        rows = execute_query(
            conn,
            "SELECT show_id FROM watch_watchlist WHERE device_id = ?",
            (normalized_device,),
        ).fetchall()
    return {str(row["show_id"]) if hasattr(row, "keys") else str(row[0]) for row in rows}


def get_watch_saved_meta(device_id: str) -> dict[str, str]:
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return {}
    with get_connection() as conn:
        rows = execute_query(
            conn,
            """
            SELECT show_id, updated_at_utc
            FROM watch_watchlist
            WHERE device_id = ?
            """,
            (normalized_device,),
        ).fetchall()
    result: dict[str, str] = {}
    for row in rows:
        show_id = str(row["show_id"]) if hasattr(row, "keys") else str(row[0])
        saved_at = str(row["updated_at_utc"]) if hasattr(row, "keys") else str(row[1])
        result[show_id] = saved_at
    return result


def set_watch_caught_up(device_id: str, show_id: str, release_date: str = "") -> tuple[bool, str]:
    normalized_device = normalize_device_id(device_id)
    normalized_show = normalize_show_id(show_id)
    normalized_release = (release_date or "").strip()[:32]
    if not normalized_device or not normalized_show:
        return False, "Invalid device_id or show_id."
    now = _now_iso()
    with get_connection() as conn:
        existing = execute_query(
            conn,
            "SELECT device_id FROM watch_caught_up WHERE device_id = ? AND show_id = ? LIMIT 1",
            (normalized_device, normalized_show),
        ).fetchone()
        if existing:
            execute_query(
                conn,
                """
                UPDATE watch_caught_up
                SET last_caught_up_release_date = ?, last_caught_up_at_utc = ?, updated_at_utc = ?
                WHERE device_id = ? AND show_id = ?
                """,
                (normalized_release, now, now, normalized_device, normalized_show),
            )
        else:
            execute_query(
                conn,
                """
                INSERT INTO watch_caught_up(
                    device_id, show_id, last_caught_up_release_date, last_caught_up_at_utc, updated_at_utc
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (normalized_device, normalized_show, normalized_release, now, now),
            )
        conn.commit()
    return True, "Marked as caught up."


def get_watch_caught_up_map(device_id: str) -> dict[str, str]:
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return {}
    with get_connection() as conn:
        rows = execute_query(
            conn,
            """
            SELECT show_id, last_caught_up_release_date
            FROM watch_caught_up
            WHERE device_id = ?
            """,
            (normalized_device,),
        ).fetchall()
    result: dict[str, str] = {}
    for row in rows:
        show_id = str(row["show_id"]) if hasattr(row, "keys") else str(row[0])
        release = str(row["last_caught_up_release_date"]) if hasattr(row, "keys") else str(row[1])
        result[show_id] = release
    return result


def get_watch_preferences(device_id: str) -> dict[str, bool]:
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return {"watch_episode_alerts": False, "upcoming_release_reminders": False}
    with get_connection() as conn:
        row = execute_query(
            conn,
            """
            SELECT watch_episode_alerts, upcoming_release_reminders
            FROM watch_preferences
            WHERE device_id = ?
            LIMIT 1
            """,
            (normalized_device,),
        ).fetchone()
    if not row:
        return {"watch_episode_alerts": False, "upcoming_release_reminders": False}
    episode = bool(row["watch_episode_alerts"]) if hasattr(row, "keys") else bool(row[0])
    upcoming = bool(row["upcoming_release_reminders"]) if hasattr(row, "keys") else bool(row[1])
    return {"watch_episode_alerts": episode, "upcoming_release_reminders": upcoming}


def set_watch_preferences(device_id: str, watch_episode_alerts: bool, upcoming_release_reminders: bool) -> tuple[bool, str]:
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return False, "Invalid device_id."
    now = _now_iso()
    with get_connection() as conn:
        existing = execute_query(
            conn,
            "SELECT device_id FROM watch_preferences WHERE device_id = ? LIMIT 1",
            (normalized_device,),
        ).fetchone()
        if existing:
            execute_query(
                conn,
                """
                UPDATE watch_preferences
                SET watch_episode_alerts = ?, upcoming_release_reminders = ?, updated_at_utc = ?
                WHERE device_id = ?
                """,
                (
                    1 if watch_episode_alerts else 0,
                    1 if upcoming_release_reminders else 0,
                    now,
                    normalized_device,
                ),
            )
        else:
            execute_query(
                conn,
                """
                INSERT INTO watch_preferences(
                    device_id, watch_episode_alerts, upcoming_release_reminders, updated_at_utc
                ) VALUES (?, ?, ?, ?)
                """,
                (
                    normalized_device,
                    1 if watch_episode_alerts else 0,
                    1 if upcoming_release_reminders else 0,
                    now,
                ),
            )
        conn.commit()
    return True, "Updated watch preferences."


def get_watch_vote_stats(show_ids: list[str]) -> dict[str, dict[str, int]]:
    if not show_ids:
        return {}
    normalized = [normalize_show_id(show_id) for show_id in show_ids]
    normalized = [item for item in normalized if item]
    if not normalized:
        return {}
    placeholders = ", ".join(["?"] * len(normalized))
    query = f"""
        SELECT show_id, reaction, COUNT(*) AS c
        FROM watch_reactions
        WHERE show_id IN ({placeholders})
        GROUP BY show_id, reaction
    """
    with get_connection() as conn:
        rows = execute_query(conn, query, tuple(normalized)).fetchall()
    result: dict[str, dict[str, int]] = {show_id: {"up": 0, "down": 0} for show_id in normalized}
    for row in rows:
        show_id = str(row["show_id"]) if hasattr(row, "keys") else str(row[0])
        reaction = str(row["reaction"]) if hasattr(row, "keys") else str(row[1])
        count = int(row["c"]) if hasattr(row, "keys") else int(row[2])
        if show_id not in result:
            result[show_id] = {"up": 0, "down": 0}
        if reaction == "up":
            result[show_id]["up"] = count
        elif reaction == "down":
            result[show_id]["down"] = count
    return result


@dataclass
class WatchRepetitionHints:
    """Recent surfacing history used to penalize repeating the same hero / feed titles."""

    hero_last_shown: dict[str, datetime]
    more_pick_counts_48h: dict[str, int]


def _parse_shown_at(raw: str) -> datetime | None:
    try:
        t = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if t.tzinfo is None:
            t = t.replace(tzinfo=timezone.utc)
        return t.astimezone(timezone.utc)
    except Exception:
        return None


def get_watch_repetition_hints(device_id: str, *, lookback_rows: int = 220) -> WatchRepetitionHints:
    normalized_device = normalize_device_id(device_id)
    hero_last: dict[str, datetime] = {}
    more_counts: dict[str, int] = {}
    if not normalized_device:
        return WatchRepetitionHints(hero_last_shown={}, more_pick_counts_48h={})
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(hours=48)
    with get_connection() as conn:
        try:
            rows = execute_query(
                conn,
                """
                SELECT show_id, surface, shown_at_utc
                FROM watch_surfaced
                WHERE device_id = ?
                ORDER BY shown_at_utc DESC
                LIMIT ?
                """,
                (normalized_device, max(1, min(lookback_rows, 500))),
            ).fetchall()
        except Exception:
            return WatchRepetitionHints(hero_last_shown={}, more_pick_counts_48h={})
    for row in rows or []:
        show_id = str(row["show_id"]) if hasattr(row, "keys") else str(row[0])
        surface = str(row["surface"]) if hasattr(row, "keys") else str(row[1])
        raw_time = str(row["shown_at_utc"]) if hasattr(row, "keys") else str(row[2])
        shown = _parse_shown_at(raw_time)
        if shown is None:
            continue
        if surface == "hero":
            prev = hero_last.get(show_id)
            if prev is None or shown > prev:
                hero_last[show_id] = shown
        if surface == "more_pick" and shown >= cutoff:
            more_counts[show_id] = more_counts.get(show_id, 0) + 1
    return WatchRepetitionHints(hero_last_shown=hero_last, more_pick_counts_48h=more_counts)


def record_watch_surfaces(device_id: str, entries: list[tuple[str, str]]) -> None:
    """Best-effort log for anti-repetition. entries: (show_id, surface)."""
    normalized_device = normalize_device_id(device_id)
    if not normalized_device or not entries:
        return
    now = _now_iso()
    with get_connection() as conn:
        for show_id, surface in entries:
            sid = normalize_show_id(show_id)
            surf = (surface or "").strip().lower()
            if not sid or surf not in {"hero", "more_pick"}:
                continue
            try:
                execute_query(
                    conn,
                    """
                    INSERT INTO watch_surfaced(device_id, show_id, surface, shown_at_utc)
                    VALUES (?, ?, ?, ?)
                    """,
                    (normalized_device, sid, surf, now),
                )
            except Exception:
                continue
        try:
            conn.commit()
        except Exception:
            pass
