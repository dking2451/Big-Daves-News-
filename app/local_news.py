from __future__ import annotations

import re
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

    query = _extract_query_terms(location_label)
    query_encoded = quote_plus(query)
    feed_url = (
        "https://news.google.com/rss/search"
        f"?q={query_encoded}&hl=en-US&gl=US&ceid=US:en"
    )
    parsed = feedparser.parse(feed_url)
    entries = getattr(parsed, "entries", []) or []

    items = []
    seen = set()
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
        published = str(getattr(entry, "published", "")).strip()
        summary = str(getattr(entry, "summary", "")).strip()
        image_url = _extract_image_url(entry)
        items.append(
            {
                "title": title,
                "url": link,
                "source_name": source,
                "published": published,
                "summary": summary,
                "image_url": image_url,
            }
        )
        if len(items) >= max(1, min(limit, 25)):
            break

    return {
        "success": True,
        "zip_code": normalized_zip,
        "location_label": location_label,
        "query": query,
        "items": items,
    }
