from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Any
from zoneinfo import ZoneInfo

import httpx

SPORTS_CACHE_TTL_SECONDS = 300

LEAGUE_CONFIGS: list[dict[str, str]] = [
    {"sport": "football", "league": "nfl", "label": "NFL"},
    {"sport": "basketball", "league": "nba", "label": "NBA"},
    {"sport": "baseball", "league": "mlb", "label": "MLB"},
    {"sport": "hockey", "league": "nhl", "label": "NHL"},
    {"sport": "soccer", "league": "usa.1", "label": "MLS"},
]

PROVIDER_NETWORK_RULES: dict[str, list[str]] = {
    "youtube_tv": ["espn", "espn2", "abc", "cbs", "fox", "nbc", "tnt", "tbs", "truTV", "fs1", "nfl network", "mlb network", "nba tv", "nhl network"],
    "hulu_live": ["espn", "espn2", "abc", "cbs", "fox", "nbc", "tnt", "tbs", "fs1", "nfl network", "mlb network", "nba tv"],
    "fubo": ["espn", "espn2", "abc", "cbs", "fox", "nbc", "fs1", "nfl network", "mlb network", "nba tv", "nhl network"],
    "xfinity": ["espn", "espn2", "abc", "cbs", "fox", "nbc", "tnt", "tbs", "truTV", "fs1", "nfl network", "mlb network", "nba tv", "nhl network"],
    "directv_stream": ["espn", "espn2", "abc", "cbs", "fox", "nbc", "tnt", "tbs", "truTV", "fs1", "nfl network", "mlb network", "nba tv", "nhl network"],
    "sling": ["espn", "espn2", "fox", "nbc", "tnt", "tbs", "fs1", "nfl network", "nba tv"],
}

_sports_cache: dict[tuple[int, str, str, bool, str], dict[str, Any]] = {}
_sports_cache_lock = Lock()


@dataclass
class SportsWindowEvent:
    event_id: str
    league: str
    sport: str
    title: str
    start_time_utc: datetime
    start_time_local: str
    status_text: str
    state: str
    is_live: bool
    is_final: bool
    starts_in_minutes: int
    home_team: str
    away_team: str
    home_score: str
    away_score: str
    network: str
    networks: list[str]
    is_available_on_provider: bool
    matched_provider_networks: list[str]
    is_favorite_league: bool
    favorite_team_count: int


