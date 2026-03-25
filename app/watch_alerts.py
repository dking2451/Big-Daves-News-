from __future__ import annotations

import json
import os
import uuid
from datetime import datetime, timedelta, timezone

from app.db import execute_query, get_connection
from app.watch import (
    effective_last_air_for_compare,
    list_watch_shows,
    watch_release_badge,
)
from app.watch_feedback import (
    get_watch_caught_up_map,
    get_watch_preferences,
    get_watch_saved_set,
    normalize_device_id,
)


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _now_iso() -> str:
    return _now_utc().isoformat()


def _parse_iso(raw: str) -> datetime | None:
    value = str(raw or "").strip()
    if not value:
        return None
    try:
        if value.endswith("Z"):
            value = value[:-1] + "+00:00"
        parsed = datetime.fromisoformat(value)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except Exception:
        return None


def _parse_release_date(raw: str) -> datetime | None:
    value = str(raw or "").strip()
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except Exception:
        return None


def _days_until_release(release_date: str) -> int | None:
    parsed = _parse_release_date(release_date)
    if parsed is None:
        return None
    today = _now_utc().date()
    return (parsed.date() - today).days


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _list_target_devices(single_device_id: str = "") -> list[str]:
    normalized = normalize_device_id(single_device_id)
    if normalized:
        return [normalized]
    with get_connection() as conn:
        rows = execute_query(
            conn,
            """
            SELECT device_id FROM watch_watchlist
            UNION
            SELECT device_id FROM watch_preferences
            """,
        ).fetchall()
    devices: list[str] = []
    for row in rows:
        value = str(row["device_id"]) if hasattr(row, "keys") else str(row[0])
        cleaned = normalize_device_id(value)
        if cleaned:
            devices.append(cleaned)
    return sorted(set(devices))


def _candidate_key(device_id: str, show_id: str, reason: str, release_date: str) -> str:
    return f"{device_id}:{show_id}:{reason}:{(release_date or '').strip()}"


def _load_existing_candidate(conn, alert_key: str) -> tuple[str, str] | None:
    row = execute_query(
        conn,
        """
        SELECT first_detected_at_utc, last_would_send_at_utc
        FROM watch_alert_candidates
        WHERE alert_key = ?
        LIMIT 1
        """,
        (alert_key,),
    ).fetchone()
    if not row:
        return None
    if hasattr(row, "keys"):
        return str(row["first_detected_at_utc"]), str(row["last_would_send_at_utc"])
    return str(row[0]), str(row[1])


def _upsert_candidate(
    conn,
    *,
    alert_key: str,
    device_id: str,
    show_id: str,
    reason: str,
    release_date: str,
    now_iso: str,
    first_detected_at_utc: str,
    last_would_send_at_utc: str,
) -> None:
    execute_query(
        conn,
        """
        INSERT INTO watch_alert_candidates(
            alert_key, device_id, show_id, reason, release_date,
            first_detected_at_utc, last_detected_at_utc, last_would_send_at_utc
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(alert_key) DO UPDATE SET
            last_detected_at_utc = excluded.last_detected_at_utc,
            last_would_send_at_utc = excluded.last_would_send_at_utc
        """,
        (
            alert_key,
            device_id,
            show_id,
            reason,
            (release_date or "").strip(),
            first_detected_at_utc,
            now_iso,
            last_would_send_at_utc,
        ),
    )


