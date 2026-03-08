from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from json import loads
from urllib.error import URLError
from urllib.parse import quote_plus
from urllib.request import Request, urlopen

import feedparser

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

    items = []
    seen = set()
    now_utc = datetime.now(timezone.utc)
    recent_cutoff = now_utc - timedelta(days=3)
    max_items = max(1, min(limit, 25))
    query_used = ""
    stale_pool: list[tuple[datetime | None, dict]] = []
    fresh_pool: list[tuple[datetime | None, dict]] = []
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

    return {
        "success": True,
        "message": geocode_message,
        "zip_code": normalized_zip,
        "location_label": location_label,
        "query": query_used or _extract_query_terms(location_label),
        "items": items,
    }
