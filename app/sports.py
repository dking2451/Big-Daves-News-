from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from threading import Lock
from typing import Any
from zoneinfo import ZoneInfo

import httpx

SPORTS_CACHE_TTL_SECONDS = 300
OCHO_SHOWCASE_BACKFILL_ENABLED = False
OCHO_ALT_SOFT_FLOOR = 6
OCHO_CURATED_EXTENDED_HOURS = 48

SOURCE_LIVE_FEED = "live_feed"
SOURCE_ESPN_EXTENDED = "espn_extended"
SOURCE_CURATED = "curated"

STADIUM_LEAGUE_LABEL = "Stadium (curated)"
STADIUM_SPORT_KEY = "linear_tv"
ESPN_HTTP_HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
    "Accept": "application/json,text/plain,*/*",
}

# Labels must match iOS `SportsFavoritesCatalog` league keys (e.g. NCAAF, NCAAB) for favorite boosts.
CORE_LEAGUE_CONFIGS: list[dict[str, str]] = [
    {"sport": "football", "league": "nfl", "label": "NFL"},
    {"sport": "football", "league": "college-football", "label": "NCAAF"},
    {"sport": "basketball", "league": "nba", "label": "NBA"},
    {"sport": "basketball", "league": "mens-college-basketball", "label": "NCAAB"},
    {"sport": "baseball", "league": "mlb", "label": "MLB"},
    {"sport": "hockey", "league": "nhl", "label": "NHL"},
    {"sport": "soccer", "league": "usa.1", "label": "MLS"},
]

OCHO_LEAGUE_CONFIGS: list[dict[str, str]] = [
    {"sport": "mma", "league": "ufc", "label": "UFC / MMA"},
    {"sport": "mma", "league": "pfl", "label": "PFL"},
    {"sport": "mma", "league": "bellator", "label": "Bellator"},
    {"sport": "australian-football", "league": "afl", "label": "Australian Rules Football"},
    {"sport": "baseball", "league": "college-baseball", "label": "College Baseball"},
    {"sport": "hockey", "league": "mens-college-hockey", "label": "College Hockey"},
    {"sport": "basketball", "league": "womens-college-basketball", "label": "Women's College Basketball"},
    {"sport": "lacrosse", "league": "mens-college-lacrosse", "label": "College Lacrosse"},
    {"sport": "volleyball", "league": "womens-college-volleyball", "label": "Women's College Volleyball"},
    {"sport": "rugby", "league": "3", "label": "NRL / Rugby League"},
    {"sport": "soccer", "league": "uefa.champions", "label": "UEFA Champions League"},
    {"sport": "soccer", "league": "mex.1", "label": "Liga MX"},
]

OCHO_CONFIG_KEYS: frozenset[tuple[str, str]] = frozenset((c["sport"], c["league"]) for c in OCHO_LEAGUE_CONFIGS)

PROVIDER_NETWORK_RULES: dict[str, list[str]] = {
    "youtube_tv": ["espn", "espn2", "abc", "cbs", "fox", "nbc", "tnt", "tbs", "truTV", "fs1", "nfl network", "mlb network", "nba tv", "nhl network"],
    "hulu_live": ["espn", "espn2", "abc", "cbs", "fox", "nbc", "tnt", "tbs", "fs1", "nfl network", "mlb network", "nba tv"],
    "fubo": ["espn", "espn2", "abc", "cbs", "fox", "nbc", "fs1", "nfl network", "mlb network", "nba tv", "nhl network"],
    "paramount_plus": ["paramount", "paramount+", "cbs", "cbs sports", "showtime"],
    "xfinity": ["espn", "espn2", "abc", "cbs", "fox", "nbc", "tnt", "tbs", "truTV", "fs1", "nfl network", "mlb network", "nba tv", "nhl network"],
    "directv_stream": ["espn", "espn2", "abc", "cbs", "fox", "nbc", "tnt", "tbs", "truTV", "fs1", "nfl network", "mlb network", "nba tv", "nhl network"],
    "sling": ["espn", "espn2", "fox", "nbc", "tnt", "tbs", "fs1", "nfl network", "nba tv"],
}

