from __future__ import annotations

import json
import os
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from app.models import WatchShow


FALLBACK_WATCH_SHOWS: list[WatchShow] = [
    WatchShow(
        show_id="severance-s2",
        title="Severance",
        poster_url="https://image.tmdb.org/t/p/w500/lx5L2B6o6qQ2XWJ6n4vRAsNQ2bT.jpg",
        synopsis="Employees at Lumon Industries discover the cost of splitting work memories from personal lives.",
        providers=["Apple TV+"],
        release_date="2026-02-21",
        season_episode_status="Season 2 now streaming",
        trend_score=94.0,
    ),
    WatchShow(
        show_id="the-bear-s4",
        title="The Bear",
        poster_url="https://image.tmdb.org/t/p/w500/1UF8dCgJm1w6Q6NwCG8X1kQbWkM.jpg",
        synopsis="Carmy and team push to keep their Chicago restaurant alive under pressure.",
        providers=["Hulu"],
        release_date="2026-02-28",
        season_episode_status="Season 4 weekly episodes",
        trend_score=90.0,
    ),
    WatchShow(
        show_id="house-of-the-dragon-s3",
        title="House of the Dragon",
        poster_url="https://image.tmdb.org/t/p/w500/z2yahl2uefxDCl0nogcRBstwruJ.jpg",
        synopsis="The Targaryen civil war escalates with shifting alliances and dragon battles.",
        providers=["Max"],
        release_date="2026-03-12",
        season_episode_status="Season 3 premieres soon",
        trend_score=88.0,
    ),
    WatchShow(
        show_id="reacher-s4",
        title="Reacher",
        poster_url="https://image.tmdb.org/t/p/w500/2V9f4N4fP8f1Bz3QG0u6R45Y1zQ.jpg",
        synopsis="Jack Reacher tackles a conspiracy tied to military secrets and corrupt contractors.",
        providers=["Prime Video"],
        release_date="2026-03-05",
        season_episode_status="New season this week",
        trend_score=86.0,
    ),
]

CACHE_TTL_SECONDS = 15 * 60
_watch_cache: dict[str, object] = {
    "expires_at": datetime.fromtimestamp(0, tz=timezone.utc),
    "source": "fallback_static",
    "items": [],
}


_PROVIDER_CANONICAL_MAP: dict[str, str] = {
    "netflix": "Netflix",
    "hulu": "Hulu",
    "disney+": "Disney+",
    "disney plus": "Disney+",
    "max": "Max",
    "hbo max": "Max",
    "prime video": "Prime Video",
    "amazon prime video": "Prime Video",
    "amazon prime": "Prime Video",
    "apple tv+": "Apple TV+",
    "apple tv plus": "Apple TV+",
    "paramount+": "Paramount+",
    "paramount plus": "Paramount+",
    "peacock": "Peacock",
    "youtube tv": "YouTube TV",
    "crunchyroll": "Crunchyroll",
    "showtime": "Showtime",
}


def _parse_release_date(raw: str) -> date | None:
    try:
        return datetime.strptime(raw, "%Y-%m-%d").date()
    except ValueError:
        return None


def _http_get_json(url: str, timeout_seconds: float, headers: dict[str, str] | None = None) -> object:
    request = Request(url, headers=headers or {})
    with urlopen(request, timeout=timeout_seconds) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw)


def _status_for_release_date(release_date: str) -> str:
    release = _parse_release_date(release_date)
    if release is None:
        return "Release date TBA"
    today = datetime.now(timezone.utc).date()
    diff_days = (release - today).days
    if diff_days <= 0:
        return "Now streaming"
    if diff_days <= 7:
        return "New this week"
    return "Coming soon"


def release_badge_for_date(release_date: str) -> str:
    release = _parse_release_date(release_date)
    if release is None:
        return "none"
    today = datetime.now(timezone.utc).date()
    diff_days = (release - today).days
    if diff_days < -14:
        return "none"
    if diff_days <= 0:
        return "new"
    if diff_days <= 7:
        return "this_week"
    return "upcoming"


def release_badge_label(badge: str) -> str:
    if badge == "new":
        return "New"
    if badge == "this_week":
        return "This Week"
    if badge == "upcoming":
        return "Upcoming"
    return ""


def normalize_provider_name(raw: str) -> str:
    key = raw.strip().lower()
    if not key:
        return ""
    return _PROVIDER_CANONICAL_MAP.get(key, raw.strip())


def normalize_provider_list(providers: list[str]) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()
    for provider in providers:
        name = normalize_provider_name(provider)
        if not name:
            continue
        dedupe_key = name.lower()
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        normalized.append(name)
    if normalized:
        return normalized[:4]
    return ["Streaming providers vary"]


def _tmdb_provider_names(tv_id: int, api_key: str, region: str, timeout_seconds: float) -> list[str]:
    try:
        query = urlencode({"api_key": api_key})
        url = f"https://api.themoviedb.org/3/tv/{tv_id}/watch/providers?{query}"
        data = _http_get_json(url, timeout_seconds=timeout_seconds)
        region_payload = (data.get("results") or {}).get(region.upper()) or {}
        providers = region_payload.get("flatrate") or []
        names = [str(item.get("provider_name", "")).strip() for item in providers if item.get("provider_name")]
        return normalize_provider_list(names)
    except Exception:
        return []


