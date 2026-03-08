from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from urllib.parse import quote_plus

import feedparser

from app.weather import geocode_zip


def _normalize_zip(zip_code: str) -> str:
    digits = "".join(ch for ch in (zip_code or "") if ch.isdigit())
    if len(digits) >= 5:
        return digits[:5]
    return "75201"


def _extract_query_terms(location_label: str) -> str:
    parts = [part.strip() for part in location_label.split(",") if part.strip()]
    if not parts:
        return "local news"
    city = parts[0]
    region = parts[1] if len(parts) > 1 else ""
    base = f"{city} {region}".strip()
    return f"{base} local news"


def _query_candidates(location_label: str, zip_code: str) -> list[str]:
    parts = [part.strip() for part in location_label.split(",") if part.strip()]
    city = parts[0] if parts else ""
    region = parts[1] if len(parts) > 1 else ""
    base = f"{city} {region}".strip()
    candidates = [
        _extract_query_terms(location_label),
        f"{base} breaking news".strip(),
        f"{city} news".strip(),
        f"{city} headlines".strip(),
        f"{zip_code} local news".strip(),
    ]
    # Add recency hint to improve freshness and avoid stale/no-result clusters.
    with_recency = [f"{query} when:7d".strip() for query in candidates if query]
    merged = candidates + with_recency
    # Preserve order while deduplicating.
    ordered_unique: list[str] = []
    seen: set[str] = set()
    for query in merged:
        key = query.lower().strip()
        if not key or key in seen:
            continue
        seen.add(key)
        ordered_unique.append(query)
    return ordered_unique


def _first_http_url(*candidates: str) -> str:
    for candidate in candidates:
        value = str(candidate or "").strip()
        if value.startswith("http://") or value.startswith("https://"):
            return value
    return ""


def _extract_image_url(entry) -> str:
    media_content = getattr(entry, "media_content", None) or []
    for media in media_content:
        if isinstance(media, dict):
            url = _first_http_url(media.get("url"))
            if url:
                return url

    media_thumbnail = getattr(entry, "media_thumbnail", None) or []
    for media in media_thumbnail:
        if isinstance(media, dict):
            url = _first_http_url(media.get("url"))
            if url:
                return url

    links = getattr(entry, "links", None) or []
    for link in links:
        if isinstance(link, dict):
            href = _first_http_url(link.get("href"))
            link_type = str(link.get("type", "")).lower()
            rel = str(link.get("rel", "")).lower()
            if href and ("image" in link_type or rel == "enclosure"):
                return href

    summary = str(getattr(entry, "summary", "")).strip()
    if summary:
        match = re.search(r'<img[^>]+src=["\']([^"\']+)["\']', summary, flags=re.IGNORECASE)
        if match:
            url = _first_http_url(match.group(1))
            if url:
                return url
    return ""


def _published_text(entry) -> str:
    return str(getattr(entry, "published", "") or getattr(entry, "updated", "")).strip()


def _published_datetime(entry) -> datetime | None:
    parsed = getattr(entry, "published_parsed", None) or getattr(entry, "updated_parsed", None)
    if parsed is None:
        return None
    try:
        return datetime(*parsed[:6], tzinfo=timezone.utc)
    except Exception:
        return None


def fetch_local_news(zip_code: str, limit: int = 10) -> dict:
    normalized_zip = _normalize_zip(zip_code)
    try:
        _lat, _lon, location_label = geocode_zip(normalized_zip)
    except Exception:
        return {
            "success": False,
            "message": "Unable to resolve ZIP for local news.",
            "zip_code": normalized_zip,
            "location_label": "",
            "items": [],
        }

    items = []
    seen = set()
    now_utc = datetime.now(timezone.utc)
    recent_cutoff = now_utc - timedelta(days=5)
    max_items = max(1, min(limit, 25))
    query_used = ""
    stale_pool: list[dict] = []
    for query in _query_candidates(location_label, normalized_zip):
        query_encoded = quote_plus(query)
        feed_url = (
            "https://news.google.com/rss/search"
            f"?q={query_encoded}&hl=en-US&gl=US&ceid=US:en"
        )
        parsed = feedparser.parse(feed_url)
        entries = getattr(parsed, "entries", []) or []
        if entries and not query_used:
            query_used = query

        for entry in entries:
            title = str(getattr(entry, "title", "")).strip()
            link = str(getattr(entry, "link", "")).strip()
            if not title or not link:
                continue
            key = (title.lower(), link.lower())
            if key in seen:
                continue
            seen.add(key)
            source = ""
            source_obj = getattr(entry, "source", None)
            if isinstance(source_obj, dict):
                source = str(source_obj.get("title", "")).strip()
            published = _published_text(entry)
            published_dt = _published_datetime(entry)
            summary = str(getattr(entry, "summary", "")).strip()
            image_url = _extract_image_url(entry)
            item = {
                "title": title,
                "url": link,
                "source_name": source,
                "published": published,
                "summary": summary,
                "image_url": image_url,
            }
            if published_dt is None or published_dt >= recent_cutoff:
                items.append(item)
            else:
                stale_pool.append(item)
            if len(items) >= max_items:
                break
        if len(items) >= max_items:
            break

    if len(items) < max_items and stale_pool:
        needed = max_items - len(items)
        items.extend(stale_pool[:needed])

    return {
        "success": True,
        "zip_code": normalized_zip,
        "location_label": location_label,
        "query": query_used or _extract_query_terms(location_label),
        "items": items,
    }
