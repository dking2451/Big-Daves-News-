from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from urllib.parse import urlparse

import feedparser

from app.db import execute_query, get_connection
from app.models import SourceConfig

KNOWN_SOURCE_DOMAINS = {
    "bbc.co.uk",
    "npr.org",
    "pbs.org",
    "espn.com",
    "formula1.com",
    "reuters.com",
    "apnews.com",
    "theguardian.com",
    "nytimes.com",
    "wsj.com",
    "ft.com",
    "bloomberg.com",
    "axios.com",
    "politico.com",
    "cnbc.com",
}


@dataclass
class SourceRequest:
    request_id: str
    name: str
    rss: str
    topic: str
    requested_by_email: str
    domain: str
    status: str
    created_at: str
    notes: str = ""


def domain_from_url(url: str) -> str:
    host = (urlparse(url).hostname or "").lower()
    if host.startswith("www."):
        return host[4:]
    return host


def validate_source_candidate(name: str, rss: str) -> tuple[bool, str, str]:
    domain = domain_from_url(rss)
    if not domain:
        return False, "Invalid RSS URL.", ""

    parsed = feedparser.parse(rss)
    entries = getattr(parsed, "entries", [])
    if len(entries) < 3:
        return False, "Feed validation failed: not enough recent entries.", domain

    known = any(domain == d or domain.endswith(f".{d}") for d in KNOWN_SOURCE_DOMAINS)
    if not known:
        return False, "Source domain is not in the trusted-known list yet.", domain

    if not name.strip():
        return False, "Source name is required.", domain

    return True, "Source validated and ready for review.", domain


def list_source_requests() -> list[SourceRequest]:
    with get_connection() as conn:
        rows = execute_query(
            conn,
            """
            SELECT request_id, name, rss, topic, requested_by_email, domain, status, created_at, notes
            FROM source_requests
            ORDER BY created_at DESC
            """
        ).fetchall()
    return [
        SourceRequest(
            request_id=str(row["request_id"]),
            name=str(row["name"]),
            rss=str(row["rss"]),
            topic=str(row["topic"]),
            requested_by_email=str(row["requested_by_email"]),
            domain=str(row["domain"]),
            status=str(row["status"]),
            created_at=str(row["created_at"]),
            notes=str(row["notes"]),
        )
        for row in rows
    ]


def create_source_request(name: str, rss: str, topic: str, requested_by_email: str) -> tuple[bool, str, SourceRequest | None]:
    ok, message, domain = validate_source_candidate(name=name, rss=rss)
    if not ok:
        return False, message, None

    normalized_rss = rss.strip()
    with get_connection() as conn:
        existing = execute_query(
            conn,
            """
            SELECT request_id FROM source_requests
            WHERE rss = ? AND status IN ('pending', 'approved')
            LIMIT 1
            """,
            (normalized_rss,),
        ).fetchone()
        if existing:
            return False, "This source is already submitted.", None

        request = SourceRequest(
            request_id=str(uuid.uuid4())[:8],
            name=name.strip(),
            rss=normalized_rss,
            topic=(topic or "general").strip().lower(),
            requested_by_email=requested_by_email.strip().lower(),
            domain=domain,
            status="pending",
            created_at=datetime.now(timezone.utc).isoformat(),
            notes=message,
        )
        execute_query(
            conn,
            """
            INSERT INTO source_requests(
                request_id, name, rss, topic, requested_by_email, domain, status, created_at, notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                request.request_id,
                request.name,
                request.rss,
                request.topic,
                request.requested_by_email,
                request.domain,
                request.status,
                request.created_at,
                request.notes,
            ),
        )
        conn.commit()
    return True, "Source submitted and pending approval.", request


def approve_source_request(request_id: str) -> tuple[bool, str]:
    with get_connection() as conn:
        row = execute_query(
            conn,
            """
            SELECT request_id, name, rss, topic, status
            FROM source_requests
            WHERE request_id = ?
            LIMIT 1
            """,
            (request_id,),
        ).fetchone()
        if not row:
            return False, "Request not found."
        if str(row["status"]) == "approved":
            return False, "Request already approved."

        existing_custom = execute_query(
            conn,
            "SELECT rss FROM custom_sources WHERE rss = ? LIMIT 1",
            (str(row["rss"]),),
        ).fetchone()
        if not existing_custom:
            execute_query(
                conn,
                """
                INSERT INTO custom_sources(rss, name, tier, trust_score, topic, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    str(row["rss"]),
                    str(row["name"]),
                    1,
                    0.9,
                    str(row["topic"]) or "general",
                    datetime.now(timezone.utc).isoformat(),
                ),
            )
        execute_query(
            conn,
            "UPDATE source_requests SET status = 'approved' WHERE request_id = ?",
            (request_id,),
        )
        conn.commit()
    return True, "Source approved and added."


def reject_source_request(request_id: str, note: str = "") -> tuple[bool, str]:
    with get_connection() as conn:
        row = execute_query(
            conn,
            "SELECT request_id FROM source_requests WHERE request_id = ? LIMIT 1",
            (request_id,),
        ).fetchone()
        if not row:
            return False, "Request not found."
        if note:
            execute_query(
                conn,
                """
                UPDATE source_requests
                SET status = 'rejected', notes = ?
                WHERE request_id = ?
                """,
                (note.strip(), request_id),
            )
        else:
            execute_query(
                conn,
                "UPDATE source_requests SET status = 'rejected' WHERE request_id = ?",
                (request_id,),
            )
        conn.commit()
    return True, "Source request rejected."


def load_custom_sources() -> list[SourceConfig]:
    with get_connection() as conn:
        rows = execute_query(
            conn,
            """
            SELECT name, tier, trust_score, rss, topic
            FROM custom_sources
            ORDER BY created_at DESC
            """
        ).fetchall()
    return [
        SourceConfig(
            name=str(row["name"]),
            tier=int(row["tier"]),
            trust_score=float(row["trust_score"]),
            rss=str(row["rss"]),
            topic=str(row["topic"]),
        )
        for row in rows
    ]