def run_watch_alert_dry_run(device_id: str = "", preview_limit: int = 200) -> dict:
    cooldown_hours = max(1, min(_env_int("WATCH_ALERT_COOLDOWN_HOURS", 24), 168))
    upcoming_days = max(1, min(_env_int("WATCH_UPCOMING_REMINDER_DAYS", 14), 45))
    source_limit = max(10, min(_env_int("WATCH_ALERT_SOURCE_LIMIT", 50), 100))
    safe_preview_limit = max(1, min(int(preview_limit), 1000))
    now = _now_utc()
    now_iso = now.isoformat()

    shows, source = list_watch_shows(limit=source_limit)
    show_by_id = {show.show_id: show for show in shows}

    devices = _list_target_devices(single_device_id=device_id)
    candidates: list[dict] = []
    summary_by_reason: dict[str, int] = {}
    summary_by_provider: dict[str, int] = {}
    would_send_count = 0

    with get_connection() as conn:
        for current_device in devices:
            prefs = get_watch_preferences(current_device)
            if not prefs.get("watch_episode_alerts") and not prefs.get("upcoming_release_reminders"):
                continue

            saved_set = get_watch_saved_set(current_device)
            if not saved_set:
                continue
            caught_up_map = get_watch_caught_up_map(current_device)

            for show_id in saved_set:
                show = show_by_id.get(show_id)
                if not show:
                    continue
                badge = watch_release_badge(show)
                caught_up_release = caught_up_map.get(show.show_id, "")
                effective_last = effective_last_air_for_compare(show)
                has_new_episode = (
                    badge == "new"
                    and bool(effective_last)
                    and (not caught_up_release or effective_last > caught_up_release)
                )
                next_or_release = (show.next_episode_air_date or show.release_date or "").strip()
                days_until = _days_until_release(next_or_release)
                has_upcoming_release = (
                    badge in {"this_week", "upcoming"}
                    and days_until is not None
                    and 0 <= days_until <= upcoming_days
                )

                reasons: list[str] = []
                if prefs.get("watch_episode_alerts") and has_new_episode:
                    reasons.append("new_episode")
                if prefs.get("upcoming_release_reminders") and has_upcoming_release:
                    reasons.append("upcoming_release")

                for reason in reasons:
                    key_date = (
                        next_or_release if reason == "upcoming_release" else effective_last
                    )
                    key = _candidate_key(current_device, show.show_id, reason, key_date)
                    existing = _load_existing_candidate(conn, key)
                    first_detected = existing[0] if existing else now_iso
                    previous_send_iso = existing[1] if existing else ""
                    previous_send = _parse_iso(previous_send_iso)
                    in_cooldown = bool(
                        previous_send
                        and previous_send >= (now - timedelta(hours=cooldown_hours))
                    )
                    would_send = not in_cooldown
                    new_last_would_send = now_iso if would_send else (previous_send_iso or "")

                    _upsert_candidate(
                        conn,
                        alert_key=key,
                        device_id=current_device,
                        show_id=show.show_id,
                        reason=reason,
                        release_date=key_date,
                        now_iso=now_iso,
                        first_detected_at_utc=first_detected,
                        last_would_send_at_utc=new_last_would_send,
                    )

                    if len(candidates) < safe_preview_limit:
                        provider = show.providers[0] if show.providers else "Unknown"
                        candidates.append(
                            {
                                "device_id": current_device,
                                "show_id": show.show_id,
                                "title": show.title,
                                "provider": provider,
                                "reason": reason,
                                "release_date": key_date,
                                "days_until_release": (
                                    days_until if reason == "upcoming_release" else None
                                ),
                                "would_send": would_send,
                                "in_cooldown": in_cooldown,
                                "last_would_send_at_utc": previous_send_iso,
                            }
                        )

                    summary_by_reason[reason] = summary_by_reason.get(reason, 0) + 1
                    primary_provider = (show.providers[0] if show.providers else "unknown").strip() or "unknown"
                    summary_by_provider[primary_provider] = summary_by_provider.get(primary_provider, 0) + 1
                    if would_send:
                        would_send_count += 1

        run_id = str(uuid.uuid4())
        summary_json = json.dumps(
            {
                "source": source,
                "summary_by_reason": summary_by_reason,
                "summary_by_provider": summary_by_provider,
                "preview_count": len(candidates),
                "cooldown_hours": cooldown_hours,
                "upcoming_days": upcoming_days,
            },
            ensure_ascii=False,
        )
        execute_query(
            conn,
            """
            INSERT INTO watch_alert_runs(
                run_id, created_at_utc, dry_run, total_devices, total_candidates, would_send_count, summary_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                run_id,
                now_iso,
                1,
                len(devices),
                sum(summary_by_reason.values()),
                would_send_count,
                summary_json,
            ),
        )
        conn.commit()

    candidates.sort(
        key=lambda item: (
            0 if item.get("would_send") else 1,
            item.get("reason", ""),
            item.get("provider", ""),
        )
    )
    return {
        "success": True,
        "dry_run": True,
        "run_id": run_id,
        "source": source,
        "created_at_utc": now_iso,
        "total_devices": len(devices),
        "total_candidates": sum(summary_by_reason.values()),
        "would_send_count": would_send_count,
        "cooldown_hours": cooldown_hours,
        "upcoming_days": upcoming_days,
        "summary_by_reason": summary_by_reason,
        "summary_by_provider": summary_by_provider,
        "candidates": candidates,
    }
