from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import feedparser

from app.models import SourceConfig

SOURCE_REQUESTS_PATH = Path("data/source_requests.json")
CUSTOM_SOURCES_PATH = Path("data/custom_sources.json")

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


def _ensure_store(path: Path, default_payload: dict) -> None:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(default_payload, indent=2))


def _read_json(path: Path, default_payload: dict) -> dict:
    _ensure_store(path, default_payload)
    return json.loads(path.read_text())


def _write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2))


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
    payload = _read_json(SOURCE_REQUESTS_PATH, {"requests": []})
    requests = payload.get("requests", [])
    result = [SourceRequest(**item) for item in requests]
    result.sort(key=lambda r: r.created_at, reverse=True)
    return result


def create_source_request(name: str, rss: str, topic: str, requested_by_email: str) -> tuple[bool, str, SourceRequest | None]:
    ok, message, domain = validate_source_candidate(name=name, rss=rss)
    if not ok:
        return False, message, None

    existing_requests = list_source_requests()
    for item in existing_requests:
        if item.rss == rss and item.status in {"pending", "approved"}:
            return False, "This source is already submitted.", None

    request = SourceRequest(
        request_id=str(uuid.uuid4())[:8],
        name=name.strip(),
        rss=rss.strip(),
        topic=(topic or "general").strip().lower(),
        requested_by_email=requested_by_email.strip().lower(),
        domain=domain,
        status="pending",
        created_at=datetime.now(timezone.utc).isoformat(),
        notes=message,
    )
    payload = _read_json(SOURCE_REQUESTS_PATH, {"requests": []})
    payload["requests"].append(request.__dict__)
    _write_json(SOURCE_REQUESTS_PATH, payload)
    return True, "Source submitted and pending approval.", request


def approve_source_request(request_id: str) -> tuple[bool, str]:
    payload = _read_json(SOURCE_REQUESTS_PATH, {"requests": []})
    requests = payload.get("requests", [])
    selected = None
    for item in requests:
        if item.get("request_id") == request_id:
            selected = item
            break
    if not selected:
        return False, "Request not found."
    if selected.get("status") == "approved":
        return False, "Request already approved."

    custom_payload = _read_json(CUSTOM_SOURCES_PATH, {"sources": []})
    sources = custom_payload.get("sources", [])
    if not any(source.get("rss") == selected.get("rss") for source in sources):
        sources.append(
            {
                "name": selected["name"],
                "tier": 1,
                "trust_score": 0.9,
                "rss": selected["rss"],
                "topic": selected.get("topic", "general"),
            }
        )
    custom_payload["sources"] = sources
    _write_json(CUSTOM_SOURCES_PATH, custom_payload)

    selected["status"] = "approved"
    _write_json(SOURCE_REQUESTS_PATH, payload)
    return True, "Source approved and added."


def reject_source_request(request_id: str, note: str = "") -> tuple[bool, str]:
    payload = _read_json(SOURCE_REQUESTS_PATH, {"requests": []})
    requests = payload.get("requests", [])
    for item in requests:
        if item.get("request_id") == request_id:
            item["status"] = "rejected"
            if note:
                item["notes"] = note.strip()
            _write_json(SOURCE_REQUESTS_PATH, payload)
            return True, "Source request rejected."
    return False, "Request not found."


def load_custom_sources() -> list[SourceConfig]:
    payload = _read_json(CUSTOM_SOURCES_PATH, {"sources": []})
    return [SourceConfig(**source) for source in payload.get("sources", [])]