def _safe_parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _resolve_timezone(timezone_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(timezone_name)
    except Exception:
        return ZoneInfo("UTC")


def _team_details(competition: dict[str, Any]) -> tuple[str, str, str, str]:
    home_team = ""
    away_team = ""
    home_score = ""
    away_score = ""
    for competitor in competition.get("competitors") or []:
        team = competitor.get("team") or {}
        name = team.get("displayName") or team.get("shortDisplayName") or ""
        score = str(competitor.get("score") or "")
        side = (competitor.get("homeAway") or "").lower()
        if side == "home":
            home_team = name
            home_score = score
        elif side == "away":
            away_team = name
            away_score = score
    return home_team, away_team, home_score, away_score


def _broadcast_name(competition: dict[str, Any]) -> str:
    broadcasts = competition.get("broadcasts") or []
    if not broadcasts:
        return ""
    names = broadcasts[0].get("names") or []
    if names:
        return ", ".join([str(name) for name in names if name])
    return str(broadcasts[0].get("market") or "")


def _broadcast_names(competition: dict[str, Any]) -> list[str]:
    broadcasts = competition.get("broadcasts") or []
    if not broadcasts:
        return []
    names = broadcasts[0].get("names") or []
    result: list[str] = []
    for name in names:
        cleaned = str(name or "").strip()
        if cleaned:
            result.append(cleaned)
    if result:
        return result
    fallback = str(broadcasts[0].get("market") or "").strip()
    return [fallback] if fallback else []


def _normalized_provider_key(provider_key: str) -> str:
    return str(provider_key or "").strip().lower()


def _normalized_label(value: str) -> str:
    return str(value or "").strip().lower()


def _match_provider_networks(provider_key: str, networks: list[str]) -> list[str]:
    normalized_provider = _normalized_provider_key(provider_key)
    if not normalized_provider:
        return []
    rules = PROVIDER_NETWORK_RULES.get(normalized_provider) or []
    if not rules:
        return []
    matched: list[str] = []
    for network in networks:
        normalized_network = network.strip().lower()
        if not normalized_network:
            continue
        for token in rules:
            if token.lower() in normalized_network:
                matched.append(network)
                break
    # Preserve order while removing duplicates.
    unique: list[str] = []
    seen: set[str] = set()
    for name in matched:
        key = name.lower()
        if key in seen:
            continue
        seen.add(key)
        unique.append(name)
    return unique


def _parse_event(
    raw_event: dict[str, Any],
    league_label: str,
    sport_key: str,
    now_utc: datetime,
    window_end: datetime,
    local_tz: ZoneInfo,
    provider_key: str,
    availability_only: bool,
    favorite_leagues: set[str],
    favorite_teams: set[str],
) -> SportsWindowEvent | None:
    event_id = str(raw_event.get("id") or "").strip()
    if not event_id:
        return None

    competition = (raw_event.get("competitions") or [{}])[0]
    start_utc = _safe_parse_datetime(
        raw_event.get("date") or competition.get("date")
    )
    if start_utc is None:
        return None

    status = competition.get("status") or raw_event.get("status") or {}
    status_type = status.get("type") or {}
    state = str(status_type.get("state") or "").lower()
    is_live = state == "in"
    is_final = bool(status_type.get("completed"))
    status_text = str(
        status.get("type", {}).get("shortDetail")
        or status.get("type", {}).get("detail")
        or raw_event.get("status", {}).get("type", {}).get("detail")
        or ""
    )

    include_event = is_live or (start_utc >= now_utc and start_utc <= window_end)
    if not include_event:
        return None

    home_team, away_team, home_score, away_score = _team_details(competition)
    title = str(raw_event.get("name") or "").strip()
    if not title:
        if away_team and home_team:
            title = f"{away_team} at {home_team}"
        else:
            title = "Matchup"

    starts_in_minutes = int((start_utc - now_utc).total_seconds() // 60)
    network = _broadcast_name(competition)
    networks = _broadcast_names(competition)
    matched_provider_networks = _match_provider_networks(provider_key, networks)
    is_available_on_provider = bool(matched_provider_networks) if provider_key else False
    if provider_key and availability_only and not is_available_on_provider:
        return None
    normalized_home = _normalized_label(home_team)
    normalized_away = _normalized_label(away_team)
    is_favorite_league = _normalized_label(league_label) in favorite_leagues
    favorite_team_count = int(normalized_home in favorite_teams) + int(normalized_away in favorite_teams)

    return SportsWindowEvent(
        event_id=event_id,
        league=league_label,
        sport=sport_key,
        title=title,
        start_time_utc=start_utc,
        start_time_local=start_utc.astimezone(local_tz).isoformat(),
        status_text=status_text,
        state=state,
        is_live=is_live,
        is_final=is_final,
        starts_in_minutes=starts_in_minutes,
        home_team=home_team,
        away_team=away_team,
        home_score=home_score,
        away_score=away_score,
        network=network,
        networks=networks,
        is_available_on_provider=is_available_on_provider,
        matched_provider_networks=matched_provider_networks,
        is_favorite_league=is_favorite_league,
        favorite_team_count=favorite_team_count,
    )


def _fetch_scoreboard_events(
    client: httpx.Client,
    sport_key: str,
    league_key: str,
    date_code: str,
) -> list[dict[str, Any]]:
    url = f"https://site.api.espn.com/apis/site/v2/sports/{sport_key}/{league_key}/scoreboard"
    response = client.get(url, params={"dates": date_code, "limit": 200})
    response.raise_for_status()
    payload = response.json()
    return payload.get("events") or []


def _collect_live_sports(
    *,
    window_hours: int,
    timezone_name: str,
    provider_key: str,
    availability_only: bool,
    favorite_leagues: set[str],
    favorite_teams: set[str],
) -> dict[str, Any]:
    now_utc = datetime.now(timezone.utc)
    window_end = now_utc + timedelta(hours=window_hours)
    local_tz = _resolve_timezone(timezone_name)

    today_code = now_utc.strftime("%Y%m%d")
    tomorrow_code = (now_utc + timedelta(days=1)).strftime("%Y%m%d")
    unique_events: dict[str, SportsWindowEvent] = {}

    with httpx.Client(timeout=10.0, follow_redirects=True) as client:
        for cfg in LEAGUE_CONFIGS:
            for date_code in (today_code, tomorrow_code):
                try:
                    raw_events = _fetch_scoreboard_events(
                        client=client,
                        sport_key=cfg["sport"],
                        league_key=cfg["league"],
                        date_code=date_code,
                    )
                except Exception:
                    continue

                for raw_event in raw_events:
                    parsed = _parse_event(
                        raw_event=raw_event,
                        league_label=cfg["label"],
                        sport_key=cfg["sport"],
                        now_utc=now_utc,
                        window_end=window_end,
                        local_tz=local_tz,
                        provider_key=provider_key,
                        availability_only=availability_only,
                        favorite_leagues=favorite_leagues,
                        favorite_teams=favorite_teams,
                    )
                    if parsed is None:
                        continue
                    unique_events[parsed.event_id] = parsed

    events = sorted(
        unique_events.values(),
        key=lambda item: (
            0 if item.is_available_on_provider else 1,
            0 if item.is_live else 1,
            -item.favorite_team_count,
            0 if item.is_favorite_league else 1,
            item.start_time_utc,
            item.league,
            item.title,
        ),
    )

    live_count = sum(1 for item in events if item.is_live)
    available_count = sum(1 for item in events if item.is_available_on_provider)
    favorite_match_count = sum(1 for item in events if item.favorite_team_count > 0 or item.is_favorite_league)
    return {
        "success": True,
        "generated_at_utc": now_utc.isoformat(),
        "timezone_name": local_tz.key,
        "provider_key": provider_key,
        "availability_only": availability_only,
        "favorite_leagues": sorted(list(favorite_leagues)),
        "favorite_teams": sorted(list(favorite_teams)),
        "window_hours": window_hours,
        "count": len(events),
        "live_count": live_count,
        "available_count": available_count,
        "favorite_match_count": favorite_match_count,
        "items": [
            {
                "event_id": item.event_id,
                "league": item.league,
                "sport": item.sport,
                "title": item.title,
                "start_time_utc": item.start_time_utc.isoformat(),
                "start_time_local": item.start_time_local,
                "status_text": item.status_text,
                "state": item.state,
                "is_live": item.is_live,
                "is_final": item.is_final,
                "starts_in_minutes": item.starts_in_minutes,
                "home_team": item.home_team,
                "away_team": item.away_team,
                "home_score": item.home_score,
                "away_score": item.away_score,
                "network": item.network,
                "networks": item.networks,
                "is_available_on_provider": item.is_available_on_provider,
                "matched_provider_networks": item.matched_provider_networks,
                "is_favorite_league": item.is_favorite_league,
                "favorite_team_count": item.favorite_team_count,
            }
            for item in events
        ],
    }


def get_live_sports_window(
    *,
    window_hours: int = 4,
    timezone_name: str = "UTC",
    provider_key: str = "",
    availability_only: bool = False,
    favorite_leagues: set[str] | None = None,
    favorite_teams: set[str] | None = None,
) -> dict[str, Any]:
    bounded_window = max(1, min(window_hours, 12))
    normalized_provider = _normalized_provider_key(provider_key)
    normalized_favorite_leagues = {
        _normalized_label(value) for value in (favorite_leagues or set()) if _normalized_label(value)
    }
    normalized_favorite_teams = {
        _normalized_label(value) for value in (favorite_teams or set()) if _normalized_label(value)
    }
    favorites_token = "|".join(sorted(normalized_favorite_leagues)) + "||" + "|".join(sorted(normalized_favorite_teams))
    cache_key = (bounded_window, timezone_name, normalized_provider, bool(availability_only), favorites_token)
    now_ts = datetime.now(timezone.utc).timestamp()

    with _sports_cache_lock:
        cached = _sports_cache.get(cache_key)
        if cached and now_ts - cached["cached_at_ts"] < SPORTS_CACHE_TTL_SECONDS:
            return cached["payload"]

    payload = _collect_live_sports(
        window_hours=bounded_window,
        timezone_name=timezone_name,
        provider_key=normalized_provider,
        availability_only=bool(availability_only),
        favorite_leagues=normalized_favorite_leagues,
        favorite_teams=normalized_favorite_teams,
    )

    with _sports_cache_lock:
        _sports_cache[cache_key] = {
            "cached_at_ts": now_ts,
            "payload": payload,
        }

    return payload
