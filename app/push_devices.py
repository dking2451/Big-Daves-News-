from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timezone

from app.db import execute_query, get_connection

_TOKEN_RE = re.compile(r"^[A-Fa-f0-9]{32,512}$")
_EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")


@dataclass
class PushDevice:
    device_token: str
    platform: str
    subscriber_email: str
    app_bundle_id: str
    timezone_name: str


def _normalize_platform(platform: str) -> str:
    value = (platform or "").strip().lower()
    if value in {"ios", "android"}:
        return value
    return "ios"


def _normalize_token(token: str) -> str:
    value = (token or "").strip().replace(" ", "")
    value = value.removeprefix("<").removesuffix(">")
    return value


def _normalize_email(email: str | None) -> str:
    value = (email or "").strip().lower()
    if not value:
        return ""
    if not _EMAIL_RE.fullmatch(value):
        return ""
    return value


def upsert_push_device(
    *,
    device_token: str,
    platform: str,
    subscriber_email: str | None = None,
    app_bundle_id: str | None = None,
    timezone_name: str | None = None,
) -> tuple[bool, str]:
    normalized_token = _normalize_token(device_token)
    if not _TOKEN_RE.fullmatch(normalized_token):
        return False, "Invalid device token format."

    normalized_platform = _normalize_platform(platform)
    normalized_email = _normalize_email(subscriber_email)
    normalized_bundle = (app_bundle_id or "").strip()
    normalized_timezone = (timezone_name or "").strip()
    now = datetime.now(timezone.utc).isoformat()

    with get_connection() as conn:
        execute_query(
            conn,
            """
            INSERT INTO push_devices(
                device_token, platform, subscriber_email, app_bundle_id, timezone_name,
                enabled, created_at, updated_at, last_seen_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(device_token, platform) DO UPDATE SET
                subscriber_email = excluded.subscriber_email,
                app_bundle_id = excluded.app_bundle_id,
                timezone_name = excluded.timezone_name,
                enabled = 1,
                updated_at = excluded.updated_at,
                last_seen_at = excluded.last_seen_at
            """,
            (
                normalized_token,
                normalized_platform,
                normalized_email,
                normalized_bundle,
                normalized_timezone,
                1,
                now,
                now,
                now,
            ),
        )
        conn.commit()
    return True, "Push device token registered."


def unregister_push_device(*, device_token: str, platform: str) -> tuple[bool, str]:
    normalized_token = _normalize_token(device_token)
    if not _TOKEN_RE.fullmatch(normalized_token):
        return False, "Invalid device token format."
    normalized_platform = _normalize_platform(platform)
    now = datetime.now(timezone.utc).isoformat()

    with get_connection() as conn:
        row = execute_query(
            conn,
            """
            SELECT device_token FROM push_devices
            WHERE device_token = ? AND platform = ?
            LIMIT 1
            """,
            (normalized_token, normalized_platform),
        ).fetchone()
        if not row:
            return False, "Token not found."
        execute_query(
            conn,
            """
            UPDATE push_devices
            SET enabled = 0, updated_at = ?
            WHERE device_token = ? AND platform = ?
            """,
            (now, normalized_token, normalized_platform),
        )
        conn.commit()
    return True, "Push device token unregistered."


def active_push_device_count() -> int:
    with get_connection() as conn:
        row = execute_query(
            conn,
            "SELECT COUNT(*) AS c FROM push_devices WHERE enabled = 1",
        ).fetchone()
    if not row:
        return 0
    return int(row["c"])


def list_active_push_devices(platform: str = "ios", limit: int = 500) -> list[PushDevice]:
    normalized_platform = _normalize_platform(platform)
    safe_limit = max(1, min(5000, int(limit)))
    with get_connection() as conn:
        rows = execute_query(
            conn,
            """
            SELECT device_token, platform, subscriber_email, app_bundle_id, timezone_name
            FROM push_devices
            WHERE enabled = 1 AND platform = ?
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            (normalized_platform, safe_limit),
        ).fetchall()
    return [
        PushDevice(
            device_token=str(row["device_token"]),
            platform=str(row["platform"]),
            subscriber_email=str(row["subscriber_email"]),
            app_bundle_id=str(row["app_bundle_id"]),
            timezone_name=str(row["timezone_name"]),
        )
        for row in rows
    ]


def disable_push_device(*, device_token: str, platform: str) -> None:
    normalized_token = _normalize_token(device_token)
    normalized_platform = _normalize_platform(platform)
    if not _TOKEN_RE.fullmatch(normalized_token):
        return
    now = datetime.now(timezone.utc).isoformat()
    with get_connection() as conn:
        execute_query(
            conn,
            """
            UPDATE push_devices
            SET enabled = 0, updated_at = ?
            WHERE device_token = ? AND platform = ?
            """,
            (now, normalized_token, normalized_platform),
        )
        conn.commit()
