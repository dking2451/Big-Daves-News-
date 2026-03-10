from __future__ import annotations

import re
from html import unescape
from datetime import datetime, timedelta, timezone
from json import dumps, loads
from urllib.error import URLError
from urllib.parse import quote_plus
from urllib.request import Request, urlopen

import feedparser

from app.db import execute_query, get_connection

LIKELY_PAYWALLED_SOURCES = (
    "dallas news",
    "the dallas morning news",
    "new york times",
    "wall street journal",
    "financial times",
    "the information",
    "the athletic",
    "barron's",
    "washington post",
)
LOCAL_NEWS_CACHE_TTL_SECONDS = 3600


def _normalize_zip(zip_code: str) -> str:
    digits = "".join(ch for ch in (zip_code or "") if ch.isdigit())
    if len(digits) >= 5:
        return digits[:5]
    return "75201"


def _source_key(source_name: str) -> str:
    normalized = (source_name or "").strip().lower()
    if not normalized:
        return "unknown-source"
    return normalized


def _per_source_cap(limit: int) -> int:
    # Keep source diversity high while still allowing enough stories.
    if limit <= 4:
        return 1
    if limit <= 10:
        return 2
    return 3


def _parse_iso_datetime(raw: str) -> datetime | None:
    value = (raw or "").strip()
    if not value:
        return None
    try:
        # Support both "...Z" and explicit offsets.
        if value.endswith("Z"):
            value = value[:-1] + "+00:00"
        return datetime.fromisoformat(value)
    except Exception:
        return None


def _load_cached_local_news(zip_code: str, ttl_seconds: int) -> dict | None:
    with get_connection() as conn:
        row = execute_query(
            conn,
            """
            SELECT payload_json, updated_at_utc
            FROM local_news_cache
            WHERE zip_code = ?
            LIMIT 1
            """,
            (zip_code,),
        ).fetchone()
    if not row:
        return None

    updated_raw = row["updated_at_utc"] if hasattr(row, "keys") else row[1]
    payload_raw = row["payload_json"] if hasattr(row, "keys") else row[0]
    updated_at = _parse_iso_datetime(str(updated_raw))
    if updated_at is None:
        return None
    age_seconds = (datetime.now(timezone.utc) - updated_at.astimezone(timezone.utc)).total_seconds()
    if age_seconds > max(60, ttl_seconds):
        return None
    try:
        payload = loads(str(payload_raw))
    except Exception:
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def _save_cached_local_news(zip_code: str, payload: dict) -> None:
    now_iso = datetime.now(timezone.utc).isoformat()
    payload_json = dumps(payload, ensure_ascii=False)
    with get_connection() as conn:
        execute_query(
            conn,
            """
            INSERT INTO local_news_cache(zip_code, payload_json, updated_at_utc)
            VALUES (?, ?, ?)
            ON CONFLICT(zip_code) DO UPDATE SET
                payload_json = excluded.payload_json,
                updated_at_utc = excluded.updated_at_utc
            """,
            (zip_code, payload_json, now_iso),
        )
        conn.commit()


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
    if city:
        candidates = [
            _extract_query_terms(location_label),
            f"{city} breaking news when:3d".strip(),
            f"{city} news when:3d".strip(),
        ]
    else:
        candidates = [
            f"{zip_code} local news when:3d".strip(),
            f"{zip_code} breaking news".strip(),
        ]
    merged = candidates
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


def _fetch_entries_for_query(query: str, timeout_seconds: float = 3.0) -> list:
    query_encoded = quote_plus(query)
    feed_url = (
        "https://news.google.com/rss/search"
        f"?q={query_encoded}&hl=en-US&gl=US&ceid=US:en"
    )
    request = Request(
        feed_url,
        headers={
            "User-Agent": "BigDavesNews/1.0 (+https://big-daves-news-web.onrender.com)"
        },
    )
    try:
        with urlopen(request, timeout=timeout_seconds) as response:
            payload = response.read()
    except (TimeoutError, URLError):
        return []
    parsed = feedparser.parse(payload)
    return getattr(parsed, "entries", []) or []


def _fast_geocode_location_label(zip_code: str, timeout_seconds: float = 3.0) -> str:
    query_encoded = quote_plus(zip_code)
    url = (
        "https://geocoding-api.open-meteo.com/v1/search"
        f"?name={query_encoded}&count=1&language=en&format=json"
    )
    request = Request(
        url,
        headers={
            "User-Agent": "BigDavesNews/1.0 (+https://big-daves-news-web.onrender.com)"
        },
    )
    try:
        with urlopen(request, timeout=timeout_seconds) as response:
            payload = loads(response.read().decode("utf-8"))
    except Exception:
        return ""

    results = payload.get("results") or []
    if not results:
        return ""
    first = results[0]
    city = str(first.get("name", "")).strip()
    admin = str(first.get("admin1", "")).strip()
    country = str(first.get("country_code", "")).strip()
    return ", ".join([part for part in [city, admin, country] if part]).strip()


def _first_http_url(*candidates: str) -> str:
    for candidate in candidates:
        value = str(candidate or "").strip()
        if not value:
            continue
        if value.startswith("//"):
            value = f"https:{value}"
        if value.startswith("http://") or value.startswith("https://"):
            return value
    return ""