_sports_cache: dict[tuple[int, str, str, bool, str, bool], dict[str, Any]] = {}
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
    ranking_score: float
    ranking_reason: str
    source_type: str
    is_alt_sport: bool = False
    timing_label: str = "tonight"
    ocho_promoted_from_core: bool = False


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


def _next_local_recurrence(now_utc: datetime, local_tz: ZoneInfo, hour: int, minute: int) -> datetime:
    """Next local clock time at hour:minute (may be today or tomorrow)."""
    now_local = now_utc.astimezone(local_tz)
    target = now_local.replace(hour=int(hour), minute=int(minute), second=0, microsecond=0)
    if target <= now_local:
        target += timedelta(days=1)
    return target


def _timing_label(
    *,
    is_live: bool,
    starts_in_minutes: int,
    start_utc: datetime,
    now_utc: datetime,
    local_tz: ZoneInfo,
) -> str:
    if is_live:
        return "live_now"
    if 0 <= starts_in_minutes <= 120:
        return "starting_soon"
    local_start = start_utc.astimezone(local_tz).date()
    local_today = now_utc.astimezone(local_tz).date()
    if local_start == local_today:
        return "tonight"
    if starts_in_minutes <= 360:
        return "starting_soon"
    return "tonight"


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
    source_type: str = SOURCE_LIVE_FEED,
    is_alt_sport: bool = False,
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
    timing_label = _timing_label(
        is_live=is_live,
        starts_in_minutes=starts_in_minutes,
        start_utc=start_utc,
        now_utc=now_utc,
        local_tz=local_tz,
    )

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
        ranking_score=0.0,
        ranking_reason="default",
        source_type=source_type,
        is_alt_sport=is_alt_sport,
        timing_label=timing_label,
        ocho_promoted_from_core=False,
    )


def _fetch_scoreboard_events(
    client: httpx.Client,
    sport_key: str,
    league_key: str,
    date_code: str,
) -> list[dict[str, Any]]:
    url = f"https://site.api.espn.com/apis/site/v2/sports/{sport_key}/{league_key}/scoreboard"
    response = client.get(url, params={"dates": date_code, "limit": 200}, headers=ESPN_HTTP_HEADERS)
    response.raise_for_status()
    payload = response.json()
    return payload.get("events") or []


def _ranking_parts(item: SportsWindowEvent) -> tuple[float, str]:
    score = 0.0
    reasons: list[str] = []
    if item.is_available_on_provider:
        score += 40.0
        reasons.append("available_on_provider")
    if item.is_live:
        score += 35.0
        reasons.append("live_now")
    if item.favorite_team_count > 0:
        team_boost = float(item.favorite_team_count * 18)
        score += team_boost
        reasons.append("favorite_team_match")
    if item.is_favorite_league:
        score += 10.0
        reasons.append("favorite_league")
    if "ocho" in _normalized_label(item.league) or _normalized_label(item.sport) in {"mma"}:
        score += 2.0
        reasons.append("ocho_discovery")
    if item.source_type == SOURCE_ESPN_EXTENDED:
        score += 1.5
        reasons.append("espn_extended_alt")
    if item.source_type == SOURCE_CURATED:
        score += 4.0
        reasons.append("curated_listing")
    if not item.is_live:
        minutes_penalty = max(0.0, min(float(max(item.starts_in_minutes, 0)), 720.0)) * 0.03
        score -= minutes_penalty
    reason = ",".join(reasons) if reasons else "default"
    return score, reason


def _is_ocho_live_event(item: SportsWindowEvent) -> bool:
    if item.is_alt_sport:
        return True
    league = _normalized_label(item.league)
    sport = _normalized_label(item.sport)
    if item.source_type == SOURCE_CURATED:
        return True
    if "ocho" in league:
        return True
    if "mma" in sport:
        return True
    if "australian rules" in league or "afl" == league:
        return True
    return False


