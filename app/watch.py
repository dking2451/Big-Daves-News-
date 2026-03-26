from __future__ import annotations

import json
import logging
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from app.models import WatchShow
from app.watch_catalog import merge_catalog_into_show, persist_watch_catalog_row
from app.watch_poster_resolution import (
    apply_resolution_to_show,
    catalog_refresh_is_stale,
    resolve_watch_poster,
    tmdb_tv_id_for_show,
)

logger = logging.getLogger(__name__)

FALLBACK_WATCH_SHOWS: list[WatchShow] = [
    WatchShow(
        show_id="severance-s2",
        title="Severance",
        poster_url="https://image.tmdb.org/t/p/w500/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg",
        synopsis="Employees at Lumon Industries discover the cost of splitting work memories from personal lives.",
        providers=["Apple TV+"],
        genres=["Sci-Fi", "Drama"],
        release_date="2026-02-21",
        season_episode_status="Season 2 now streaming",
        trend_score=94.0,
        tmdb_tv_id=95396,
    ),
    WatchShow(
        show_id="the-bear-s4",
        title="The Bear",
        poster_url="https://image.tmdb.org/t/p/w500/1UF8dCgJm1w6Q6NwCG8X1kQbWkM.jpg",
        synopsis="Carmy and team push to keep their Chicago restaurant alive under pressure.",
        providers=["Hulu"],
        genres=["Drama", "Comedy"],
        release_date="2026-02-28",
        season_episode_status="Season 4 weekly episodes",
        trend_score=90.0,
        tmdb_tv_id=136315,
    ),
    WatchShow(
        show_id="house-of-the-dragon-s3",
        title="House of the Dragon",
        poster_url="https://image.tmdb.org/t/p/w500/z2yahl2uefxDCl0nogcRBstwruJ.jpg",
        synopsis="The Targaryen civil war escalates with shifting alliances and dragon battles.",
        providers=["HBO Max"],
        genres=["Drama", "Action"],
        release_date="2026-03-12",
        season_episode_status="Season 3 premieres soon",
        trend_score=88.0,
        tmdb_tv_id=94997,
    ),
    WatchShow(
        show_id="reacher-s4",
        title="Reacher",
        poster_url="https://image.tmdb.org/t/p/w500/2V9f4N4fP8f1Bz3QG0u6R45Y1zQ.jpg",
        synopsis="Jack Reacher tackles a conspiracy tied to military secrets and corrupt contractors.",
        providers=["Prime Video"],
        genres=["Action", "Crime"],
        release_date="2026-03-05",
        season_episode_status="New season this week",
        trend_score=86.0,
        tmdb_tv_id=108978,
    ),
    WatchShow(
        show_id="the-last-of-us-s3",
        title="The Last of Us",
        poster_url="https://image.tmdb.org/t/p/w500/uKvVjHNqB5VmOrdxqAt2F7J78ED.jpg",
        synopsis="Joel and Ellie navigate a brutal world where every new alliance has a cost.",
        providers=["HBO Max"],
        genres=["Drama", "Sci-Fi"],
        release_date="2026-03-22",
        season_episode_status="Upcoming season",
        trend_score=84.0,
        tmdb_tv_id=100088,
    ),
    WatchShow(
        show_id="only-murders-s5",
        title="Only Murders in the Building",
        poster_url="https://image.tmdb.org/t/p/w500/pnq5LSrVjY2x2fL7M6VgH5j8VYk.jpg",
        synopsis="The Arconia trio tackles another mystery with sharp wit and surprise suspects.",
        providers=["Hulu"],
        genres=["Comedy", "Crime"],
        release_date="2026-03-18",
        season_episode_status="New season soon",
        trend_score=82.0,
        tmdb_tv_id=107113,
    ),
    WatchShow(
        show_id="invincible-s4",
        title="Invincible",
        poster_url="https://image.tmdb.org/t/p/w500/yDWJYRAwMNKbIYT8ZB33qy84uzO.jpg",
        synopsis="Mark Grayson faces cosmic threats while balancing life, duty, and family.",
        providers=["Prime Video"],
        genres=["Animation", "Action"],
        release_date="2026-03-10",
        season_episode_status="New episodes weekly",
        trend_score=81.0,
        tmdb_tv_id=95557,
    ),
    WatchShow(
        show_id="silo-s3",
        title="Silo",
        poster_url="https://image.tmdb.org/t/p/w500/7QMsOTMUswlwxJP0rTTZfmz2tX2.jpg",
        synopsis="Juliette uncovers deeper secrets beneath the surface of the silo.",
        providers=["Apple TV+"],
        genres=["Sci-Fi", "Drama"],
        release_date="2026-04-02",
        season_episode_status="Coming soon",
        trend_score=80.0,
        tmdb_tv_id=125988,
    ),
    WatchShow(
        show_id="the-gentlemen-s2",
        title="The Gentlemen",
        poster_url="https://image.tmdb.org/t/p/w500/tw3tzfXaSpmUZIB8ZNqNEGzMBCy.jpg",
        synopsis="A reluctant heir gets pulled deeper into a high-stakes criminal empire.",
        providers=["Netflix"],
        genres=["Crime", "Comedy"],
        release_date="2026-03-15",
        season_episode_status="New season this month",
        trend_score=79.0,
        tmdb_tv_id=236235,
    ),
    WatchShow(
        show_id="slow-horses-s6",
        title="Slow Horses",
        poster_url="https://image.tmdb.org/t/p/w500/dnpatlJrEPiDSn5fzgzvxtiSnMo.jpg",
        synopsis="Jackson Lamb and his team of outcasts stumble into another deadly operation.",
        providers=["Apple TV+"],
        genres=["Drama", "Crime"],
        release_date="2026-03-27",
        season_episode_status="Upcoming",
        trend_score=78.0,
        tmdb_tv_id=95480,
    ),
    WatchShow(
        show_id="welcome-to-wrexham-s5",
        title="Welcome to Wrexham",
        poster_url="https://image.tmdb.org/t/p/w500/53CNogAzbbwepLxQS5jIfGG35MQ.jpg",
        synopsis="The club chases another promotion as expectations rise on and off the pitch.",
        providers=["Hulu"],
        genres=["Documentary", "Reality"],
        release_date="2026-03-08",
        season_episode_status="Now streaming",
        trend_score=76.0,
        tmdb_tv_id=126929,
    ),
    WatchShow(
        show_id="andor-s3",
        title="Andor",
        poster_url="https://image.tmdb.org/t/p/w500/59SVNwLfoMnZPPB6ukW6dlPxAdI.jpg",
        synopsis="The rebellion grows as Cassian takes on higher-risk missions across the galaxy.",
        providers=["Disney+"],
        genres=["Sci-Fi", "Action"],
        release_date="2026-04-10",
        season_episode_status="Upcoming release",
        trend_score=77.0,
        tmdb_tv_id=83867,
    ),
    WatchShow(
        show_id="stranger-things-s5",
        title="Stranger Things",
        poster_url="https://image.tmdb.org/t/p/w500/49WJfeN0moxb9IPfGn8AIqMGskD.jpg",
        synopsis="Hawkins faces its biggest threat yet as the final chapter unfolds.",
        providers=["Netflix"],
        genres=["Sci-Fi", "Drama"],
        release_date="2026-04-18",
        season_episode_status="Final season upcoming",
        trend_score=75.0,
        tmdb_tv_id=66732,
    ),
    WatchShow(
        show_id="the-traitors-us-s4",
        title="The Traitors",
        poster_url="https://image.tmdb.org/t/p/w500/xWK9tLH2UGgzuAI6P3cHeTKopfj.jpg",
        synopsis="Alliances shift fast in a high-stakes game of deception and strategy.",
        providers=["Peacock"],
        genres=["Reality"],
        release_date="2026-03-20",
        season_episode_status="New season this month",
        trend_score=74.0,
        tmdb_tv_id=215943,
    ),
    WatchShow(
        show_id="yellowjackets-s4",
        title="Yellowjackets",
        poster_url="https://image.tmdb.org/t/p/w500/xRnGrn7Z7SC0KIBodocoU1QgDZF.jpg",
        synopsis="Past and present collide as the survivors confront buried secrets.",
        providers=["Paramount+"],
        genres=["Drama", "Mystery"],
        release_date="2026-03-30",
        season_episode_status="Upcoming",
        trend_score=73.0,
        tmdb_tv_id=117488,
    ),
    WatchShow(
        show_id="landman-s2",
        title="Landman",
        poster_url="https://image.tmdb.org/t/p/w500/hYthRgS1nvQkGILn9YmqsF8kSk6.jpg",
        synopsis="Power and risk collide in the Texas oil boom.",
        providers=["Paramount+"],
        genres=["Drama"],
        release_date="2026-04-04",
        season_episode_status="Coming soon",
        trend_score=72.0,
        tmdb_tv_id=157741,
    ),
    WatchShow(
        show_id="marshall-s1",
        title="Marshals",
        poster_url="https://image.tmdb.org/t/p/w500/8QVDXDiOGHRcAD4oM6MXjE0osSj.jpg",
        synopsis="A U.S. Marshal balances dangerous field work with a shifting political landscape.",
        providers=["Paramount+"],
        genres=["Drama", "Crime"],
        release_date="2026-03-07",
        season_episode_status="Weekly episodes",
        trend_score=71.0,
        tmdb_tv_id=290856,
    ),
    WatchShow(
        show_id="hijack-s2",
        title="Hijack",
        poster_url="https://image.tmdb.org/t/p/w500/68OrQ4L4g6l6XjX6V2O7s9k6tS2.jpg",
        synopsis="Sam Nelson is pulled into another high-stakes in-flight crisis.",
        providers=["Apple TV+"],
        genres=["Drama", "Action"],
        release_date="2026-03-09",
        season_episode_status="New season weekly",
        trend_score=70.0,
        tmdb_tv_id=198102,
    ),
    WatchShow(
        show_id="the-night-agent-s3",
        title="The Night Agent",
        poster_url="https://image.tmdb.org/t/p/w500/4c5yUNcaff4W4aPrkXE6zr7papX.jpg",
        synopsis="A low-level FBI agent is thrust into a deep conspiracy threatening national security.",
        providers=["Netflix"],
        genres=["Action", "Drama"],
        release_date="2026-03-14",
        season_episode_status="New season this month",
        trend_score=69.0,
        tmdb_tv_id=129552,
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
    "max": "HBO Max",
    "hbo": "HBO Max",
    "hbo max": "HBO Max",
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

_TMDB_GENRE_MAP: dict[int, str] = {
    10759: "Action",
    16: "Animation",
    35: "Comedy",
    80: "Crime",
    99: "Documentary",
    18: "Drama",
    10751: "Family",
    10762: "Kids",
    9648: "Mystery",
    10763: "News",
    10764: "Reality",
    10765: "Sci-Fi",
    10766: "Soap",
    10767: "Talk",
    10768: "War",
    37: "Western",
}

_GENRE_CANONICAL_MAP: dict[str, str] = {
    "science fiction": "Sci-Fi",
    "sci-fi": "Sci-Fi",
    "scifi": "Sci-Fi",
    "sci fi": "Sci-Fi",
    "action & adventure": "Action",
    "action-adventure": "Action",
    "kids": "Kids",
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


def _needs_tmdb_resolution_pass(show: WatchShow) -> bool:
    """
    Run TMDB resolver when we lack a trusted TMDB poster + stable id, or catalog metadata is stale.
    TVmaze ingest rows ship non-TMDB image URLs — we must search TMDB for canonical art + id.
    """
    url = str(show.poster_url or "").strip()
    if not url:
        return True
    if (show.show_id or "").startswith("tvmaze-"):
        return True
    if "placehold.co" in url.lower():
        return True
    if not url.startswith("https://image.tmdb.org/"):
        return True
    tid = tmdb_tv_id_for_show(show)
    if tid is None:
        return True
    last_ref = str(getattr(show, "tmdb_last_refreshed_at", "") or "").strip()
    if last_ref and not catalog_refresh_is_stale(last_ref):
        return False
    if not last_ref:
        return False
    return True


def _tag_poster_trust_for_cached_row(show: WatchShow) -> None:
    """Infer trust when we skip resolution (e.g. trending rows already from TMDB)."""
    url = str(show.poster_url or "").strip().lower()
    if not url:
        show.poster_trusted = False
        show.poster_resolution_path = show.poster_resolution_path or "missing"
        show.poster_status = show.poster_status or "missing"
        return
    if "placehold.co" in url:
        show.poster_trusted = False
        show.poster_resolution_path = show.poster_resolution_path or "placeholder"
        show.poster_status = show.poster_status or "missing"
        return
    if url.startswith("https://image.tmdb.org/"):
        show.poster_trusted = True
        show.poster_resolution_path = show.poster_resolution_path or "tmdb_inline"
        show.poster_status = show.poster_status or "trusted"
        return
    # Non-TMDB art (e.g. legacy TVmaze) — premium placeholder on client; do not load as trusted.
    show.poster_trusted = False
    show.poster_resolution_path = show.poster_resolution_path or "non_tmdb_art"
    show.poster_status = show.poster_status or "unverified_remote"


def _enrich_missing_posters(
    shows: list[WatchShow],
    timeout_seconds: float,
    force_lookup_existing: bool = False,
) -> list[WatchShow]:
    """TMDB-only, trust-first posters; placeholders beat wrong matches (see watch_poster_resolution)."""
    api_key = os.getenv("TMDB_API_KEY", "").strip()
    for show in shows:
        merge_catalog_into_show(show)
        existing = str(show.poster_url or "").strip()
        show.poster_source = "original"

        if force_lookup_existing:
            if not _needs_tmdb_resolution_pass(show):
                _tag_poster_trust_for_cached_row(show)
                persist_watch_catalog_row(show, outcome=None)
                continue
            outcome = resolve_watch_poster(
                show,
                api_key=api_key,
                timeout_seconds=timeout_seconds,
            )
            apply_resolution_to_show(
                show,
                outcome,
                poster_source_tag=outcome.resolution_path,
            )
            persist_watch_catalog_row(show, outcome=outcome)
            continue

        if existing and not _needs_tmdb_resolution_pass(show):
            _tag_poster_trust_for_cached_row(show)
            continue

        outcome = resolve_watch_poster(
            show,
            api_key=api_key,
            timeout_seconds=timeout_seconds,
        )
        apply_resolution_to_show(
            show,
            outcome,
            poster_source_tag=outcome.resolution_path,
        )
        persist_watch_catalog_row(show, outcome=outcome)
    return shows


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


def release_badge_from_episode_dates(
    last_air: str,
    next_air: str,
    fallback_release: str,
) -> str:
    """Badge from TMDB/TVmaze last/next episode air dates; falls back to series premiere logic."""
    today = datetime.now(timezone.utc).date()
    l = _parse_release_date((last_air or "").strip())
    n = _parse_release_date((next_air or "").strip())
    if n is not None and n >= today:
        days_until = (n - today).days
        if days_until <= 7:
            return "this_week"
        return "upcoming"
    if l is not None and l <= today:
        if (today - l).days <= 14:
            return "new"
    return release_badge_for_date((fallback_release or "").strip())


def watch_release_badge(show: WatchShow) -> str:
    last = (show.last_episode_air_date or "").strip()
    next_a = (show.next_episode_air_date or "").strip()
    if last or next_a:
        return release_badge_from_episode_dates(last, next_a, show.release_date)
    return release_badge_for_date(show.release_date)


def effective_last_air_for_compare(show: WatchShow) -> str:
    return (show.last_episode_air_date or show.release_date or "").strip()


def effective_next_air_for_schedule(show: WatchShow) -> str:
    return (show.next_episode_air_date or show.release_date or "").strip()


def release_badge_label(badge: str) -> str:
    if badge == "new":
        return "Recently aired"
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


def normalize_genre_name(raw: str) -> str:
    key = raw.strip().lower()
    if not key:
        return ""
    if key in _GENRE_CANONICAL_MAP:
        return _GENRE_CANONICAL_MAP[key]
    return raw.strip().title()


def normalize_genre_list(genres: list[str]) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()
    for genre in genres:
        item = normalize_genre_name(genre)
        if not item:
            continue
        dedupe_key = item.lower()
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        normalized.append(item)
    return normalized[:4]


def _normalized_title_key(title: str) -> str:
    return "".join(ch for ch in title.lower() if ch.isalnum())


def _dedupe_watch_shows(shows: list[WatchShow]) -> list[WatchShow]:
    best_by_title: dict[str, WatchShow] = {}
    for show in shows:
        key = _normalized_title_key(show.title)
        if not key:
            continue
        existing = best_by_title.get(key)
        if existing is None or float(show.trend_score) > float(existing.trend_score):
            best_by_title[key] = show
    return list(best_by_title.values())


def _diversify_provider_mix(shows: list[WatchShow], per_provider_cap: int = 4) -> list[WatchShow]:
    if not shows:
        return []
    cap = max(1, per_provider_cap)
    selected: list[WatchShow] = []
    overflow: list[WatchShow] = []
    provider_counts: dict[str, int] = {}
    for show in shows:
        primary = normalize_provider_name(show.providers[0]) if show.providers else "Streaming providers vary"
        key = primary.lower()
        current_count = provider_counts.get(key, 0)
        if current_count < cap:
            selected.append(show)
            provider_counts[key] = current_count + 1
        else:
            overflow.append(show)
    return selected + overflow


def _fill_with_fallback_shows(shows: list[WatchShow], target_count: int) -> list[WatchShow]:
    desired = max(1, target_count)
    if len(shows) >= desired:
        return shows
    by_title = {_normalized_title_key(show.title) for show in shows if show.title}
    by_id = {show.show_id for show in shows if show.show_id}
    filled = list(shows)
    for fallback in FALLBACK_WATCH_SHOWS:
        if len(filled) >= desired:
            break
        title_key = _normalized_title_key(fallback.title)
        if fallback.show_id in by_id or (title_key and title_key in by_title):
            continue
        filled.append(fallback)
        by_id.add(fallback.show_id)
        if title_key:
            by_title.add(title_key)
    return filled


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


def _tmdb_tv_episode_dates(tv_id: int, api_key: str, timeout_seconds: float) -> tuple[str, str]:
    query = urlencode({"api_key": api_key})
    url = f"https://api.themoviedb.org/3/tv/{tv_id}?{query}"
    try:
        data = _http_get_json(url, timeout_seconds=timeout_seconds)
    except Exception:
        return "", ""
    if not isinstance(data, dict):
        return "", ""
    last_ep = data.get("last_episode_to_air") or {}
    next_ep = data.get("next_episode_to_air") or {}
    last_a = ""
    next_a = ""
    if isinstance(last_ep, dict):
        last_a = str(last_ep.get("air_date") or "").strip()
    if isinstance(next_ep, dict):
        next_a = str(next_ep.get("air_date") or "").strip()
    return last_a, next_a


def _tvmaze_tv_episode_dates(show_id: int, timeout_seconds: float) -> tuple[str, str]:
    url = f"https://api.tvmaze.com/shows/{show_id}?embed[]=nextepisode&embed[]=previousepisode"
    try:
        data = _http_get_json(
            url,
            timeout_seconds=timeout_seconds,
            headers={"User-Agent": "BigDavesNews/1.0"},
        )
    except Exception:
        return "", ""
    if not isinstance(data, dict):
        return "", ""
    embedded = data.get("_embedded") if isinstance(data.get("_embedded"), dict) else {}
    prev_ep = embedded.get("previousepisode") or data.get("previousepisode")
    next_ep = embedded.get("nextepisode") or data.get("nextepisode")
    last_a = ""
    next_a = ""
    if isinstance(prev_ep, dict):
        last_a = str(prev_ep.get("airdate") or "").strip()
    if isinstance(next_ep, dict):
        next_a = str(next_ep.get("airdate") or "").strip()
    return last_a, next_a


def _preferred_status_date(show: WatchShow) -> str:
    today = datetime.now(timezone.utc).date()
    n = _parse_release_date((show.next_episode_air_date or "").strip())
    if n and n > today:
        return show.next_episode_air_date
    if (show.last_episode_air_date or "").strip():
        return show.last_episode_air_date
    return show.release_date


def _enrich_single_show_episode_dates(show: WatchShow, *, tmdb_api_key: str, timeout_seconds: float) -> None:
    try:
        sid = (show.show_id or "").strip()
        if sid.startswith("tmdb-"):
            if not tmdb_api_key:
                return
            try:
                tv_id = int(sid.split("-", 1)[1])
            except (ValueError, IndexError):
                return
            last_a, next_a = _tmdb_tv_episode_dates(tv_id, tmdb_api_key, timeout_seconds=timeout_seconds)
            show.last_episode_air_date = last_a or ""
            show.next_episode_air_date = next_a or ""
        elif sid.startswith("tvmaze-"):
            try:
                mid = int(sid.split("-", 1)[1])
            except (ValueError, IndexError):
                return
            last_a, next_a = _tvmaze_tv_episode_dates(mid, timeout_seconds=timeout_seconds)
            show.last_episode_air_date = last_a or ""
            show.next_episode_air_date = next_a or ""
        if show.last_episode_air_date or show.next_episode_air_date:
            show.season_episode_status = _status_for_release_date(_preferred_status_date(show))
    except Exception:
        return


def _enrich_episode_air_dates(shows: list[WatchShow], *, timeout_seconds: float) -> None:
    if not shows:
        return
    api_key = os.getenv("TMDB_API_KEY", "").strip()
    workers = min(8, max(1, len(shows)))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [
            pool.submit(_enrich_single_show_episode_dates, show, tmdb_api_key=api_key, timeout_seconds=timeout_seconds)
            for show in shows
        ]
        for fut in futures:
            try:
                fut.result()
            except Exception:
                continue


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
    for idx, item in enumerate(results[: max(1, min(limit, 40))]):
        tv_id = item.get("id")
        name = str(item.get("name", "")).strip()
        if not tv_id or not name:
            continue
        first_air_date = str(item.get("first_air_date", "")).strip()
        poster_path = str(item.get("poster_path", "")).strip()
        providers = _tmdb_provider_names(int(tv_id), api_key, region, timeout_seconds=timeout_seconds)
        providers = normalize_provider_list(providers)
        genre_ids = item.get("genre_ids") or []
        genres: list[str] = []
        if isinstance(genre_ids, list):
            for genre_id in genre_ids:
                try:
                    int_id = int(genre_id)
                except (TypeError, ValueError):
                    continue
                mapped = _TMDB_GENRE_MAP.get(int_id)
                if mapped:
                    genres.append(mapped)
        genres = normalize_genre_list(genres)
        shows.append(
            WatchShow(
                show_id=f"tmdb-{tv_id}",
                title=name,
                poster_url=f"https://image.tmdb.org/t/p/w500{poster_path}" if poster_path else "",
                synopsis=str(item.get("overview", "")).strip() or "No synopsis yet.",
                providers=providers,
                genres=genres,
                release_date=first_air_date,
                season_episode_status=_status_for_release_date(first_air_date),
                trend_score=max(0.0, 100.0 - float(idx * 2)),
                tmdb_tv_id=int(tv_id),
            )
        )
        logger.info(
            "watch_ingest trending stored tmdb_tv_id show_id=tmdb-%s tmdb_tv_id=%s title=%r",
            tv_id,
            int(tv_id),
            name[:80],
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
        genres_raw = show.get("genres") if isinstance(show.get("genres"), list) else []
        genres = normalize_genre_list([str(item) for item in genres_raw if str(item).strip()])
        by_show_id[int(show_id)] = WatchShow(
            show_id=f"tvmaze-{show_id}",
            title=title,
            poster_url=str(image.get("original") or image.get("medium") or "").strip(),
            synopsis=summary or "No synopsis yet.",
            providers=normalize_provider_list([provider]),
            genres=genres,
            release_date=release_date,
            season_episode_status="Trending now",
            trend_score=max(0.0, 85.0 - float(idx)),
        )
        if len(by_show_id) >= max(1, min(limit, 40)):
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
            diversified = _diversify_provider_mix(ranked)
            return diversified[:safe_limit], source

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
        show.genres = normalize_genre_list(show.genres)
    live_shows = _dedupe_watch_shows(live_shows)
    before_fill_count = len(live_shows)
    live_shows = _fill_with_fallback_shows(live_shows, target_count=safe_limit)
    if source != "fallback_static" and len(live_shows) > before_fill_count:
        source = f"{source}+fallback_fill"
    live_shows = _enrich_missing_posters(
        live_shows,
        timeout_seconds=timeout_seconds,
        force_lookup_existing=("fallback" in source),
    )
    _enrich_episode_air_dates(live_shows, timeout_seconds=timeout_seconds)

    _watch_cache["source"] = source
    _watch_cache["items"] = live_shows
    _watch_cache["expires_at"] = now + timedelta(seconds=max(60, CACHE_TTL_SECONDS))
    ranked = sorted(live_shows, key=lambda show: _sort_key(show, today), reverse=True)
    diversified = _diversify_provider_mix(ranked)
    return diversified[:safe_limit], source


def _sort_key(show: WatchShow, today: date) -> tuple[float, int]:
    primary = (
        (show.next_episode_air_date or show.last_episode_air_date or show.release_date or "").strip()
    )
    release = _parse_release_date(primary)
    # Reward newer releases slightly without overpowering trend score.
    freshness_boost = 0
    if release is not None:
        days = abs((today - release).days)
        freshness_boost = max(0, 30 - days)
    return (show.trend_score, freshness_boost)
