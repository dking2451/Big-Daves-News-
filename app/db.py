from __future__ import annotations

import json
import os
import sqlite3
from collections.abc import Sequence
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from typing import Any

_INIT_LOCK = Lock()
_INITIALIZED = False


def _database_url() -> str:
    return os.getenv("DATABASE_URL", "").strip()


def _sqlite_path() -> Path:
    return Path(os.getenv("DATA_DB_PATH", "data/big_daves_news.db"))


def is_postgres() -> bool:
    value = _database_url().lower()
    return value.startswith("postgres://") or value.startswith("postgresql://")


def _normalized_database_url() -> str:
    database_url = _database_url()
    if database_url.startswith("postgres://"):
        return "postgresql://" + database_url[len("postgres://") :]
    return database_url


def _connect_raw():
    if is_postgres():
        try:
            import psycopg
            from psycopg.rows import dict_row
        except Exception as exc:  # pragma: no cover - import error path
            raise RuntimeError(
                "Postgres DATABASE_URL is set but psycopg is unavailable. "
                "Install dependency: psycopg[binary]."
            ) from exc
        return psycopg.connect(_normalized_database_url(), row_factory=dict_row)

    db_path = _sqlite_path()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path, timeout=30)
    conn.row_factory = sqlite3.Row
    return conn


def _adapt_query(query: str) -> str:
    if is_postgres():
        return query.replace("?", "%s")
    return query


def execute_query(conn: Any, query: str, params: Sequence[Any] = ()) -> Any:
    return conn.execute(_adapt_query(query), tuple(params))


def _migrate_watch_seen_progress(conn: Any) -> None:
    """Add progress_state for not_started / watching / finished (default finished for legacy rows)."""
    try:
        if is_postgres():
            execute_query(
                conn,
                "ALTER TABLE watch_seen ADD COLUMN IF NOT EXISTS progress_state TEXT NOT NULL DEFAULT 'finished'",
            )
            return
        rows = execute_query(conn, "PRAGMA table_info(watch_seen)").fetchall()
        names = {str(r[1]) for r in (rows or [])}
        if "progress_state" in names:
            return
        execute_query(
            conn,
            "ALTER TABLE watch_seen ADD COLUMN progress_state TEXT NOT NULL DEFAULT 'finished'",
        )
    except Exception:
        pass


def _read_json(path: Path, default_payload: dict) -> dict:
    if not path.exists():
        return default_payload
    try:
        return json.loads(path.read_text())
    except Exception:
        return default_payload


def _table_count(conn: Any, table_name: str) -> int:
    row = execute_query(conn, f"SELECT COUNT(*) AS c FROM {table_name}").fetchone()
    if row is None:
        return 0
    if hasattr(row, "keys"):
        return int(row["c"])
    return int(row[0])  # pragma: no cover


def _migrate_from_json_if_needed(conn: Any) -> None:
    subscribers_json = Path("data/subscribers.json")
    requests_json = Path("data/source_requests.json")
    custom_sources_json = Path("data/custom_sources.json")

    if _table_count(conn, "subscribers") == 0:
        payload = _read_json(subscribers_json, {"emails": []})
        emails = payload.get("emails", [])
        for email in emails:
            normalized = str(email).strip().lower()
            if normalized:
                existing = execute_query(
                    conn,
                    "SELECT email FROM subscribers WHERE email = ? LIMIT 1",
                    (normalized,),
                ).fetchone()
                if not existing:
                    execute_query(
                        conn,
                        "INSERT INTO subscribers(email, created_at) VALUES (?, ?)",
                        (normalized, datetime.now(timezone.utc).isoformat()),
                    )

    if _table_count(conn, "source_requests") == 0:
        payload = _read_json(requests_json, {"requests": []})
        requests = payload.get("requests", [])
        for item in requests:
            request_id = str(item.get("request_id", "")).strip()
            name = str(item.get("name", "")).strip()
            rss = str(item.get("rss", "")).strip()
            if not request_id or not name or not rss:
                continue
            existing = execute_query(
                conn,
                "SELECT request_id FROM source_requests WHERE request_id = ? LIMIT 1",
                (request_id,),
            ).fetchone()
            if existing:
                continue
            execute_query(
                conn,
                """
                INSERT INTO source_requests(
                    request_id, name, rss, topic, requested_by_email, domain, status, created_at, notes
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    request_id,
                    name,
                    rss,
                    str(item.get("topic", "general")).strip().lower() or "general",
                    str(item.get("requested_by_email", "")).strip().lower(),
                    str(item.get("domain", "")).strip().lower(),
                    str(item.get("status", "pending")).strip().lower() or "pending",
                    str(item.get("created_at", datetime.now(timezone.utc).isoformat())).strip(),
                    str(item.get("notes", "")).strip(),
                ),
            )

    if _table_count(conn, "custom_sources") == 0:
        payload = _read_json(custom_sources_json, {"sources": []})
        sources = payload.get("sources", [])
        for item in sources:
            rss = str(item.get("rss", "")).strip()
            name = str(item.get("name", "")).strip()
            if not rss or not name:
                continue
            existing = execute_query(
                conn,
                "SELECT rss FROM custom_sources WHERE rss = ? LIMIT 1",
                (rss,),
            ).fetchone()
            if existing:
                continue
            execute_query(
                conn,
                """
                INSERT INTO custom_sources(
                    rss, name, tier, trust_score, topic, created_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    rss,
                    name,
                    int(item.get("tier", 1)),
                    float(item.get("trust_score", 0.9)),
                    str(item.get("topic", "general")).strip().lower() or "general",
                    datetime.now(timezone.utc).isoformat(),
                ),
            )