def _build_ocho_showcase_events(
    *,
    now_utc: datetime,
    window_end: datetime,
    local_tz: ZoneInfo,
    provider_key: str,
    availability_only: bool,
    favorite_leagues: set[str],
    favorite_teams: set[str],
) -> list[SportsWindowEvent]:
    # Showcase placeholders ensure Ocho mode has discoverable content while feed adapters expand.
    raw_showcase = [
        {
            "event_id": "ocho-mighty-trygon-1",
            "league": "The Ocho",
            "sport": "combat",
            "title": "Triangle Bareknuckle Boxing: Mighty Trygon Main Event",
            "minutes_from_now": 110,
            "home_team": "Trygon Red Corner",
            "away_team": "Trygon Blue Corner",
            "network": "The Ocho Feed",
            "status_text": "Special exhibition card",
        },
        {
            "event_id": "ocho-american-sumo-1",
            "league": "The Ocho",
            "sport": "wrestling",
            "title": "American Sumo Showcase",
            "minutes_from_now": 140,
            "home_team": "Lone Star Heavyweights",
            "away_team": "Pacific Titans",
            "network": "The Ocho Feed",
            "status_text": "Regional championship bracket",
        },
        {
            "event_id": "ocho-slap-fight-1",
            "league": "The Ocho",
            "sport": "combat",
            "title": "Pro Slap Fighting Series",
            "minutes_from_now": 85,
            "home_team": "Openweight Bracket A",
            "away_team": "Openweight Bracket B",
            "network": "The Ocho Feed",
            "status_text": "Qualifier rounds",
        },
        {
            "event_id": "ocho-bare-knuckle-1",
            "league": "The Ocho",
            "sport": "boxing",
            "title": "Bare Knuckle Spotlight",
            "minutes_from_now": 170,
            "home_team": "Southside Striker",
            "away_team": "Downtown Hammer",
            "network": "The Ocho Feed",
            "status_text": "Featured undercard",
        },
    ]
    if provider_key and availability_only:
        return []

    events: list[SportsWindowEvent] = []
    for item in raw_showcase:
        start_utc = now_utc + timedelta(minutes=int(item["minutes_from_now"]))
        if start_utc > window_end:
            continue
        starts_in_minutes = int((start_utc - now_utc).total_seconds() // 60)
        league_label = str(item["league"])
        normalized_home = _normalized_label(str(item["home_team"]))
        normalized_away = _normalized_label(str(item["away_team"]))
        is_favorite_league = _normalized_label(league_label) in favorite_leagues
        favorite_team_count = int(normalized_home in favorite_teams) + int(normalized_away in favorite_teams)
        timing_label = _timing_label(
            is_live=False,
            starts_in_minutes=starts_in_minutes,
            start_utc=start_utc,
            now_utc=now_utc,
            local_tz=local_tz,
        )
        event = SportsWindowEvent(
            event_id=str(item["event_id"]),
            league=league_label,
            sport=str(item["sport"]),
            title=str(item["title"]),
            start_time_utc=start_utc,
            start_time_local=start_utc.astimezone(local_tz).isoformat(),
            status_text=str(item["status_text"]),
            state="pre",
            is_live=False,
            is_final=False,
            starts_in_minutes=starts_in_minutes,
            home_team=str(item["home_team"]),
            away_team=str(item["away_team"]),
            home_score="",
            away_score="",
            network=str(item["network"]),
            networks=[str(item["network"])],
            is_available_on_provider=False,
            matched_provider_networks=[],
            is_favorite_league=is_favorite_league,
            favorite_team_count=favorite_team_count,
            ranking_score=0.0,
            ranking_reason="default",
            source_type=SOURCE_CURATED,
            is_alt_sport=True,
            timing_label=timing_label,
            ocho_promoted_from_core=False,
        )
        event.ranking_score, event.ranking_reason = _ranking_parts(event)
        events.append(event)
    return events


def _stadium_schedule_json_path() -> Path:
    override = (os.environ.get("STADIUM_SCHEDULE_JSON_PATH") or "").strip()
    if override:
        return Path(override).expanduser()
    return Path(__file__).resolve().parent / "data" / "stadium_schedule.json"


def _load_stadium_curated_events(
    *,
    now_utc: datetime,
    window_end: datetime,
    local_tz: ZoneInfo,
    favorite_leagues: set[str],
    favorite_teams: set[str],
) -> list[SportsWindowEvent]:
    """
    Curated Stadium / Bally linear listings (JSON). Not ESPN; used as Ocho stopgap.
    """
    path = _stadium_schedule_json_path()
    if not path.is_file():
        return []

    try:
        raw_text = path.read_text(encoding="utf-8")
        payload = json.loads(raw_text)
    except Exception:
        return []

    rows = payload.get("events") if isinstance(payload, dict) else None
    if not isinstance(rows, list):
        return []

    out: list[SportsWindowEvent] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        eid = str(row.get("id") or "").strip()
        title = str(row.get("title") or "").strip()
        start_raw = str(row.get("start_time_utc") or "").strip()
        if not eid or not title:
            continue
        start_utc = _safe_parse_datetime(start_raw)
        if start_utc is None:
            continue

        event_key = f"stadium-{eid}"
        status_text = str(row.get("status_text") or "Stadium channel").strip()
        home_team = str(row.get("home_team") or "").strip()
        away_team = str(row.get("away_team") or "").strip()
        network = str(row.get("network") or "Stadium").strip() or "Stadium"
        is_live = bool(row.get("is_live")) if "is_live" in row else False

        include_event = is_live or (start_utc >= now_utc and start_utc <= window_end)
        if not include_event:
            continue

        starts_in_minutes = int((start_utc - now_utc).total_seconds() // 60)
        league_label = STADIUM_LEAGUE_LABEL
        normalized_home = _normalized_label(home_team)
        normalized_away = _normalized_label(away_team)
        is_favorite_league = _normalized_label(league_label) in favorite_leagues
        favorite_team_count = int(normalized_home in favorite_teams) + int(normalized_away in favorite_teams)

        state = "in" if is_live else "pre"
        timing_label = _timing_label(
            is_live=is_live,
            starts_in_minutes=starts_in_minutes,
            start_utc=start_utc,
            now_utc=now_utc,
            local_tz=local_tz,
        )
        event = SportsWindowEvent(
            event_id=event_key,
            league=league_label,
            sport=STADIUM_SPORT_KEY,
            title=title,
            start_time_utc=start_utc,
            start_time_local=start_utc.astimezone(local_tz).isoformat(),
            status_text=status_text,
            state=state,
            is_live=is_live,
            is_final=False,
            starts_in_minutes=starts_in_minutes,
            home_team=home_team,
            away_team=away_team,
            home_score="",
            away_score="",
            network=network,
            networks=[network],
            is_available_on_provider=False,
            matched_provider_networks=[],
            is_favorite_league=is_favorite_league,
            favorite_team_count=favorite_team_count,
            ranking_score=0.0,
            ranking_reason="default",
            source_type=SOURCE_CURATED,
            is_alt_sport=True,
            timing_label=timing_label,
            ocho_promoted_from_core=False,
        )
        event.ranking_score, event.ranking_reason = _ranking_parts(event)
        out.append(event)
    return out


def _ocho_curated_json_path() -> Path:
    override = (os.environ.get("OCHO_CURATED_JSON_PATH") or "").strip()
    if override:
        return Path(override).expanduser()
    return Path(__file__).resolve().parent / "data" / "ocho_curated.json"


def _load_ocho_curated_events(
    *,
    now_utc: datetime,
    window_end: datetime,
    local_tz: ZoneInfo,
    favorite_leagues: set[str],
    favorite_teams: set[str],
) -> list[SportsWindowEvent]:
    """
    Hand-maintained Ocho listings + recurring local-time slots. Merged when ESPN alt slate is thin.
    """
    path = _ocho_curated_json_path()
    if not path.is_file():
        return []

    try:
        raw_text = path.read_text(encoding="utf-8")
        payload = json.loads(raw_text)
    except Exception:
        return []

    rows = payload.get("events") if isinstance(payload, dict) else None
    if not isinstance(rows, list):
        return []

    out: list[SportsWindowEvent] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        eid = str(row.get("id") or "").strip()
        title = str(row.get("title") or "").strip()
        if not eid or not title:
            continue

        start_utc: datetime | None = None
        start_raw = str(row.get("start_time_utc") or "").strip()
        if start_raw:
            start_utc = _safe_parse_datetime(start_raw)
        rec_h = row.get("recurring_local_hour")
        if start_utc is None and rec_h is not None:
            start_local = _next_local_recurrence(
                now_utc,
                local_tz,
                int(rec_h),
                int(row.get("recurring_local_minute") or 0),
            )
            start_utc = start_local.astimezone(timezone.utc)

        if start_utc is None:
            continue

        is_live = bool(row.get("is_live")) if "is_live" in row else False
        include_event = is_live or (start_utc >= now_utc and start_utc <= window_end)
        if not include_event:
            continue

        starts_in_minutes = int((start_utc - now_utc).total_seconds() // 60)
        status_text = str(row.get("status_text") or "Alt sports — verify time in your guide").strip()
        home_team = str(row.get("home_team") or "").strip()
        away_team = str(row.get("away_team") or "").strip()
        network = str(row.get("network") or "Streaming / regional").strip() or "Streaming / regional"
        event_key = f"ocho-curated-{eid}"
        normalized_home = _normalized_label(home_team)
        normalized_away = _normalized_label(away_team)
        league_label = str(row.get("league_label") or "Ocho (curated)").strip() or "Ocho (curated)"
        sport_key = str(row.get("sport_key") or "alt_sports").strip() or "alt_sports"
        is_favorite_league = _normalized_label(league_label) in favorite_leagues
        favorite_team_count = int(normalized_home in favorite_teams) + int(normalized_away in favorite_teams)
        state = "in" if is_live else "pre"
        timing_label = _timing_label(
            is_live=is_live,
            starts_in_minutes=starts_in_minutes,
            start_utc=start_utc,
            now_utc=now_utc,
            local_tz=local_tz,
        )
        event = SportsWindowEvent(
            event_id=event_key,
            league=league_label,
            sport=sport_key,
            title=title,
            start_time_utc=start_utc,
            start_time_local=start_utc.astimezone(local_tz).isoformat(),
            status_text=status_text,
            state=state,
            is_live=is_live,
            is_final=False,
            starts_in_minutes=starts_in_minutes,
            home_team=home_team,
            away_team=away_team,
            home_score="",
            away_score="",
            network=network,
            networks=[network],
            is_available_on_provider=False,
            matched_provider_networks=[],
            is_favorite_league=is_favorite_league,
            favorite_team_count=favorite_team_count,
            ranking_score=0.0,
            ranking_reason="default",
            source_type=SOURCE_CURATED,
            is_alt_sport=True,
            timing_label=timing_label,
            ocho_promoted_from_core=False,
        )
        event.ranking_score, event.ranking_reason = _ranking_parts(event)
        out.append(event)
    return out


BIG_FOUR_LEAGUES: frozenset[str] = frozenset({"nfl", "nba", "mlb", "nhl"})


def _league_is_big_four(league_label: str) -> bool:
    return _normalized_label(league_label) in BIG_FOUR_LEAGUES


def _promote_core_events_for_ocho(
    unique_events: dict[str, SportsWindowEvent],
    *,
    now_utc: datetime,
    window_end: datetime,
    floor: int,
) -> int:
    """
    When alt-sport rows are still too few, mark non–big-4 ESPN games as alt so Ocho stays populated.
    Returns count of events promoted this pass.
    """
    active_alt = sum(
        1
        for e in unique_events.values()
        if e.is_alt_sport and not e.is_final and (e.is_live or (e.start_time_utc >= now_utc and e.start_time_utc <= window_end))
    )
    if active_alt >= floor:
        return 0

    candidates = [
        e
        for e in unique_events.values()
        if not e.is_alt_sport
        and not e.ocho_promoted_from_core
        and not e.is_final
        and (e.is_live or (e.start_time_utc >= now_utc and e.start_time_utc <= window_end))
        and not _league_is_big_four(e.league)
        and e.source_type == SOURCE_LIVE_FEED
    ]
    candidates.sort(key=lambda x: (-_ranking_parts(x)[0], x.start_time_utc))
    promoted = 0
    for e in candidates:
        active_alt = sum(
            1
            for x in unique_events.values()
            if x.is_alt_sport
            and not x.is_final
            and (x.is_live or (x.start_time_utc >= now_utc and x.start_time_utc <= window_end))
        )
        if active_alt >= floor:
            break
        replacement = SportsWindowEvent(
            event_id=e.event_id,
            league=e.league,
            sport=e.sport,
            title=e.title,
            start_time_utc=e.start_time_utc,
            start_time_local=e.start_time_local,
            status_text=e.status_text,
            state=e.state,
            is_live=e.is_live,
            is_final=e.is_final,
            starts_in_minutes=e.starts_in_minutes,
            home_team=e.home_team,
            away_team=e.away_team,
            home_score=e.home_score,
            away_score=e.away_score,
            network=e.network,
            networks=list(e.networks),
            is_available_on_provider=e.is_available_on_provider,
            matched_provider_networks=list(e.matched_provider_networks),
            is_favorite_league=e.is_favorite_league,
            favorite_team_count=e.favorite_team_count,
            ranking_score=e.ranking_score,
            ranking_reason=e.ranking_reason,
            source_type=e.source_type,
            is_alt_sport=True,
            timing_label=e.timing_label,
            ocho_promoted_from_core=True,
        )
        replacement.ranking_score, replacement.ranking_reason = _ranking_parts(replacement)
        unique_events[e.event_id] = replacement
        promoted += 1
    return promoted


def _collect_live_sports(
    *,
    window_hours: int,
    timezone_name: str,
    provider_key: str,
    availability_only: bool,
    favorite_leagues: set[str],
    favorite_teams: set[str],
    include_ocho: bool,
) -> dict[str, Any]:
    now_utc = datetime.now(timezone.utc)
    eff_window_hours = window_hours
    if include_ocho:
        eff_window_hours = min(12, max(window_hours, 8))
    window_end = now_utc + timedelta(hours=eff_window_hours)
    local_tz = _resolve_timezone(timezone_name)
    # ESPN scoreboards are keyed by **calendar date** (game “day”). Using only UTC today/tomorrow
    # misses slates still active on the previous **local** day after UTC midnight (e.g. US primetime
    # games). Fetch yesterday / today / tomorrow in the client’s timezone.
    local_now = now_utc.astimezone(local_tz)
    scoreboard_date_codes = [
        (local_now - timedelta(days=1)).strftime("%Y%m%d"),
        local_now.strftime("%Y%m%d"),
        (local_now + timedelta(days=1)).strftime("%Y%m%d"),
    ]
    unique_events: dict[str, SportsWindowEvent] = {}
    source_attempts = 0
    source_successes = 0
    source_failures = 0
    ocho_used_curated_extra = False
    ocho_used_core_promotion = False
    league_configs = list(CORE_LEAGUE_CONFIGS)
    if include_ocho:
        league_configs.extend(OCHO_LEAGUE_CONFIGS)

    http_timeout = 18.0 if include_ocho else 10.0
    with httpx.Client(timeout=http_timeout, follow_redirects=True) as client:
        for cfg in league_configs:
            cfg_key = (cfg["sport"], cfg["league"])
            from_ocho_bundle = cfg_key in OCHO_CONFIG_KEYS
            src = SOURCE_ESPN_EXTENDED if from_ocho_bundle else SOURCE_LIVE_FEED
            for date_code in scoreboard_date_codes:
                source_attempts += 1
                try:
                    raw_events = _fetch_scoreboard_events(
                        client=client,
                        sport_key=cfg["sport"],
                        league_key=cfg["league"],
                        date_code=date_code,
                    )
                    source_successes += 1
                except Exception:
                    source_failures += 1
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
                        source_type=src,
                        is_alt_sport=from_ocho_bundle,
                    )
                    if parsed is None:
                        continue
                    unique_events[parsed.event_id] = parsed

    if include_ocho:
        for stadium_event in _load_stadium_curated_events(
            now_utc=now_utc,
            window_end=window_end,
            local_tz=local_tz,
            favorite_leagues=favorite_leagues,
            favorite_teams=favorite_teams,
        ):
            unique_events[stadium_event.event_id] = stadium_event

        for ocho_row in _load_ocho_curated_events(
            now_utc=now_utc,
            window_end=window_end,
            local_tz=local_tz,
            favorite_leagues=favorite_leagues,
            favorite_teams=favorite_teams,
        ):
            unique_events.setdefault(ocho_row.event_id, ocho_row)

        def _active_alt_count(we: datetime) -> int:
            return sum(
                1
                for e in unique_events.values()
                if e.is_alt_sport
                and not e.is_final
                and (e.is_live or (e.start_time_utc >= now_utc and e.start_time_utc <= we))
            )

        if _active_alt_count(window_end) < OCHO_ALT_SOFT_FLOOR:
            extended_end = now_utc + timedelta(hours=eff_window_hours + OCHO_CURATED_EXTENDED_HOURS)
            before_ids = {k for k, e in unique_events.items() if e.is_alt_sport}
            for ocho_row in _load_ocho_curated_events(
                now_utc=now_utc,
                window_end=extended_end,
                local_tz=local_tz,
                favorite_leagues=favorite_leagues,
                favorite_teams=favorite_teams,
            ):
                unique_events.setdefault(ocho_row.event_id, ocho_row)
            after_ids = {k for k, e in unique_events.items() if e.is_alt_sport}
            if len(after_ids) > len(before_ids):
                ocho_used_curated_extra = True

        promoted_initial = _promote_core_events_for_ocho(
            unique_events,
            now_utc=now_utc,
            window_end=window_end,
            floor=max(4, min(OCHO_ALT_SOFT_FLOOR, 8)),
        )
        promoted_desperate = 0
        if _active_alt_count(window_end) < 1:
            promoted_desperate = _promote_core_events_for_ocho(
                unique_events,
                now_utc=now_utc,
                window_end=window_end,
                floor=1,
            )
        ocho_used_core_promotion = promoted_initial > 0 or promoted_desperate > 0

    if include_ocho and OCHO_SHOWCASE_BACKFILL_ENABLED:
        real_ocho_count = sum(
            1 for item in unique_events.values() if _is_ocho_live_event(item)
        )
        showcase_target = 4
        needed_showcase = max(0, showcase_target - real_ocho_count)
        for showcase in _build_ocho_showcase_events(
            now_utc=now_utc,
            window_end=window_end,
            local_tz=local_tz,
            provider_key=provider_key,
            availability_only=availability_only,
            favorite_leagues=favorite_leagues,
            favorite_teams=favorite_teams,
        )[:needed_showcase]:
            unique_events[showcase.event_id] = showcase

    events = sorted(
        [
            SportsWindowEvent(
                event_id=item.event_id,
                league=item.league,
                sport=item.sport,
                title=item.title,
                start_time_utc=item.start_time_utc,
                start_time_local=item.start_time_local,
                status_text=item.status_text,
                state=item.state,
                is_live=item.is_live,
                is_final=item.is_final,
                starts_in_minutes=item.starts_in_minutes,
                home_team=item.home_team,
                away_team=item.away_team,
                home_score=item.home_score,
                away_score=item.away_score,
                network=item.network,
                networks=item.networks,
                is_available_on_provider=item.is_available_on_provider,
                matched_provider_networks=item.matched_provider_networks,
                is_favorite_league=item.is_favorite_league,
                favorite_team_count=item.favorite_team_count,
                ranking_score=_ranking_parts(item)[0],
                ranking_reason=_ranking_parts(item)[1],
                source_type=item.source_type,
                is_alt_sport=item.is_alt_sport,
                timing_label=item.timing_label,
                ocho_promoted_from_core=item.ocho_promoted_from_core,
            )
            for item in unique_events.values()
        ],
        key=lambda item: (
            -item.ranking_score,
            item.start_time_utc,
            item.league,
            item.title,
        ),
    )

    live_count = sum(1 for item in events if item.is_live)
    available_count = sum(1 for item in events if item.is_available_on_provider)
    favorite_match_count = sum(1 for item in events if item.favorite_team_count > 0 or item.is_favorite_league)

    ocho_feed_status: dict[str, Any] | None = None
    if include_ocho:
        alt_ev = [i for i in events if i.is_alt_sport]
        live_alt = [i for i in alt_ev if i.is_live]
        upcoming_alt = [i for i in alt_ev if not i.is_live and not i.is_final]
        ctx: list[str] = []
        if not live_alt:
            ctx.append("no_live_alt")
        if len(live_alt) == 0 and len(upcoming_alt) < 3:
            ctx.append("sparse_alt_slate")
        if ocho_used_curated_extra:
            ctx.append("curated_backfill")
        if ocho_used_core_promotion:
            ctx.append("core_promoted_for_ocho")
        ocho_feed_status = {
            "no_live_alt_message": "No live alt sports right now - here's what's coming up.",
            "has_live_alt": len(live_alt) > 0,
            "live_alt_count": len(live_alt),
            "upcoming_alt_count": len(upcoming_alt),
            "show_main_sports_cta": True,
            "used_curated_extended_window": ocho_used_curated_extra,
            "used_core_promotion": ocho_used_core_promotion,
            "context_labels": ctx,
        }

    out_payload: dict[str, Any] = {
        "success": True,
        "generated_at_utc": now_utc.isoformat(),
        "timezone_name": local_tz.key,
        "provider_key": provider_key,
        "availability_only": availability_only,
        "favorite_leagues": sorted(list(favorite_leagues)),
        "favorite_teams": sorted(list(favorite_teams)),
        "include_ocho": bool(include_ocho),
        "window_hours": eff_window_hours,
        "count": len(events),
        "live_count": live_count,
        "available_count": available_count,
        "favorite_match_count": favorite_match_count,
        "source_attempts": source_attempts,
        "source_successes": source_successes,
        "source_failures": source_failures,
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
                "ranking_score": item.ranking_score,
                "ranking_reason": item.ranking_reason,
                "source_type": item.source_type,
                "is_alt_sport": item.is_alt_sport,
                "timing_label": item.timing_label,
                "ocho_promoted_from_core": item.ocho_promoted_from_core,
            }
            for item in events
        ],
    }
    if ocho_feed_status is not None:
        out_payload["ocho_feed_status"] = ocho_feed_status
    return out_payload


