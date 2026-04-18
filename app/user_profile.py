"""Accountless user profile document: JSON storage + compose from existing watch/sports tables."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from app.db import execute_query, get_connection
from app.watch_feedback import (
    get_watch_preferences,
    get_watch_progress_map,
    get_watch_saved_set,
    get_watch_user_reactions,
    normalize_device_id,
    normalize_show_id,
    set_watch_preferences,
    set_watch_progress,
    set_watch_reaction,
    set_watch_saved,
)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _load_stored_json(user_id: str) -> dict[str, Any]:
    uid = normalize_device_id(user_id)
    if not uid:
        return {}
    with get_connection() as conn:
        row = execute_query(
            conn,
            "SELECT json FROM user_profile_documents WHERE user_id = ? LIMIT 1",
            (uid,),
        ).fetchone()
    if not row:
        return {}
    raw = str(row["json"] if hasattr(row, "keys") else row[0])
    try:
        data = json.loads(raw)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_stored_json(user_id: str, payload: dict[str, Any]) -> str:
    uid = normalize_device_id(user_id)
    now = _now_iso()
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    with get_connection() as conn:
        existing = execute_query(
            conn,
            "SELECT user_id FROM user_profile_documents WHERE user_id = ? LIMIT 1",
            (uid,),
        ).fetchone()
        if existing:
            execute_query(
                conn,
                """
                UPDATE user_profile_documents
                SET json = ?, updated_at_utc = ?
                WHERE user_id = ?
                """,
                (body, now, uid),
            )
        else:
            execute_query(
                conn,
                """
                INSERT INTO user_profile_documents(user_id, json, updated_at_utc)
                VALUES (?, ?, ?)
                """,
                (uid, body, now),
            )
        conn.commit()
    return now


def _get_sports_preferences_raw(user_id: str) -> tuple[list[str], list[str]]:
    uid = normalize_device_id(user_id)
    if not uid:
        return [], []
    with get_connection() as conn:
        row = execute_query(
            conn,
            """
            SELECT favorite_leagues_json, favorite_teams_json
            FROM sports_preferences
            WHERE device_id = ?
            LIMIT 1
            """,
            (uid,),
        ).fetchone()
    if not row:
        return [], []
    try:
        leagues_raw = row["favorite_leagues_json"] if hasattr(row, "keys") else row[0]
        teams_raw = row["favorite_teams_json"] if hasattr(row, "keys") else row[1]
        leagues = json.loads(str(leagues_raw)) if leagues_raw else []
        teams = json.loads(str(teams_raw)) if teams_raw else []
        if not isinstance(leagues, list):
            leagues = []
        if not isinstance(teams, list):
            teams = []
        return [str(x) for x in leagues], [str(x) for x in teams]
    except Exception:
        return [], []


def _set_sports_preferences_inline(uid: str, leagues: list[str], teams: list[str]) -> None:
    leagues_j = json.dumps(leagues[:32], ensure_ascii=True)
    teams_j = json.dumps(teams[:64], ensure_ascii=True)
    now = _now_iso()
    with get_connection() as conn:
        existing = execute_query(
            conn,
            "SELECT device_id FROM sports_preferences WHERE device_id = ? LIMIT 1",
            (uid,),
        ).fetchone()
        if existing:
            execute_query(
                conn,
                """
                UPDATE sports_preferences
                SET favorite_leagues_json = ?, favorite_teams_json = ?, updated_at_utc = ?
                WHERE device_id = ?
                """,
                (leagues_j, teams_j, now, uid),
            )
        else:
            execute_query(
                conn,
                """
                INSERT INTO sports_preferences(
                    device_id, favorite_leagues_json, favorite_teams_json, updated_at_utc
                ) VALUES (?, ?, ?, ?)
                """,
                (uid, leagues_j, teams_j, now),
            )
        conn.commit()


def _recent_surfaces(user_id: str, limit: int = 48) -> list[dict[str, str]]:
    uid = normalize_device_id(user_id)
    if not uid:
        return []
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
                (uid, max(1, min(limit, 200))),
            ).fetchall()
        except Exception:
            return []
    out: list[dict[str, str]] = []
    for row in rows or []:
        sid = str(row["show_id"] if hasattr(row, "keys") else row[0])
        surf = str(row["surface"] if hasattr(row, "keys") else row[1])
        at = str(row["shown_at_utc"] if hasattr(row, "keys") else row[2])
        out.append({"show_id": sid, "surface": surf, "at": at})
    return out


def _profile_row_updated_at(user_id: str) -> str | None:
    uid = normalize_device_id(user_id)
    if not uid:
        return None
    with get_connection() as conn:
        row = execute_query(
            conn,
            "SELECT updated_at_utc FROM user_profile_documents WHERE user_id = ? LIMIT 1",
            (uid,),
        ).fetchone()
    if not row:
        return None
    return str(row["updated_at_utc"] if hasattr(row, "keys") else row[0] or "") or None


def compose_user_profile(user_id: str) -> dict[str, Any]:
    """Merge DB-backed watch/sports state with stored JSON preferences (iPhone / tvOS continuity)."""
    uid = normalize_device_id(user_id)
    stored = _load_stored_json(uid)
    if not uid:
        return {
            "schema_version": 1,
            "user_id": "",
            "updated_at": _now_iso(),
            "preferences": stored.get("preferences") or {},
            "watch": {},
            "behavior": {"recently_surfaced": [], **(stored.get("behavior") or {})},
            "sync": stored.get("sync") or {},
        }

    saved_ids = sorted(get_watch_saved_set(uid))
    progress = get_watch_progress_map(uid)
    reactions = get_watch_user_reactions(uid)
    liked_ids = sorted([k for k, v in reactions.items() if v == "up"])
    passed_ids = sorted([k for k, v in reactions.items() if v == "down"])
    watch_state: dict[str, str] = {**progress}
    for sid in saved_ids:
        watch_state.setdefault(sid, "not_started")

    wprefs = get_watch_preferences(uid)
    leagues, teams = _get_sports_preferences_raw(uid)

    sto_pref = stored.get("preferences") or {}
    pref_doc: dict[str, Any] = dict(sto_pref)
    pref_doc.setdefault("favorite_leagues", leagues)
    pref_doc.setdefault("favorite_teams", teams)
    pref_doc.setdefault("watch_episode_alerts", bool(wprefs.get("watch_episode_alerts")))
    pref_doc.setdefault("upcoming_release_reminders", bool(wprefs.get("upcoming_release_reminders")))

    doc_watch: dict[str, Any] = {
        "saved_show_ids": saved_ids,
        "watch_state_by_show": watch_state,
        "liked_show_ids": liked_ids,
        "passed_show_ids": passed_ids,
    }
    if isinstance(stored.get("watch"), dict):
        caught = stored["watch"].get("caught_up_by_show")
        if isinstance(caught, dict):
            doc_watch["caught_up_by_show"] = caught

    behavior: dict[str, Any] = {**(stored.get("behavior") or {})}
    behavior["recently_surfaced"] = _recent_surfaces(uid)

    row_ts = _profile_row_updated_at(uid)
    updated = row_ts or _now_iso()

    return {
        "schema_version": int(stored.get("schema_version") or 1),
        "user_id": uid,
        "updated_at": updated,
        "preferences": pref_doc,
        "watch": doc_watch,
        "behavior": behavior,
        "sync": stored.get("sync") or {},
    }


def _deep_merge(into: dict[str, Any], patch: dict[str, Any]) -> None:
    for k, v in patch.items():
        if k in into and isinstance(into[k], dict) and isinstance(v, dict):
            _deep_merge(into[k], v)
        else:
            into[k] = v


def _materialize_watch_to_tables(uid: str, watch: dict[str, Any]) -> None:
    saved = watch.get("saved_show_ids")
    states = watch.get("watch_state_by_show")
    liked = watch.get("liked_show_ids")
    passed = watch.get("passed_show_ids")

    saved_set: set[str] = set()
    if isinstance(saved, list):
        for x in saved:
            s = normalize_show_id(str(x))
            if s:
                saved_set.add(s)

    current_saved = get_watch_saved_set(uid)
    for sid in current_saved - saved_set:
        set_watch_saved(uid, sid, False)
    for sid in saved_set:
        set_watch_saved(uid, sid, True)

    if isinstance(states, dict):
        for sid_raw, st_raw in states.items():
            sid = normalize_show_id(str(sid_raw))
            st = str(st_raw).strip().lower()
            if not sid or st not in {"not_started", "watching", "finished"}:
                continue
            set_watch_progress(uid, sid, st)

    liked_set: set[str] = set()
    if isinstance(liked, list):
        for x in liked:
            s = normalize_show_id(str(x))
            if s:
                liked_set.add(s)
    passed_set: set[str] = set()
    if isinstance(passed, list):
        for x in passed:
            s = normalize_show_id(str(x))
            if s:
                passed_set.add(s)

    current_rx = get_watch_user_reactions(uid)
    for sid, r in list(current_rx.items()):
        if r == "up" and sid not in liked_set:
            set_watch_reaction(uid, sid, "none")
        elif r == "down" and sid not in passed_set:
            set_watch_reaction(uid, sid, "none")
    for sid in liked_set:
        set_watch_reaction(uid, sid, "up")
    for sid in passed_set:
        set_watch_reaction(uid, sid, "down")


def _materialize_preferences_to_tables(uid: str, prefs: dict[str, Any]) -> None:
    wep = prefs.get("watch_episode_alerts")
    urr = prefs.get("upcoming_release_reminders")
    if wep is not None or urr is not None:
        cur = get_watch_preferences(uid)
        set_watch_preferences(
            uid,
            bool(wep) if wep is not None else bool(cur.get("watch_episode_alerts")),
            bool(urr) if urr is not None else bool(cur.get("upcoming_release_reminders")),
        )
    fl = prefs.get("favorite_leagues")
    ft = prefs.get("favorite_teams")
    if isinstance(fl, list) or isinstance(ft, list):
        cur_l, cur_t = _get_sports_preferences_raw(uid)
        leagues = [str(x) for x in fl] if isinstance(fl, list) else cur_l
        teams = [str(x) for x in ft] if isinstance(ft, list) else cur_t
        _set_sports_preferences_inline(uid, leagues, teams)


def merge_patch_profile(user_id: str, patch: dict[str, Any]) -> dict[str, Any]:
    """Merge patch into overlay JSON, materialize watch/preferences to SQLite, return composed profile."""
    uid = normalize_device_id(user_id)
    if not uid:
        raise ValueError("invalid user_id")

    stored = _load_stored_json(uid)
    overlay: dict[str, Any] = {
        "schema_version": int(stored.get("schema_version") or 1),
        "preferences": dict(stored.get("preferences") or {}),
        "watch": dict(stored.get("watch") or {}),
        "behavior": dict(stored.get("behavior") or {}),
        "sync": dict(stored.get("sync") or {}),
    }
    if isinstance(patch.get("preferences"), dict):
        _deep_merge(overlay["preferences"], patch["preferences"])
    if isinstance(patch.get("watch"), dict):
        _deep_merge(overlay["watch"], patch["watch"])
    if isinstance(patch.get("behavior"), dict):
        _deep_merge(overlay["behavior"], patch["behavior"])
    if isinstance(patch.get("sync"), dict):
        _deep_merge(overlay["sync"], patch["sync"])
    if patch.get("schema_version") is not None:
        try:
            overlay["schema_version"] = int(patch["schema_version"])
        except Exception:
            pass

    _save_stored_json(uid, overlay)

    live = compose_user_profile(user_id)
    watch_block: dict[str, Any] = dict(live.get("watch") or {})
    pwatch = patch.get("watch")
    if isinstance(pwatch, dict):
        for key in ("saved_show_ids", "liked_show_ids", "passed_show_ids"):
            if key in pwatch:
                watch_block[key] = pwatch[key]
        if "watch_state_by_show" in pwatch and isinstance(pwatch["watch_state_by_show"], dict):
            merged_states = dict(watch_block.get("watch_state_by_show") or {})
            merged_states.update(pwatch["watch_state_by_show"])
            watch_block["watch_state_by_show"] = merged_states
    _materialize_watch_to_tables(uid, watch_block)
    _materialize_preferences_to_tables(uid, overlay.get("preferences") or {})

    return compose_user_profile(user_id)


def persist_composed_preferences_overlay(user_id: str, composed: dict[str, Any]) -> None:
    """Write preference keys from composed profile into overlay (genre/provider strings only)."""
    uid = normalize_device_id(user_id)
    if not uid:
        return
    prefs = composed.get("preferences") or {}
    if not isinstance(prefs, dict):
        return
    keep = {
        k: prefs[k]
        for k in (
            "preferred_providers",
            "preferred_genres",
            "favorite_teams",
            "favorite_leagues",
            "watch_episode_alerts",
            "upcoming_release_reminders",
        )
        if k in prefs
    }
    stored = _load_stored_json(uid)
    stored["preferences"] = {**(stored.get("preferences") or {}), **keep}
    stored["schema_version"] = int(composed.get("schema_version") or stored.get("schema_version") or 1)
    _save_stored_json(uid, stored)