def _db_row_value(row: Any, key: str, index: int, default: Any = None) -> Any:
    if row is None:
        return default
    if hasattr(row, "keys"):
        try:
            return row[key]
        except Exception:
            return default
    if isinstance(row, (list, tuple)) and len(row) > index:
        return row[index]
    return default


def _watch_catalog_column_names(conn: Any) -> set[str]:
    if is_postgres():
        rows = execute_query(
            conn,
            """
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'watch_catalog'
            """,
            (),
        ).fetchall()
        return {str(_db_row_value(r, "column_name", 0, "")).lower() for r in (rows or [])}
    rows = execute_query(conn, "PRAGMA table_info(watch_catalog)").fetchall()
    out: set[str] = set()
    for r in rows or []:
        if hasattr(r, "keys"):
            out.add(str(r["name"]).lower())
        else:
            out.add(str(r[1]).lower())
    return out


def _migrate_watch_seen_progress(conn: Any) -> None:
    """Add progress_state for not_started / watching / finished (legacy rows treated as finished)."""
    try:
        if is_postgres():
            execute_query(
                conn,
                """
                ALTER TABLE watch_seen
                ADD COLUMN IF NOT EXISTS progress_state TEXT NOT NULL DEFAULT 'finished'
                """,
            )
            return
        rows = execute_query(conn, "PRAGMA table_info(watch_seen)").fetchall()
        names = {str(r[1]) for r in (rows or [])} if rows else set()
        if "progress_state" in names:
            return
        execute_query(
            conn,
            "ALTER TABLE watch_seen ADD COLUMN progress_state TEXT NOT NULL DEFAULT 'finished'",
        )
    except Exception:
        pass


def _ensure_user_profile_documents_table(conn: Any) -> None:
    try:
        execute_query(
            conn,
            """
            CREATE TABLE IF NOT EXISTS user_profile_documents (
                user_id TEXT PRIMARY KEY,
                json TEXT NOT NULL DEFAULT '{}',
                updated_at_utc TEXT NOT NULL DEFAULT ''
            )
            """,
        )
    except Exception:
        pass


def _ensure_watch_surfaced_table(conn: Any) -> None:
    """Lightweight log of what we surfaced to a device (anti-repetition)."""
    try:
        if is_postgres():
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS watch_surfaced (
                    id BIGSERIAL PRIMARY KEY,
                    device_id TEXT NOT NULL,
                    show_id TEXT NOT NULL,
                    surface TEXT NOT NULL,
                    shown_at_utc TEXT NOT NULL
                )
                """,
            )
        else:
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS watch_surfaced (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    device_id TEXT NOT NULL,
                    show_id TEXT NOT NULL,
                    surface TEXT NOT NULL,
                    shown_at_utc TEXT NOT NULL
                )
                """,
            )
        execute_query(
            conn,
            "CREATE INDEX IF NOT EXISTS idx_watch_surfaced_device_time ON watch_surfaced(device_id, shown_at_utc)",
        )
        execute_query(
            conn,
            "CREATE INDEX IF NOT EXISTS idx_watch_surfaced_device_surface ON watch_surfaced(device_id, surface)",
        )
    except Exception:
        pass