def get_live_sports_window(
    *,
    window_hours: int = 4,
    timezone_name: str = "UTC",
    provider_key: str = "",
    availability_only: bool = False,
    favorite_leagues: set[str] | None = None,
    favorite_teams: set[str] | None = None,
    include_ocho: bool = False,
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
    cache_key = (
        bounded_window,
        timezone_name,
        normalized_provider,
        bool(availability_only),
        favorites_token,
        bool(include_ocho),
    )
    now_ts = datetime.now(timezone.utc).timestamp()

    stale_cached_payload: dict[str, Any] | None = None
    with _sports_cache_lock:
        cached = _sports_cache.get(cache_key)
        if cached:
            stale_cached_payload = cached["payload"]
            if now_ts - cached["cached_at_ts"] < SPORTS_CACHE_TTL_SECONDS:
                return cached["payload"]

    payload = _collect_live_sports(
        window_hours=bounded_window,
        timezone_name=timezone_name,
        provider_key=normalized_provider,
        availability_only=bool(availability_only),
        favorite_leagues=normalized_favorite_leagues,
        favorite_teams=normalized_favorite_teams,
        include_ocho=bool(include_ocho),
    )

    source_successes = int(payload.get("source_successes", 0) or 0)
    current_count = int(payload.get("count", 0) or 0)
    if (
        current_count == 0
        and source_successes == 0
        and stale_cached_payload
        and int(stale_cached_payload.get("count", 0) or 0) > 0
    ):
        fallback = dict(stale_cached_payload)
        fallback["is_stale"] = True
        fallback["message"] = "Live sports feed is temporarily unavailable. Showing latest available."
        return fallback
    if current_count == 0 and source_successes == 0:
        payload["message"] = "Live sports feed is temporarily unavailable."

    with _sports_cache_lock:
        # Avoid poisoning cache with fully failed empty fetches.
        if current_count > 0 or source_successes > 0:
            _sports_cache[cache_key] = {
                "cached_at_ts": now_ts,
                "payload": payload,
            }

    return payload