def _extract_img_url_from_html(raw_html: str) -> str:
    html = unescape(str(raw_html or "")).strip()
    if not html:
        return ""

    # Try common attributes first.
    patterns = (
        r'<img[^>]+src=["\']([^"\']+)["\']',
        r'<img[^>]+data-src=["\']([^"\']+)["\']',
        r'<img[^>]+srcset=["\']([^"\']+)["\']',
        r'url=["\'](https?://[^"\']+)["\']',
    )
    for pattern in patterns:
        match = re.search(pattern, html, flags=re.IGNORECASE)
        if not match:
            continue
        candidate = match.group(1)
        if " " in candidate and "," in candidate:
            # srcset can contain multiple image candidates.
            candidate = candidate.split(",")[0].strip().split(" ")[0].strip()
        normalized = _first_http_url(candidate)
        if normalized:
            return normalized
    return ""


def _extract_image_url(entry) -> str:
    image_obj = getattr(entry, "image", None)
    if isinstance(image_obj, dict):
        url = _first_http_url(image_obj.get("href"), image_obj.get("url"))
        if url:
            return url

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

    enclosures = getattr(entry, "enclosures", None) or []
    for enclosure in enclosures:
        if isinstance(enclosure, dict):
            href = _first_http_url(enclosure.get("href"), enclosure.get("url"))
            media_type = str(enclosure.get("type", "")).lower()
            if href and ("image" in media_type or not media_type):
                return href

    content_blocks = getattr(entry, "content", None) or []
    for block in content_blocks:
        if isinstance(block, dict):
            html = block.get("value") or ""
            extracted = _extract_img_url_from_html(str(html))
            if extracted:
                return extracted

    summary = str(getattr(entry, "summary", "")).strip()
    extracted = _extract_img_url_from_html(summary)
    if extracted:
        return extracted

    summary_detail = getattr(entry, "summary_detail", None)
    if isinstance(summary_detail, dict):
        extracted = _extract_img_url_from_html(str(summary_detail.get("value", "")))
        if extracted:
            return extracted

    description = str(getattr(entry, "description", "")).strip()
    extracted = _extract_img_url_from_html(description)
    if extracted:
        return extracted

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


def _is_likely_paywalled(source_name: str, title: str, summary: str) -> bool:
    haystacks = [source_name.lower(), title.lower(), summary.lower()]
    if any(any(marker in text for marker in LIKELY_PAYWALLED_SOURCES) for text in haystacks):
        return True

    # Lightweight keyword heuristic for premium prompts in feed snippets.
    paywall_markers = (
        "subscriber",
        "subscription",
        "subscribe to continue",
        "for subscribers",
        "members only",
        "gift article",
    )
    return any(any(marker in text for marker in paywall_markers) for text in haystacks)


def fetch_local_news(zip_code: str, limit: int = 10) -> dict:
    normalized_zip = _normalize_zip(zip_code)
    location_label = _fast_geocode_location_label(normalized_zip)
    geocode_message = None
    if not location_label:
        location_label = f"ZIP {normalized_zip}"
        geocode_message = "Location lookup fallback active."

    cached_payload = _load_cached_local_news(normalized_zip, LOCAL_NEWS_CACHE_TTL_SECONDS)

    items = []
    seen = set()
    now_utc = datetime.now(timezone.utc)
    recent_cutoff = now_utc - timedelta(days=3)
    max_items = max(1, min(limit, 25))
    source_cap = _per_source_cap(max_items)
    query_used = ""
    stale_pool: list[tuple[datetime | None, dict]] = []
    fresh_pool: list[tuple[datetime | None, dict]] = []
    source_counts: dict[str, int] = {}
    for query in _query_candidates(location_label, normalized_zip)[:2]:
        entries = _fetch_entries_for_query(query)
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
            source_key = _source_key(source)
            if source_counts.get(source_key, 0) >= source_cap:
                continue
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
                "is_paywalled": _is_likely_paywalled(source, title, summary),
            }
            if published_dt is not None and published_dt >= recent_cutoff:
                fresh_pool.append((published_dt, item))
            else:
                stale_pool.append((published_dt, item))
            source_counts[source_key] = source_counts.get(source_key, 0) + 1
            if len(fresh_pool) >= max_items:
                break
        if len(fresh_pool) >= max_items:
            break

    fresh_pool.sort(key=lambda entry: entry[0] or datetime.min.replace(tzinfo=timezone.utc), reverse=True)
    stale_pool.sort(key=lambda entry: entry[0] or datetime.min.replace(tzinfo=timezone.utc), reverse=True)
    items = [item for _, item in fresh_pool[:max_items]]
    if len(items) < max_items and stale_pool:
        needed = max_items - len(items)
        items.extend(item for _, item in stale_pool[:needed])

    response = {
        "success": True,
        "message": geocode_message,
        "zip_code": normalized_zip,
        "location_label": location_label,
        "query": query_used or _extract_query_terms(location_label),
        "items": items,
    }
    if items:
        _save_cached_local_news(normalized_zip, response)
        return response

    if cached_payload:
        cached_payload["success"] = True
        cached_payload["message"] = "Showing recent cached local headlines while live feed catches up."
        return cached_payload

    response["message"] = response.get("message") or "Local news unavailable right now. Please retry shortly."
    return response