def _migrate_watch_catalog_schema(conn: Any) -> None:
    """Add TMDB cache columns to watch_catalog (idempotent)."""
    try:
        names = _watch_catalog_column_names(conn)
    except Exception:
        return
    alters: list[str] = []
    if "backdrop_url" not in names:
        alters.append("ALTER TABLE watch_catalog ADD COLUMN backdrop_url TEXT NOT NULL DEFAULT ''")
    if "tmdb_first_air_date" not in names:
        alters.append("ALTER TABLE watch_catalog ADD COLUMN tmdb_first_air_date TEXT NOT NULL DEFAULT ''")
    if "tmdb_canonical_title" not in names:
        alters.append("ALTER TABLE watch_catalog ADD COLUMN tmdb_canonical_title TEXT NOT NULL DEFAULT ''")
    if "tmdb_last_refreshed_at" not in names:
        alters.append("ALTER TABLE watch_catalog ADD COLUMN tmdb_last_refreshed_at TEXT NOT NULL DEFAULT ''")
    if "tmdb_match_confidence" not in names:
        alters.append("ALTER TABLE watch_catalog ADD COLUMN tmdb_match_confidence INTEGER")
    for stmt in alters:
        try:
            execute_query(conn, stmt, ())
        except Exception:
            continue


def init_db() -> None:
    global _INITIALIZED
    with _INIT_LOCK:
        db_path = _sqlite_path()
        if _INITIALIZED and (is_postgres() or db_path.exists()):
            try:
                with _connect_raw() as conn:
                    _migrate_watch_catalog_schema(conn)
                    _migrate_watch_seen_progress(conn)
                    _ensure_watch_surfaced_table(conn)
                    _ensure_user_profile_documents_table(conn)
                    conn.commit()
            except Exception:
                pass
            return

        with _connect_raw() as conn:
            if not is_postgres():
                execute_query(conn, "PRAGMA journal_mode=WAL")
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS subscribers (
                    email TEXT PRIMARY KEY,
                    created_at TEXT NOT NULL
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS source_requests (
                    request_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    rss TEXT NOT NULL,
                    topic TEXT NOT NULL,
                    requested_by_email TEXT NOT NULL,
                    domain TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    notes TEXT NOT NULL DEFAULT ''
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS custom_sources (
                    rss TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    tier INTEGER NOT NULL,
                    trust_score REAL NOT NULL,
                    topic TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS daily_email_sends (
                    send_date_local TEXT PRIMARY KEY,
                    timezone_name TEXT NOT NULL,
                    sent_at_utc TEXT NOT NULL
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS daily_push_sends (
                    send_date_local TEXT PRIMARY KEY,
                    timezone_name TEXT NOT NULL,
                    sent_at_utc TEXT NOT NULL
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS local_news_cache (
                    zip_code TEXT PRIMARY KEY,
                    payload_json TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS article_saves (
                    device_id TEXT NOT NULL,
                    article_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    url TEXT NOT NULL,
                    source_name TEXT NOT NULL DEFAULT '',
                    summary TEXT NOT NULL DEFAULT '',
                    image_url TEXT NOT NULL DEFAULT '',
                    created_at_utc TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL,
                    PRIMARY KEY (device_id, article_id)
                )
                """
            )
            if is_postgres():
                execute_query(
                    conn,
                    """
                    CREATE TABLE IF NOT EXISTS app_events (
                        id BIGSERIAL PRIMARY KEY,
                        device_id TEXT NOT NULL,
                        event_name TEXT NOT NULL,
                        event_props_json TEXT NOT NULL DEFAULT '{}',
                        created_at_utc TEXT NOT NULL
                    )
                    """
                )
            else:
                execute_query(
                    conn,
                    """
                    CREATE TABLE IF NOT EXISTS app_events (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        device_id TEXT NOT NULL,
                        event_name TEXT NOT NULL,
                        event_props_json TEXT NOT NULL DEFAULT '{}',
                        created_at_utc TEXT NOT NULL
                    )
                    """
                )
            if is_postgres():
                execute_query(
                    conn,
                    """
                    CREATE TABLE IF NOT EXISTS api_request_metrics (
                        id BIGSERIAL PRIMARY KEY,
                        endpoint TEXT NOT NULL,
                        success INTEGER NOT NULL,
                        duration_ms INTEGER NOT NULL,
                        error_text TEXT NOT NULL DEFAULT '',
                        created_at_utc TEXT NOT NULL
                    )
                    """
                )
            else:
                execute_query(
                    conn,
                    """
                    CREATE TABLE IF NOT EXISTS api_request_metrics (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        endpoint TEXT NOT NULL,
                        success INTEGER NOT NULL,
                        duration_ms INTEGER NOT NULL,
                        error_text TEXT NOT NULL DEFAULT '',
                        created_at_utc TEXT NOT NULL
                    )
                    """
                )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS push_devices (
                    device_token TEXT NOT NULL,
                    platform TEXT NOT NULL,
                    subscriber_email TEXT NOT NULL DEFAULT '',
                    app_bundle_id TEXT NOT NULL DEFAULT '',
                    timezone_name TEXT NOT NULL DEFAULT '',
                    enabled INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    last_seen_at TEXT NOT NULL,
                    PRIMARY KEY (device_token, platform)
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS watch_seen (
                    device_id TEXT NOT NULL,
                    show_id TEXT NOT NULL,
                    created_at_utc TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL,
                    PRIMARY KEY (device_id, show_id)
                )
                """
            )
            _migrate_watch_seen_progress(conn)
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS watch_reactions (
                    device_id TEXT NOT NULL,
                    show_id TEXT NOT NULL,
                    reaction TEXT NOT NULL,
                    created_at_utc TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL,
                    PRIMARY KEY (device_id, show_id)
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS watch_watchlist (
                    device_id TEXT NOT NULL,
                    show_id TEXT NOT NULL,
                    created_at_utc TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL,
                    PRIMARY KEY (device_id, show_id)
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS watch_caught_up (
                    device_id TEXT NOT NULL,
                    show_id TEXT NOT NULL,
                    last_caught_up_release_date TEXT NOT NULL DEFAULT '',
                    last_caught_up_at_utc TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL,
                    PRIMARY KEY (device_id, show_id)
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS watch_preferences (
                    device_id TEXT PRIMARY KEY,
                    watch_episode_alerts INTEGER NOT NULL DEFAULT 0,
                    upcoming_release_reminders INTEGER NOT NULL DEFAULT 0,
                    updated_at_utc TEXT NOT NULL
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS sports_preferences (
                    device_id TEXT PRIMARY KEY,
                    favorite_leagues_json TEXT NOT NULL DEFAULT '[]',
                    favorite_teams_json TEXT NOT NULL DEFAULT '[]',
                    updated_at_utc TEXT NOT NULL
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS watch_alert_candidates (
                    alert_key TEXT PRIMARY KEY,
                    device_id TEXT NOT NULL,
                    show_id TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    release_date TEXT NOT NULL DEFAULT '',
                    first_detected_at_utc TEXT NOT NULL,
                    last_detected_at_utc TEXT NOT NULL,
                    last_would_send_at_utc TEXT NOT NULL DEFAULT ''
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS watch_alert_runs (
                    run_id TEXT PRIMARY KEY,
                    created_at_utc TEXT NOT NULL,
                    dry_run INTEGER NOT NULL,
                    total_devices INTEGER NOT NULL,
                    total_candidates INTEGER NOT NULL,
                    would_send_count INTEGER NOT NULL,
                    summary_json TEXT NOT NULL
                )
                """
            )
            execute_query(
                conn,
                """
                CREATE TABLE IF NOT EXISTS watch_catalog (
                    show_id TEXT PRIMARY KEY,
                    title TEXT NOT NULL DEFAULT '',
                    tmdb_tv_id INTEGER,
                    poster_url TEXT NOT NULL DEFAULT '',
                    poster_confidence INTEGER,
                    poster_resolution_path TEXT NOT NULL DEFAULT '',
                    poster_status TEXT NOT NULL DEFAULT '',
                    updated_at_utc TEXT NOT NULL
                )
                """
            )
            _migrate_watch_catalog_schema(conn)
            _migrate_watch_seen_progress(conn)
            _ensure_watch_surfaced_table(conn)
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_source_requests_status ON source_requests(status)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_source_requests_rss ON source_requests(rss)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_push_devices_enabled ON push_devices(enabled)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_push_devices_platform_enabled ON push_devices(platform, enabled)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_local_news_cache_updated ON local_news_cache(updated_at_utc)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_article_saves_device ON article_saves(device_id)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_article_saves_updated ON article_saves(updated_at_utc)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_app_events_device_time ON app_events(device_id, created_at_utc)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_app_events_name_time ON app_events(event_name, created_at_utc)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_api_request_metrics_endpoint_time ON api_request_metrics(endpoint, created_at_utc)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_seen_device ON watch_seen(device_id)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_seen_show ON watch_seen(show_id)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_reactions_show ON watch_reactions(show_id)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_reactions_device ON watch_reactions(device_id)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_watchlist_device ON watch_watchlist(device_id)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_watchlist_show ON watch_watchlist(show_id)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_caught_up_device ON watch_caught_up(device_id)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_caught_up_show ON watch_caught_up(show_id)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_preferences_updated ON watch_preferences(updated_at_utc)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_sports_preferences_updated ON sports_preferences(updated_at_utc)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_alert_candidates_device ON watch_alert_candidates(device_id)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_alert_candidates_detected ON watch_alert_candidates(last_detected_at_utc)"
            )
            execute_query(
                conn,
                "CREATE INDEX IF NOT EXISTS idx_watch_alert_runs_created ON watch_alert_runs(created_at_utc)"
            )
            _migrate_from_json_if_needed(conn)
            _ensure_user_profile_documents_table(conn)
            conn.commit()
        _INITIALIZED = True


def get_connection():
    init_db()
    return _connect_raw()
