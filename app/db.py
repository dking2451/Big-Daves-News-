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


def init_db() -> None:
    global _INITIALIZED
    with _INIT_LOCK:
        db_path = _sqlite_path()
        if _INITIALIZED and (is_postgres() or db_path.exists()):
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
                "CREATE INDEX IF NOT EXISTS idx_api_request_metrics_endpoint_time ON api_request_metrics(endpoint, created_at_utc)"
            )
            _migrate_from_json_if_needed(conn)
            conn.commit()
        _INITIALIZED = True


def get_connection():
    init_db()
    return _connect_raw()
