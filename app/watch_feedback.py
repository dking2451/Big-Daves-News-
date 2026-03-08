from __future__ import annotations

from datetime import datetime, timezone

from app.db import execute_query, get_connection


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalize_device_id(raw: str) -> str:
    cleaned = "".join(ch for ch in (raw or "").strip() if ch.isalnum() or ch in ("-", "_"))
    return cleaned[:64]


def normalize_show_id(raw: str) -> str:
    cleaned = "".join(ch for ch in (raw or "").strip() if ch.isalnum() or ch in ("-", "_"))
    return cleaned[:120]


def set_watch_seen(device_id: str, show_id: str, seen: bool) -> tuple[bool, str]:
    normalized_device = normalize_device_id(device_id)
    normalized_show = normalize_show_id(show_id)
    if not normalized_device or not normalized_show:
        return False, "Invalid device_id or show_id."
    with get_connection() as conn:
        if seen:
            now = _now_iso()
            existing = execute_query(
                conn,
                "SELECT device_id FROM watch_seen WHERE device_id = ? AND show_id = ? LIMIT 1",
                (normalized_device, normalized_show),
            ).fetchone()
            if existing:
                execute_query(
                    conn,
                    "UPDATE watch_seen SET updated_at_utc = ? WHERE device_id = ? AND show_id = ?",
                    (now, normalized_device, normalized_show),
                )
            else:
                execute_query(
                    conn,
                    """
                    INSERT INTO watch_seen(device_id, show_id, created_at_utc, updated_at_utc)
                    VALUES (?, ?, ?, ?)
                    """,
                    (normalized_device, normalized_show, now, now),
                )
        else:
            execute_query(
                conn,
                "DELETE FROM watch_seen WHERE device_id = ? AND show_id = ?",
                (normalized_device, normalized_show),
            )
        conn.commit()
    return True, "Updated seen state."


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
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return set()
    with get_connection() as conn:
        rows = execute_query(
            conn,
            "SELECT show_id FROM watch_seen WHERE device_id = ?",
            (normalized_device,),
        ).fetchall()
    return {str(row["show_id"]) if hasattr(row, "keys") else str(row[0]) for row in rows}


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