def _ingest_tmdb_trending(limit: int, timeout_seconds: float) -> list[WatchShow]:
    api_key = os.getenv("TMDB_API_KEY", "").strip()
    if not api_key:
        return []
    region = os.getenv("TMDB_REGION", "US").strip() or "US"
    query = urlencode({"api_key": api_key})
    url = f"https://api.themoviedb.org/3/trending/tv/week?{query}"
    data = _http_get_json(url, timeout_seconds=timeout_seconds)
    if not isinstance(data, dict):
        return []
    results = data.get("results") or []
    if not isinstance(results, list):
        return []
    shows: list[WatchShow] = []
    for idx, item in enumerate(results[: max(1, min(limit, 20))]):
        tv_id = item.get("id")
        name = str(item.get("name", "")).strip()
        if not tv_id or not name:
            continue
        first_air_date = str(item.get("first_air_date", "")).strip()
        poster_path = str(item.get("poster_path", "")).strip()
        providers = _tmdb_provider_names(int(tv_id), api_key, region, timeout_seconds=timeout_seconds)
        providers = normalize_provider_list(providers)
        shows.append(
            WatchShow(
                show_id=f"tmdb-{tv_id}",
                title=name,
                poster_url=f"https://image.tmdb.org/t/p/w500{poster_path}" if poster_path else "",
                synopsis=str(item.get("overview", "")).strip() or "No synopsis yet.",
                providers=providers,
                release_date=first_air_date,
                season_episode_status=_status_for_release_date(first_air_date),
                trend_score=max(0.0, 100.0 - float(idx * 2)),
            )
        )
    return shows


def _ingest_tvmaze_schedule(limit: int, timeout_seconds: float) -> list[WatchShow]:
    today = datetime.now(timezone.utc).date().isoformat()
    query = urlencode({"country": "US", "date": today})
    url = f"https://api.tvmaze.com/schedule/web?{query}"
    data = _http_get_json(
        url,
        timeout_seconds=timeout_seconds,
        headers={"User-Agent": "BigDavesNews/1.0"},
    )
    if not isinstance(data, list):
        return []
    by_show_id: dict[int, WatchShow] = {}
    for idx, item in enumerate(data):
        show = item.get("show") or {}
        show_id = show.get("id")
        title = str(show.get("name", "")).strip()
        if not show_id or not title:
            continue
        if int(show_id) in by_show_id:
            continue
        web_channel = (show.get("webChannel") or {}).get("name")
        network = (show.get("network") or {}).get("name")
        provider = str(web_channel or network or "Streaming providers vary").strip()
        image = show.get("image") or {}
        summary = str(show.get("summary", "")).replace("<p>", "").replace("</p>", "").strip()
        release_date = str(show.get("premiered", "")).strip()
        by_show_id[int(show_id)] = WatchShow(
            show_id=f"tvmaze-{show_id}",
            title=title,
            poster_url=str(image.get("original") or image.get("medium") or "").strip(),
            synopsis=summary or "No synopsis yet.",
            providers=normalize_provider_list([provider]),
            release_date=release_date,
            season_episode_status="Trending now",
            trend_score=max(0.0, 85.0 - float(idx)),
        )
        if len(by_show_id) >= max(1, min(limit, 20)):
            break
    return list(by_show_id.values())


def list_watch_shows(limit: int = 20) -> tuple[list[WatchShow], str]:
    safe_limit = max(1, min(limit, 50))
    today = datetime.now(timezone.utc).date()
    now = datetime.now(timezone.utc)
    expires_at = _watch_cache.get("expires_at")
    if isinstance(expires_at, datetime) and expires_at > now:
        cached = _watch_cache.get("items")
        source = str(_watch_cache.get("source") or "fallback_static")
        if isinstance(cached, list):
            ranked = sorted(cached, key=lambda show: _sort_key(show, today), reverse=True)
            return ranked[:safe_limit], source

    timeout_raw = os.getenv("WATCH_HTTP_TIMEOUT_SECONDS", "4.0").strip() or "4.0"
    try:
        timeout_seconds = max(1.0, min(float(timeout_raw), 12.0))
    except ValueError:
        timeout_seconds = 4.0
    source = "fallback_static"
    try:
        live_shows = _ingest_tmdb_trending(safe_limit, timeout_seconds=timeout_seconds)
    except Exception:
        live_shows = []
    if live_shows:
        source = "tmdb_trending"
    else:
        try:
            live_shows = _ingest_tvmaze_schedule(safe_limit, timeout_seconds=timeout_seconds)
        except Exception:
            live_shows = []
        if live_shows:
            source = "tvmaze_schedule_web"
    if not live_shows:
        live_shows = FALLBACK_WATCH_SHOWS

    for show in live_shows:
        show.providers = normalize_provider_list(show.providers)

    _watch_cache["source"] = source
    _watch_cache["items"] = live_shows
    _watch_cache["expires_at"] = now + timedelta(seconds=max(60, CACHE_TTL_SECONDS))
    ranked = sorted(live_shows, key=lambda show: _sort_key(show, today), reverse=True)
    return ranked[:safe_limit], source


def _sort_key(show: WatchShow, today: date) -> tuple[float, int]:
    release = _parse_release_date(show.release_date)
    # Reward newer releases slightly without overpowering trend score.
    freshness_boost = 0
    if release is not None:
        days = abs((today - release).days)
        freshness_boost = max(0, 30 - days)
    return (show.trend_score, freshness_boost)
