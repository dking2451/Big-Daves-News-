from __future__ import annotations

import os
import logging
import time
import json
from datetime import datetime, timezone, timedelta

from pydantic import BaseModel
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.news_chat import ask_talk_to_news_llm, build_news_context_with_confidence, fallback_news_answer
from app.markets import fetch_market_chart
from app.pipeline import fetch_articles, select_relevant_headlines, validate_claims
from app.sources import load_sources
from app.substack import fetch_latest_substack_posts, list_substack_publications
from app.push_devices import active_push_device_count, unregister_push_device, upsert_push_device
from app.local_news import fetch_local_news
from app.subscribers import MAX_SUBSCRIBERS, add_subscriber, load_subscribers
from app.db import execute_query, get_connection
from app.watch import (
    effective_last_air_for_compare,
    effective_next_air_for_schedule,
    list_watch_shows,
    release_badge_label,
    watch_release_badge,
)
from app.watch_alerts import run_watch_alert_dry_run
from app.watch_feedback import (
    get_watch_caught_up_map,
    get_watch_preferences,
    get_watch_saved_set,
    get_watch_saved_meta,
    get_watch_seen_set,
    get_watch_user_reactions,
    get_watch_vote_stats,
    normalize_device_id,
    normalize_show_id,
    set_watch_caught_up,
    set_watch_preferences,
    set_watch_reaction,
    set_watch_saved,
    set_watch_seen,
)
from app.source_management import (
    approve_source_request,
    create_source_request,
    list_source_requests,
    reject_source_request,
)
from app.sports import get_live_sports_window
from app.weather import geocode_zip, weather_from_coordinates

app = FastAPI(title="Big Daves News")
templates = Jinja2Templates(directory="templates")
logger = logging.getLogger(__name__)


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


PER_TOPIC_HEADLINE_LIMIT = _env_int("HEADLINES_PER_TOPIC_LIMIT", 8)
TOTAL_HEADLINE_LIMIT = _env_int("HEADLINES_TOTAL_LIMIT", 80)
HEADLINES_PER_SOURCE_LIMIT = _env_int("HEADLINES_PER_SOURCE_LIMIT", 18)


def _normalize_provider_key(value: str) -> str:
    return str(value or "").strip().lower()


def _build_provider_preference_scores(
    shows: list,
    saved_set: set[str],
    user_reactions: dict[str, str],
) -> dict[str, float]:
    show_by_id = {show.show_id: show for show in shows}
    scores: dict[str, float] = {}

    def add_provider_weight(provider_name: str, weight: float) -> None:
        key = _normalize_provider_key(provider_name)
        if not key:
            return
        scores[key] = scores.get(key, 0.0) + weight

    for show_id in saved_set:
        show = show_by_id.get(show_id)
        if not show:
            continue
        for provider in getattr(show, "providers", []) or []:
            add_provider_weight(provider, 2.0)

    for show_id, reaction in user_reactions.items():
        if reaction not in {"up", "down"}:
            continue
        show = show_by_id.get(show_id)
        if not show:
            continue
        reaction_weight = 3.0 if reaction == "up" else -2.0
        for provider in getattr(show, "providers", []) or []:
            add_provider_weight(provider, reaction_weight)

    return scores


def _provider_preference_delta(providers: list[str], preference_scores: dict[str, float]) -> float:
    if not providers or not preference_scores:
        return 0.0
    raw = 0.0
    for provider in providers:
        raw += preference_scores.get(_normalize_provider_key(provider), 0.0)
    # Keep this as a light personalization layer.
    return max(-6.0, min(12.0, raw * 0.8))


def _record_api_metric(endpoint: str, duration_ms: int, success: bool, error_text: str = "") -> None:
    try:
        with get_connection() as conn:
            execute_query(
                conn,
                """
                INSERT INTO api_request_metrics(endpoint, success, duration_ms, error_text, created_at_utc)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    endpoint,
                    1 if success else 0,
                    max(0, int(duration_ms)),
                    (error_text or "").strip()[:500],
                    datetime.now(timezone.utc).isoformat(),
                ),
            )
            conn.commit()
    except Exception:
        # Telemetry should never break the user-facing API.
        return


def _normalize_article_id(article_id: str, article_url: str) -> str:
    normalized = (article_id or "").strip()
    if normalized:
        return normalized[:300]
    return (article_url or "").strip()[:300]


def _set_saved_article(payload: SavedArticleRequest) -> tuple[bool, str]:
    normalized_device = normalize_device_id(payload.device_id)
    normalized_url = (payload.url or "").strip()
    normalized_id = _normalize_article_id(payload.article_id, normalized_url)
    if not normalized_device:
        return False, "Missing device_id."
    if not normalized_id or not normalized_url:
        return False, "Missing article_id/url."
    now_utc = datetime.now(timezone.utc).isoformat()
    with get_connection() as conn:
        if payload.saved:
            existing = execute_query(
                conn,
                "SELECT article_id FROM article_saves WHERE device_id = ? AND article_id = ? LIMIT 1",
                (normalized_device, normalized_id),
            ).fetchone()
            if existing:
                execute_query(
                    conn,
                    """
                    UPDATE article_saves
                    SET title = ?, url = ?, source_name = ?, summary = ?, image_url = ?, updated_at_utc = ?
                    WHERE device_id = ? AND article_id = ?
                    """,
                    (
                        (payload.title or "").strip(),
                        normalized_url,
                        (payload.source_name or "").strip(),
                        (payload.summary or "").strip(),
                        (payload.image_url or "").strip(),
                        now_utc,
                        normalized_device,
                        normalized_id,
                    ),
                )
            else:
                execute_query(
                    conn,
                    """
                    INSERT INTO article_saves(
                        device_id, article_id, title, url, source_name, summary, image_url, created_at_utc, updated_at_utc
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        normalized_device,
                        normalized_id,
                        (payload.title or "").strip(),
                        normalized_url,
                        (payload.source_name or "").strip(),
                        (payload.summary or "").strip(),
                        (payload.image_url or "").strip(),
                        now_utc,
                        now_utc,
                    ),
                )
            message = "Saved article."
        else:
            execute_query(
                conn,
                "DELETE FROM article_saves WHERE device_id = ? AND article_id = ?",
                (normalized_device, normalized_id),
            )
            message = "Removed saved article."
        conn.commit()
    return True, message


def _list_saved_articles(device_id: str) -> list[dict]:
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return []
    with get_connection() as conn:
        rows = execute_query(
            conn,
            """
            SELECT article_id, title, url, source_name, summary, image_url, updated_at_utc
            FROM article_saves
            WHERE device_id = ?
            ORDER BY updated_at_utc DESC
            LIMIT 200
            """,
            (normalized_device,),
        ).fetchall()
    result: list[dict] = []
    for row in rows:
        if hasattr(row, "keys"):
            result.append(
                {
                    "article_id": str(row["article_id"]),
                    "title": str(row["title"]),
                    "url": str(row["url"]),
                    "source_name": str(row["source_name"]),
                    "summary": str(row["summary"]),
                    "image_url": str(row["image_url"]),
                    "updated_at_utc": str(row["updated_at_utc"]),
                }
            )
        else:
            result.append(
                {
                    "article_id": str(row[0]),
                    "title": str(row[1]),
                    "url": str(row[2]),
                    "source_name": str(row[3]),
                    "summary": str(row[4]),
                    "image_url": str(row[5]),
                    "updated_at_utc": str(row[6]),
                }
            )
    return result


def _record_app_event(payload: AppEventRequest) -> tuple[bool, str]:
    normalized_device = normalize_device_id(payload.device_id)
    event_name = (payload.event_name or "").strip().lower()
    if not event_name:
        return False, "Missing event_name."
    if len(event_name) > 80:
        event_name = event_name[:80]
    props_json = "{}"
    try:
        props_json = json.dumps(payload.event_props or {}, ensure_ascii=True)[:3000]
    except Exception:
        props_json = "{}"
    with get_connection() as conn:
        execute_query(
            conn,
            """
            INSERT INTO app_events(device_id, event_name, event_props_json, created_at_utc)
            VALUES (?, ?, ?, ?)
            """,
            (
                normalized_device,
                event_name,
                props_json,
                datetime.now(timezone.utc).isoformat(),
            ),
        )
        conn.commit()
    return True, "Recorded event."


def _normalize_pref_label(value: str) -> str:
    return str(value or "").strip().lower()[:80]


def _list_unique_pref_labels(values: list[str], *, max_items: int = 80) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for raw in values:
        normalized = _normalize_pref_label(raw)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        result.append(normalized)
        if len(result) >= max_items:
            break
    return result


def _get_sports_preferences(device_id: str) -> dict[str, list[str]]:
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return {"favorite_leagues": [], "favorite_teams": []}
    with get_connection() as conn:
        row = execute_query(
            conn,
            """
            SELECT favorite_leagues_json, favorite_teams_json
            FROM sports_preferences
            WHERE device_id = ?
            LIMIT 1
            """,
            (normalized_device,),
        ).fetchone()
    if not row:
        return {"favorite_leagues": [], "favorite_teams": []}
    leagues_raw = row["favorite_leagues_json"] if hasattr(row, "keys") else row[0]
    teams_raw = row["favorite_teams_json"] if hasattr(row, "keys") else row[1]
    try:
        leagues = json.loads(leagues_raw or "[]")
        if not isinstance(leagues, list):
            leagues = []
    except Exception:
        leagues = []
    try:
        teams = json.loads(teams_raw or "[]")
        if not isinstance(teams, list):
            teams = []
    except Exception:
        teams = []
    favorite_leagues = _list_unique_pref_labels([str(item) for item in leagues], max_items=32)
    favorite_teams = _list_unique_pref_labels([str(item) for item in teams], max_items=64)
    return {"favorite_leagues": favorite_leagues, "favorite_teams": favorite_teams}


def _set_sports_preferences(device_id: str, favorite_leagues: list[str], favorite_teams: list[str]) -> tuple[bool, str]:
    normalized_device = normalize_device_id(device_id)
    if not normalized_device:
        return False, "Invalid device_id."
    leagues = _list_unique_pref_labels(favorite_leagues, max_items=32)
    teams = _list_unique_pref_labels(favorite_teams, max_items=64)
    now_utc = datetime.now(timezone.utc).isoformat()
    with get_connection() as conn:
        existing = execute_query(
            conn,
            "SELECT device_id FROM sports_preferences WHERE device_id = ? LIMIT 1",
            (normalized_device,),
        ).fetchone()
        leagues_json = json.dumps(leagues, ensure_ascii=True)
        teams_json = json.dumps(teams, ensure_ascii=True)
        if existing:
            execute_query(
                conn,
                """
                UPDATE sports_preferences
                SET favorite_leagues_json = ?, favorite_teams_json = ?, updated_at_utc = ?
                WHERE device_id = ?
                """,
                (leagues_json, teams_json, now_utc, normalized_device),
            )
        else:
            execute_query(
                conn,
                """
                INSERT INTO sports_preferences(
                    device_id, favorite_leagues_json, favorite_teams_json, updated_at_utc
                ) VALUES (?, ?, ?, ?)
                """,
                (normalized_device, leagues_json, teams_json, now_utc),
            )
        conn.commit()
    return True, "Updated sports preferences."


class TalkToNewsRequest(BaseModel):
    question: str


class SubscribeRequest(BaseModel):
    email: str


class SourceRequestCreate(BaseModel):
    name: str
    rss: str
    topic: str = "general"
    requested_by_email: str


class SourceRequestModeration(BaseModel):
    token: str
    note: str = ""


class PushTokenRegisterRequest(BaseModel):
    device_token: str
    platform: str = "ios"
    subscriber_email: str = ""
    app_bundle_id: str = ""
    timezone_name: str = ""


class PushTokenUnregisterRequest(BaseModel):
    device_token: str
    platform: str = "ios"


class WatchSeenRequest(BaseModel):
    device_id: str
    show_id: str
    seen: bool = True


class WatchReactionRequest(BaseModel):
    device_id: str
    show_id: str
    reaction: str


class WatchlistRequest(BaseModel):
    device_id: str
    show_id: str
    saved: bool = True


class WatchCaughtUpRequest(BaseModel):
    device_id: str
    show_id: str
    release_date: str = ""


class WatchPreferencesRequest(BaseModel):
    device_id: str
    watch_episode_alerts: bool = False
    upcoming_release_reminders: bool = False


class SavedArticleRequest(BaseModel):
    device_id: str
    article_id: str = ""
    title: str = ""
    url: str = ""
    source_name: str = ""
    summary: str = ""
    image_url: str = ""
    saved: bool = True


class AppEventRequest(BaseModel):
    device_id: str = ""
    event_name: str
    event_props: dict = {}


class SportsPreferencesRequest(BaseModel):
    device_id: str
    favorite_leagues: list[str] = []
    favorite_teams: list[str] = []


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/facts")
def facts() -> dict:
    started = time.perf_counter()
    try:
        source_configs, policy = load_sources()
        articles = fetch_articles(
            source_configs,
            per_source_limit=max(8, min(HEADLINES_PER_SOURCE_LIMIT, 30)),
        )
        source_index = {s.name: s for s in source_configs}

        claims = validate_claims(
            articles=articles,
            source_index=source_index,
            min_tier1_sources=policy.get("min_tier1_sources", 2),
        )
        claims = select_relevant_headlines(
            claims,
            per_topic_limit=max(0, PER_TOPIC_HEADLINE_LIMIT),
            total_limit=max(0, TOTAL_HEADLINE_LIMIT),
        )
        payload = {
            "sources_used": [s.name for s in source_configs],
            "claims": [
                {
                    "claim_id": c.claim_id,
                    "text": c.text,
                    "category": c.category,
                    "subtopic": c.subtopic,
                    "status": c.status,
                    "confidence": c.confidence,
                    "image_url": c.image_url,
                    "first_seen": c.first_seen.isoformat() if c.first_seen else None,
                    "evidence": [
                        {
                            "source_name": e.source_name,
                            "source_tier": e.source_tier,
                            "article_title": e.article_title,
                            "article_url": e.article_url,
                        }
                        for e in c.evidence
                    ],
                }
                for c in claims
            ],
        }
        _record_api_metric("facts", int((time.perf_counter() - started) * 1000), True)
        return payload
    except Exception as exc:
        _record_api_metric("facts", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"sources_used": [], "claims": []}


@app.get("/api/substack-latest")
def substack_latest(publication: str | None = None) -> dict:
    posts = fetch_latest_substack_posts(per_source_limit=5, total_limit=25, publication=publication)
    return {
        "count": len(posts),
        "publication_filter": publication,
        "available_publications": list_substack_publications(),
        "posts": [
            {
                "publication": post.publication,
                "title": post.title,
                "url": post.url,
                "published": post.published,
            }
            for post in posts
        ],
    }


@app.get("/api/local-news")
def local_news(zip_code: str = "75201", limit: int = 10) -> dict:
    started = time.perf_counter()
    safe_limit = max(1, min(limit, 25))
    try:
        payload = fetch_local_news(zip_code=zip_code, limit=safe_limit)
        _record_api_metric("local-news", int((time.perf_counter() - started) * 1000), True)
        return payload
    except Exception as exc:
        _record_api_metric("local-news", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {
            "success": False,
            "message": "Local news is temporarily unavailable.",
            "zip_code": "".join(ch for ch in (zip_code or "") if ch.isdigit())[:5] or "75201",
            "location_label": "",
            "items": [],
        }


@app.get("/api/articles/saved")
def saved_articles(device_id: str = "") -> dict:
    started = time.perf_counter()
    try:
        normalized_device = normalize_device_id(device_id)
        items = _list_saved_articles(normalized_device)
        _record_api_metric("articles-saved-get", int((time.perf_counter() - started) * 1000), True)
        return {
            "success": True,
            "device_id": normalized_device,
            "count": len(items),
            "items": items,
        }
    except Exception as exc:
        _record_api_metric("articles-saved-get", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {
            "success": False,
            "message": "Could not load saved articles right now.",
            "device_id": normalize_device_id(device_id),
            "count": 0,
            "items": [],
        }


@app.post("/api/articles/saved")
def upsert_saved_article(payload: SavedArticleRequest) -> dict:
    started = time.perf_counter()
    try:
        success, message = _set_saved_article(payload)
        _record_api_metric("articles-saved-set", int((time.perf_counter() - started) * 1000), success, "" if success else message)
        normalized_id = _normalize_article_id(payload.article_id, payload.url)
        return {
            "success": success,
            "message": message,
            "device_id": normalize_device_id(payload.device_id),
            "article_id": normalized_id,
            "saved": bool(payload.saved),
        }
    except Exception as exc:
        _record_api_metric("articles-saved-set", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not update saved article right now."}


@app.post("/api/events")
def app_event(payload: AppEventRequest) -> dict:
    started = time.perf_counter()
    try:
        success, message = _record_app_event(payload)
        _record_api_metric("events", int((time.perf_counter() - started) * 1000), success, "" if success else message)
        return {"success": success, "message": message}
    except Exception as exc:
        _record_api_metric("events", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not record event right now."}


@app.get("/api/weather")
def weather(lat: float | None = None, lon: float | None = None, zip_code: str | None = None) -> dict:
    started = time.perf_counter()
    try:
        if zip_code:
            lat_val, lon_val, label = geocode_zip(zip_code)
            snapshot = weather_from_coordinates(lat=lat_val, lon=lon_val, location_label=label)
        elif lat is not None and lon is not None:
            snapshot = weather_from_coordinates(lat=lat, lon=lon, location_label="Current location")
        else:
            return {"success": False, "message": "Provide zip_code or lat/lon."}

        payload = {
            "success": True,
            "weather": {
                "location_label": snapshot.location_label,
                "temperature_f": snapshot.temperature_f,
                "wind_mph": snapshot.wind_mph,
                "weather_code": snapshot.weather_code,
                "weather_text": snapshot.weather_text,
                "weather_icon": snapshot.weather_icon,
                "observed_at": snapshot.observed_at,
                "latitude": snapshot.latitude,
                "longitude": snapshot.longitude,
                "map_url": snapshot.map_url,
                "map_embed_url": snapshot.map_embed_url,
                "alerts": [
                    {
                        "headline": alert.headline,
                        "severity": alert.severity,
                        "event": alert.event,
                        "effective": alert.effective,
                        "ends": alert.ends,
                        "description": alert.description,
                    }
                    for alert in snapshot.alerts
                ],
                "rain_timeline": [
                    {
                        "time": point.time,
                        "precipitation_probability": point.precipitation_probability,
                        "precipitation_in": point.precipitation_in,
                    }
                    for point in snapshot.rain_timeline
                ],
                "forecast_5day": [
                    {
                        "date": point.date,
                        "weather_code": point.weather_code,
                        "weather_text": point.weather_text,
                        "weather_icon": point.weather_icon,
                        "temp_max_f": point.temp_max_f,
                        "temp_min_f": point.temp_min_f,
                        "precipitation_probability_max": point.precipitation_probability_max,
                    }
                    for point in snapshot.forecast_5day
                ],
            },
        }
        _record_api_metric("weather", int((time.perf_counter() - started) * 1000), True)
        return payload
    except Exception as exc:
        message = str(exc)
        if "429" in message or "rate limit" in message.lower() or "too many requests" in message.lower():
            message = "Weather provider is temporarily busy. Please retry in 1-2 minutes."
        elif "timeout" in message.lower():
            message = "Weather lookup timed out. Please retry in a moment."
        _record_api_metric("weather", int((time.perf_counter() - started) * 1000), False, message)
        return {"success": False, "message": message}


@app.get("/api/market-chart")
def market_chart(symbol: str, range: str = "3mo") -> dict:  # noqa: A002
    try:
        data = fetch_market_chart(symbol=symbol, range_key=range)
        return {"success": True, "chart": data}
    except Exception as exc:
        return {"success": False, "message": str(exc)}


@app.get("/api/sports/now")
def sports_now(
    window_hours: int = 4,
    timezone_name: str = "UTC",
    provider_key: str = "",
    availability_only: bool = False,
    device_id: str = "",
    include_ocho: bool = False,
) -> dict:
    started = time.perf_counter()
    try:
        normalized_device = normalize_device_id(device_id)
        prefs = _get_sports_preferences(normalized_device) if normalized_device else {
            "favorite_leagues": [],
            "favorite_teams": [],
        }
        payload = get_live_sports_window(
            window_hours=window_hours,
            timezone_name=(timezone_name or "UTC").strip() or "UTC",
            provider_key=(provider_key or "").strip().lower(),
            availability_only=availability_only,
            favorite_leagues=set(prefs.get("favorite_leagues", [])),
            favorite_teams=set(prefs.get("favorite_teams", [])),
            include_ocho=bool(include_ocho),
        )
        payload["device_id"] = normalized_device
        _record_api_metric("sports_now", int((time.perf_counter() - started) * 1000), True)
        return payload
    except Exception as exc:
        _record_api_metric("sports_now", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": str(exc), "items": []}


@app.get("/api/sports/preferences")
def sports_preferences(device_id: str = "") -> dict:
    started = time.perf_counter()
    normalized_device = normalize_device_id(device_id)
    try:
        prefs = _get_sports_preferences(normalized_device)
        _record_api_metric("sports-preferences-get", int((time.perf_counter() - started) * 1000), True)
        return {
            "success": True,
            "device_id": normalized_device,
            "favorite_leagues": prefs.get("favorite_leagues", []),
            "favorite_teams": prefs.get("favorite_teams", []),
        }
    except Exception as exc:
        _record_api_metric("sports-preferences-get", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {
            "success": False,
            "message": "Could not load sports preferences right now.",
            "device_id": normalized_device,
            "favorite_leagues": [],
            "favorite_teams": [],
        }


@app.post("/api/sports/preferences")
def update_sports_preferences(payload: SportsPreferencesRequest) -> dict:
    started = time.perf_counter()
    try:
        success, message = _set_sports_preferences(
            device_id=payload.device_id,
            favorite_leagues=payload.favorite_leagues,
            favorite_teams=payload.favorite_teams,
        )
        normalized_device = normalize_device_id(payload.device_id)
        _record_api_metric("sports-preferences-set", int((time.perf_counter() - started) * 1000), success, "" if success else message)
        current = _get_sports_preferences(normalized_device) if success else {"favorite_leagues": [], "favorite_teams": []}
        return {
            "success": success,
            "message": message,
            "device_id": normalized_device,
            "favorite_leagues": current.get("favorite_leagues", []),
            "favorite_teams": current.get("favorite_teams", []),
        }
    except Exception as exc:
        _record_api_metric("sports-preferences-set", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not save sports preferences right now."}


@app.get("/api/watch")
def watch(
    limit: int = 20,
    device_id: str = "",
    hide_seen: bool = True,
    only_saved: bool = False,
    minimum_count: int = 24,
) -> dict:
    started = time.perf_counter()
    requested_limit = max(1, min(limit, 50))
    requested_minimum = max(1, min(minimum_count, 50))
    ingest_limit = max(requested_limit, requested_minimum)
    try:
        shows, source = list_watch_shows(limit=ingest_limit)
    except Exception as exc:
        _record_api_metric("watch", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {
            "success": False,
            "source": "fallback_static",
            "device_id": normalize_device_id(device_id),
            "preferences": {
                "watch_episode_alerts": False,
                "upcoming_release_reminders": False,
            },
            "count": 0,
            "items": [],
        }
    normalized_device = normalize_device_id(device_id)
    seen_set: set[str] = set()
    saved_set: set[str] = set()
    saved_meta: dict[str, str] = {}
    caught_up_map: dict[str, str] = {}
    user_reactions: dict[str, str] = {}
    prefs = {
        "watch_episode_alerts": False,
        "upcoming_release_reminders": False,
    }
    if normalized_device:
        try:
            seen_set = get_watch_seen_set(normalized_device)
            saved_set = get_watch_saved_set(normalized_device)
            saved_meta = get_watch_saved_meta(normalized_device)
            caught_up_map = get_watch_caught_up_map(normalized_device)
            user_reactions = get_watch_user_reactions(normalized_device)
            prefs = get_watch_preferences(normalized_device)
        except Exception as exc:
            logger.warning("Watch personalization degraded for device_id=%s: %s", normalized_device, exc)
    if only_saved and saved_set:
        shows = [show for show in shows if show.show_id in saved_set]
    elif only_saved:
        shows = []
    if hide_seen and seen_set:
        shows = [show for show in shows if show.show_id not in seen_set]

    try:
        vote_stats = get_watch_vote_stats([show.show_id for show in shows])
    except Exception as exc:
        logger.warning("Watch vote stats unavailable: %s", exc)
        vote_stats = {}
    provider_preference_scores = _build_provider_preference_scores(shows, saved_set, user_reactions)
    scored: list[tuple[float, object]] = []
    for show in shows:
        stats = vote_stats.get(show.show_id, {"up": 0, "down": 0})
        community_delta = max(-20.0, min(20.0, (stats["up"] - stats["down"]) * 0.6))
        personal_reaction = user_reactions.get(show.show_id, "")
        is_seen = show.show_id in seen_set
        caught_up_release = caught_up_map.get(show.show_id, "")
        badge = watch_release_badge(show)
        effective_last = effective_last_air_for_compare(show)
        is_upcoming_release = (
            show.show_id in saved_set
            and badge in {"this_week", "upcoming"}
            and bool(effective_next_air_for_schedule(show))
        )
        has_content_new_episode = (
            badge == "new"
            and bool(effective_last)
        )
        has_new_episode_for_user = (
            show.show_id in saved_set
            and has_content_new_episode
            and (not caught_up_release or effective_last > caught_up_release)
        )
        if personal_reaction == "up":
            personal_delta = 6.0 if is_seen else 4.0
        elif personal_reaction == "down":
            personal_delta = -8.0 if is_seen else -6.0
        else:
            personal_delta = 0.0
        provider_delta = _provider_preference_delta(getattr(show, "providers", []) or [], provider_preference_scores)
        new_episode_delta = 10.0 if (prefs.get("watch_episode_alerts", False) and has_new_episode_for_user) else 0.0
        upcoming_delta = 4.0 if (prefs.get("upcoming_release_reminders", False) and is_upcoming_release) else 0.0
        score = float(show.trend_score) + community_delta + personal_delta + provider_delta + new_episode_delta + upcoming_delta
        scored.append((score, show))
    scored.sort(key=lambda item: item[0], reverse=True)
    shows = [item[1] for item in scored]
    score_by_show_id = {candidate.show_id: score for score, candidate in scored}
    if len(shows) > requested_limit:
        shows = shows[:requested_limit]

    def serialize_show(show, adjusted_score: float) -> dict:
        stats = vote_stats.get(show.show_id, {"up": 0, "down": 0})
        badge = watch_release_badge(show)
        caught_up_release = caught_up_map.get(show.show_id, "")
        is_saved = show.show_id in saved_set
        effective_last = effective_last_air_for_compare(show)
        has_new_episode = (
            badge == "new"
            and bool(effective_last)
            and (not is_saved or not caught_up_release or effective_last > caught_up_release)
        )
        is_upcoming_release = (
            is_saved
            and badge in {"this_week", "upcoming"}
            and bool(effective_next_air_for_schedule(show))
        )
        return {
            "id": show.show_id,
            "title": show.title,
            "poster_url": show.poster_url,
            "poster_source": str(getattr(show, "poster_source", "original") or "original"),
            "synopsis": show.synopsis,
            "providers": show.providers,
            "primary_provider": show.providers[0] if show.providers else "",
            "genres": show.genres,
            "primary_genre": show.genres[0] if show.genres else "",
            "release_date": show.release_date,
            "last_episode_air_date": show.last_episode_air_date or "",
            "next_episode_air_date": show.next_episode_air_date or "",
            "release_badge": badge,
            "release_badge_label": release_badge_label(badge),
            "season_episode_status": show.season_episode_status,
            "trend_score": round(adjusted_score, 2),
            "seen": show.show_id in seen_set,
            "saved": is_saved,
            "saved_at_utc": saved_meta.get(show.show_id, ""),
            "is_new_episode": has_new_episode,
            "is_upcoming_release": is_upcoming_release,
            "caught_up_release_date": caught_up_release,
            "user_reaction": user_reactions.get(show.show_id, ""),
            "upvotes": int(stats["up"]),
            "downvotes": int(stats["down"]),
        }
    coverage_count = sum(1 for show in shows if str(getattr(show, "poster_url", "") or "").strip())
    poster_coverage = round((coverage_count / len(shows)), 3) if shows else 0.0
    payload = {
        "success": True,
        "source": source,
        "device_id": normalized_device,
        "preferences": prefs,
        "count": len(shows),
        "poster_coverage": poster_coverage,
        "items": [
            serialize_show(
                show,
                score_by_show_id.get(show.show_id, float(show.trend_score)),
            )
            for show in shows
        ],
    }
    _record_api_metric("watch", int((time.perf_counter() - started) * 1000), True)
    return payload


@app.post("/api/watch/seen")
def watch_seen(payload: WatchSeenRequest) -> dict:
    started = time.perf_counter()
    try:
        success, message = set_watch_seen(
            device_id=payload.device_id,
            show_id=payload.show_id,
            seen=bool(payload.seen),
        )
        _record_api_metric("watch-seen", int((time.perf_counter() - started) * 1000), success, "" if success else message)
        return {
            "success": success,
            "message": message,
            "device_id": normalize_device_id(payload.device_id),
            "show_id": normalize_show_id(payload.show_id),
            "seen": bool(payload.seen),
        }
    except Exception as exc:
        _record_api_metric("watch-seen", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not update seen state right now."}


@app.post("/api/watch/reaction")
def watch_reaction(payload: WatchReactionRequest) -> dict:
    started = time.perf_counter()
    try:
        success, message = set_watch_reaction(
            device_id=payload.device_id,
            show_id=payload.show_id,
            reaction=payload.reaction,
        )
        normalized_reaction = (payload.reaction or "").strip().lower()
        _record_api_metric("watch-reaction", int((time.perf_counter() - started) * 1000), success, "" if success else message)
        return {
            "success": success,
            "message": message,
            "device_id": normalize_device_id(payload.device_id),
            "show_id": normalize_show_id(payload.show_id),
            "reaction": normalized_reaction if normalized_reaction in {"up", "down", "none"} else "",
        }
    except Exception as exc:
        _record_api_metric("watch-reaction", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not save reaction right now."}


@app.post("/api/watch/watchlist")
def watch_watchlist(payload: WatchlistRequest) -> dict:
    started = time.perf_counter()
    try:
        success, message = set_watch_saved(
            device_id=payload.device_id,
            show_id=payload.show_id,
            saved=bool(payload.saved),
        )
        _record_api_metric("watch-watchlist", int((time.perf_counter() - started) * 1000), success, "" if success else message)
        return {
            "success": success,
            "message": message,
            "device_id": normalize_device_id(payload.device_id),
            "show_id": normalize_show_id(payload.show_id),
            "saved": bool(payload.saved),
        }
    except Exception as exc:
        _record_api_metric("watch-watchlist", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not update watchlist right now."}


@app.post("/api/watch/caught-up")
def watch_caught_up(payload: WatchCaughtUpRequest) -> dict:
    started = time.perf_counter()
    try:
        success, message = set_watch_caught_up(
            device_id=payload.device_id,
            show_id=payload.show_id,
            release_date=payload.release_date,
        )
        _record_api_metric("watch-caught-up", int((time.perf_counter() - started) * 1000), success, "" if success else message)
        return {
            "success": success,
            "message": message,
            "device_id": normalize_device_id(payload.device_id),
            "show_id": normalize_show_id(payload.show_id),
            "release_date": (payload.release_date or "").strip(),
        }
    except Exception as exc:
        _record_api_metric("watch-caught-up", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not update caught up status right now."}


@app.get("/api/watch/preferences")
def watch_preferences(device_id: str = "") -> dict:
    started = time.perf_counter()
    normalized_device = normalize_device_id(device_id)
    try:
        prefs = get_watch_preferences(normalized_device)
        _record_api_metric("watch-preferences-get", int((time.perf_counter() - started) * 1000), True)
        return {
            "success": True,
            "device_id": normalized_device,
            "watch_episode_alerts": bool(prefs.get("watch_episode_alerts", False)),
            "upcoming_release_reminders": bool(prefs.get("upcoming_release_reminders", False)),
        }
    except Exception as exc:
        _record_api_metric("watch-preferences-get", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {
            "success": False,
            "message": "Could not load watch preferences right now.",
            "device_id": normalized_device,
            "watch_episode_alerts": False,
            "upcoming_release_reminders": False,
        }


@app.post("/api/watch/preferences")
def update_watch_preferences(payload: WatchPreferencesRequest) -> dict:
    started = time.perf_counter()
    try:
        success, message = set_watch_preferences(
            device_id=payload.device_id,
            watch_episode_alerts=bool(payload.watch_episode_alerts),
            upcoming_release_reminders=bool(payload.upcoming_release_reminders),
        )
        _record_api_metric("watch-preferences-set", int((time.perf_counter() - started) * 1000), success, "" if success else message)
        return {
            "success": success,
            "message": message,
            "device_id": normalize_device_id(payload.device_id),
            "watch_episode_alerts": bool(payload.watch_episode_alerts),
            "upcoming_release_reminders": bool(payload.upcoming_release_reminders),
        }
    except Exception as exc:
        _record_api_metric("watch-preferences-set", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not save watch preferences right now."}


@app.get("/api/watch/alerts/dry-run")
def watch_alerts_dry_run(token: str = "", device_id: str = "", limit: int = 200) -> dict:
    started = time.perf_counter()
    if not _validate_admin_token(token):
        _record_api_metric("watch-alerts-dry-run", int((time.perf_counter() - started) * 1000), False, "Unauthorized")
        return {"success": False, "message": "Unauthorized."}
    try:
        payload = run_watch_alert_dry_run(device_id=device_id, preview_limit=limit)
        _record_api_metric("watch-alerts-dry-run", int((time.perf_counter() - started) * 1000), True)
        return payload
    except Exception as exc:
        _record_api_metric("watch-alerts-dry-run", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not compute watch alert dry run."}


@app.post("/api/talk-to-news")
def talk_to_news(payload: TalkToNewsRequest) -> dict:
    question = payload.question.strip()
    if not question:
        return {"answer": "Please enter a question first.", "mode": "validation"}

    source_configs, policy = load_sources()
    min_tier1 = policy.get("min_tier1_sources", 2)

    # First pass retrieval.
    articles = fetch_articles(
        source_configs,
        per_source_limit=max(8, min(HEADLINES_PER_SOURCE_LIMIT, 30)),
    )
    source_index = {s.name: s for s in source_configs}
    claims = validate_claims(
        articles=articles,
        source_index=source_index,
        min_tier1_sources=min_tier1,
    )
    posts = fetch_latest_substack_posts(per_source_limit=4, total_limit=20)
    context, confidence = build_news_context_with_confidence(
        question=question,
        claims=claims,
        posts=posts,
        articles=articles,
    )

    # Second pass retrieval when confidence is low.
    if confidence < 0.35:
        expanded_articles = fetch_articles(source_configs, per_source_limit=24)
        expanded_claims = validate_claims(
            articles=expanded_articles,
            source_index=source_index,
            min_tier1_sources=min_tier1,
        )
        expanded_posts = fetch_latest_substack_posts(per_source_limit=8, total_limit=35)
        context, _expanded_confidence = build_news_context_with_confidence(
            question=question,
            claims=expanded_claims,
            posts=expanded_posts,
            articles=expanded_articles,
        )
        articles = expanded_articles
        claims = expanded_claims
        posts = expanded_posts

    try:
        answer = ask_talk_to_news_llm(question=question, context=context)
        return {"answer": answer, "mode": "free_llm"}
    except Exception as exc:
        logger.exception("Talk-to-news LLM request failed: %s", exc)
        fallback = fallback_news_answer(question=question, claims=claims, posts=posts, articles=articles)
        return {"answer": fallback, "mode": "fallback", "llm_error": str(exc)}


@app.get("/api/subscribers")
def subscribers() -> dict:
    emails = load_subscribers()
    return {"count": len(emails), "max": MAX_SUBSCRIBERS}


@app.post("/api/subscribe")
def subscribe(payload: SubscribeRequest) -> dict:
    success, message, count = add_subscriber(payload.email)
    return {"success": success, "message": message, "count": count, "max": MAX_SUBSCRIBERS}


@app.post("/api/push/register-token")
def register_push_token(payload: PushTokenRegisterRequest) -> dict:
    success, message = upsert_push_device(
        device_token=payload.device_token,
        platform=payload.platform,
        subscriber_email=payload.subscriber_email,
        app_bundle_id=payload.app_bundle_id,
        timezone_name=payload.timezone_name,
    )
    return {
        "success": success,
        "message": message,
        "active_devices": active_push_device_count(),
    }


@app.post("/api/push/unregister-token")
def unregister_token(payload: PushTokenUnregisterRequest) -> dict:
    success, message = unregister_push_device(
        device_token=payload.device_token,
        platform=payload.platform,
    )
    return {
        "success": success,
        "message": message,
        "active_devices": active_push_device_count(),
    }


@app.get("/api/push/devices-count")
def push_devices_count(token: str = "") -> dict:
    expected = os.getenv("ADMIN_TOKEN", "").strip()
    if expected and not _validate_admin_token(token):
        return {"success": False, "message": "Unauthorized."}
    return {
        "success": True,
        "active_devices": active_push_device_count(),
        "platform": "ios",
    }


@app.post("/api/source-requests")
def create_source(payload: SourceRequestCreate) -> dict:
    success, message, request = create_source_request(
        name=payload.name,
        rss=payload.rss,
        topic=payload.topic,
        requested_by_email=payload.requested_by_email,
    )
    return {
        "success": success,
        "message": message,
        "request": request.__dict__ if request else None,
    }


def _validate_admin_token(token: str) -> bool:
    expected = os.getenv("ADMIN_TOKEN", "").strip()
    return bool(expected and token.strip() == expected)


def _row_value(row, key: str, index: int, default=0):
    if row is None:
        return default
    if hasattr(row, "keys"):
        return row.get(key, default)
    if isinstance(row, (list, tuple)) and len(row) > index:
        return row[index]
    return default


def _metrics_summary_for_window(cutoff_utc_iso: str) -> dict:
    with get_connection() as conn:
        event_rows = execute_query(
            conn,
            """
            SELECT event_name, COUNT(*) AS count
            FROM app_events
            WHERE created_at_utc >= ?
            GROUP BY event_name
            ORDER BY count DESC
            LIMIT 30
            """,
            (cutoff_utc_iso,),
        ).fetchall()
        unique_devices_row = execute_query(
            conn,
            """
            SELECT COUNT(DISTINCT device_id) AS unique_devices
            FROM app_events
            WHERE created_at_utc >= ?
            """,
            (cutoff_utc_iso,),
        ).fetchone()
        api_rows = execute_query(
            conn,
            """
            SELECT endpoint, COUNT(*) AS calls, SUM(success) AS success_calls, AVG(duration_ms) AS avg_duration_ms
            FROM api_request_metrics
            WHERE created_at_utc >= ?
            GROUP BY endpoint
            ORDER BY calls DESC
            LIMIT 30
            """,
            (cutoff_utc_iso,),
        ).fetchall()

    top_events: list[dict] = []
    event_count_map: dict[str, int] = {}
    for row in event_rows:
        name = str(_row_value(row, "event_name", 0, ""))
        count = int(_row_value(row, "count", 1, 0))
        if not name:
            continue
        top_events.append({"event_name": name, "count": count})
        event_count_map[name] = count

    api_by_endpoint: list[dict] = []
    total_api_calls = 0
    failed_api_calls = 0
    for row in api_rows:
        endpoint = str(_row_value(row, "endpoint", 0, ""))
        calls = int(_row_value(row, "calls", 1, 0))
        success_calls = int(_row_value(row, "success_calls", 2, 0))
        avg_duration_raw = _row_value(row, "avg_duration_ms", 3, 0.0)
        avg_duration = float(avg_duration_raw or 0.0)
        if not endpoint:
            continue
        failures = max(0, calls - success_calls)
        total_api_calls += calls
        failed_api_calls += failures
        api_by_endpoint.append(
            {
                "endpoint": endpoint,
                "calls": calls,
                "success_calls": success_calls,
                "failure_calls": failures,
                "avg_duration_ms": round(avg_duration, 1),
            }
        )

    sports_event_names = [
        "sports_open",
        "sports_filter_provider",
        "sports_window_change",
        "sports_follow_toggle",
        "sports_card_open",
        "sports_alert_open",
        "sports_alerts_enabled",
        "sports_alerts_start_toggle",
        "sports_alerts_close_toggle",
        "sports_alerts_digest_toggle",
        "sports_alerts_quiet_hours_toggle",
        "sports_alerts_quiet_hours_time",
        "sports_alerts_scheduled",
    ]
    sports_events = {
        name: int(event_count_map.get(name, 0))
        for name in sports_event_names
    }

    return {
        "cutoff_utc": cutoff_utc_iso,
        "events": {
            "unique_devices": int(_row_value(unique_devices_row, "unique_devices", 0, 0)),
            "total_events": int(sum(event_count_map.values())),
            "top_events": top_events,
            "sports_events": sports_events,
        },
        "api": {
            "total_calls": total_api_calls,
            "failure_calls": failed_api_calls,
            "failure_rate": round((failed_api_calls / total_api_calls), 4) if total_api_calls > 0 else 0.0,
            "by_endpoint": api_by_endpoint,
        },
    }


def _daily_metrics_rollup(days: int = 14) -> dict:
    safe_days = max(2, min(int(days), 60))
    now_utc = datetime.now(timezone.utc)
    start_utc = (now_utc - timedelta(days=safe_days)).isoformat()
    with get_connection() as conn:
        event_rows = execute_query(
            conn,
            """
            SELECT SUBSTR(created_at_utc, 1, 10) AS day_utc, COUNT(*) AS count
            FROM app_events
            WHERE created_at_utc >= ?
            GROUP BY SUBSTR(created_at_utc, 1, 10)
            ORDER BY day_utc ASC
            """,
            (start_utc,),
        ).fetchall()
        sports_open_rows = execute_query(
            conn,
            """
            SELECT SUBSTR(created_at_utc, 1, 10) AS day_utc, COUNT(*) AS count
            FROM app_events
            WHERE created_at_utc >= ? AND event_name = 'sports_open'
            GROUP BY SUBSTR(created_at_utc, 1, 10)
            ORDER BY day_utc ASC
            """,
            (start_utc,),
        ).fetchall()
        api_failure_rows = execute_query(
            conn,
            """
            SELECT SUBSTR(created_at_utc, 1, 10) AS day_utc, COUNT(*) AS count
            FROM api_request_metrics
            WHERE created_at_utc >= ? AND success = 0
            GROUP BY SUBSTR(created_at_utc, 1, 10)
            ORDER BY day_utc ASC
            """,
            (start_utc,),
        ).fetchall()
        api_call_rows = execute_query(
            conn,
            """
            SELECT SUBSTR(created_at_utc, 1, 10) AS day_utc, COUNT(*) AS count
            FROM api_request_metrics
            WHERE created_at_utc >= ?
            GROUP BY SUBSTR(created_at_utc, 1, 10)
            ORDER BY day_utc ASC
            """,
            (start_utc,),
        ).fetchall()

    def _series(rows) -> list[dict]:
        out: list[dict] = []
        for row in rows:
            day = str(_row_value(row, "day_utc", 0, ""))
            count = int(_row_value(row, "count", 1, 0))
            if day:
                out.append({"day_utc": day, "value": count})
        return out

    calls_by_day = {item["day_utc"]: item["value"] for item in _series(api_call_rows)}
    failures_by_day = {item["day_utc"]: item["value"] for item in _series(api_failure_rows)}
    api_failure_rate_series: list[dict] = []
    for day in sorted(calls_by_day.keys()):
        calls = int(calls_by_day.get(day, 0))
        failures = int(failures_by_day.get(day, 0))
        rate = (failures / calls) if calls > 0 else 0.0
        api_failure_rate_series.append({"day_utc": day, "value": round(rate, 4)})

    return {
        "days": safe_days,
        "event_volume_series": _series(event_rows),
        "sports_open_series": _series(sports_open_rows),
        "api_failure_series": _series(api_failure_rows),
        "api_failure_rate_series": api_failure_rate_series,
    }


def _to_layman_metrics(summary_24h: dict, summary_7d: dict) -> dict:
    events_24h = int(summary_24h.get("events", {}).get("total_events", 0))
    unique_24h = int(summary_24h.get("events", {}).get("unique_devices", 0))
    api_calls_24h = int(summary_24h.get("api", {}).get("total_calls", 0))
    api_failures_24h = int(summary_24h.get("api", {}).get("failure_calls", 0))
    api_failure_rate_24h = float(summary_24h.get("api", {}).get("failure_rate", 0.0))
    top_events_24h = summary_24h.get("events", {}).get("top_events", [])[:5]
    top_api_24h = summary_24h.get("api", {}).get("by_endpoint", [])[:5]
    sports_24h = summary_24h.get("events", {}).get("sports_events", {})

    bullets = [
        f"In the last 24 hours, {unique_24h} devices generated {events_24h} tracked actions.",
        f"The API handled {api_calls_24h} requests with {api_failures_24h} failures ({api_failure_rate_24h * 100:.2f}% failure rate).",
    ]
    if top_events_24h:
        bullets.append(
            "Most common user actions: "
            + ", ".join([f"{item.get('event_name', '?')} ({item.get('count', 0)})" for item in top_events_24h[:3]])
            + "."
        )

    sports_bullets = [
        f"Sports opens (24h): {int(sports_24h.get('sports_open', 0))}",
        f"Sports card opens (24h): {int(sports_24h.get('sports_card_open', 0))}",
        f"Sports filters changed (24h): {int(sports_24h.get('sports_filter_provider', 0))}",
    ]

    weekly = {
        "total_events": int(summary_7d.get("events", {}).get("total_events", 0)),
        "unique_devices": int(summary_7d.get("events", {}).get("unique_devices", 0)),
        "api_calls": int(summary_7d.get("api", {}).get("total_calls", 0)),
        "api_failure_rate": float(summary_7d.get("api", {}).get("failure_rate", 0.0)),
    }

    return {
        "summary_bullets": bullets,
        "sports_bullets": sports_bullets,
        "weekly_snapshot": weekly,
    }


@app.get("/api/admin/metrics-summary")
def admin_metrics_summary(token: str = "") -> dict:
    started = time.perf_counter()
    if not _validate_admin_token(token):
        _record_api_metric("admin-metrics-summary", int((time.perf_counter() - started) * 1000), False, "Unauthorized")
        return {"success": False, "message": "Unauthorized."}
    try:
        now_utc = datetime.now(timezone.utc)
        last_24h = (now_utc - timedelta(hours=24)).isoformat()
        last_7d = (now_utc - timedelta(days=7)).isoformat()
        payload = {
            "success": True,
            "generated_at_utc": now_utc.isoformat(),
            "windows": {
                "last_24h": _metrics_summary_for_window(last_24h),
                "last_7d": _metrics_summary_for_window(last_7d),
            },
        }
        _record_api_metric("admin-metrics-summary", int((time.perf_counter() - started) * 1000), True)
        return payload
    except Exception as exc:
        _record_api_metric("admin-metrics-summary", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not load metrics summary right now."}


@app.get("/api/admin/metrics-layman")
def admin_metrics_layman(token: str = "", days: int = 14) -> dict:
    started = time.perf_counter()
    if not _validate_admin_token(token):
        _record_api_metric("admin-metrics-layman", int((time.perf_counter() - started) * 1000), False, "Unauthorized")
        return {"success": False, "message": "Unauthorized."}
    try:
        now_utc = datetime.now(timezone.utc)
        last_24h = (now_utc - timedelta(hours=24)).isoformat()
        last_7d = (now_utc - timedelta(days=7)).isoformat()
        summary_24h = _metrics_summary_for_window(last_24h)
        summary_7d = _metrics_summary_for_window(last_7d)
        payload = {
            "success": True,
            "generated_at_utc": now_utc.isoformat(),
            "plain_english": _to_layman_metrics(summary_24h, summary_7d),
            "tables": {
                "top_events_24h": summary_24h.get("events", {}).get("top_events", []),
                "top_api_endpoints_24h": summary_24h.get("api", {}).get("by_endpoint", []),
                "sports_events_24h": summary_24h.get("events", {}).get("sports_events", {}),
            },
            "charts": _daily_metrics_rollup(days=days),
        }
        _record_api_metric("admin-metrics-layman", int((time.perf_counter() - started) * 1000), True)
        return payload
    except Exception as exc:
        _record_api_metric("admin-metrics-layman", int((time.perf_counter() - started) * 1000), False, str(exc))
        return {"success": False, "message": "Could not build layman metrics summary right now."}


@app.get("/api/source-requests")
def source_requests(token: str = "") -> dict:
    if not _validate_admin_token(token):
        return {"success": False, "message": "Unauthorized."}
    requests = [item.__dict__ for item in list_source_requests()]
    return {"success": True, "requests": requests}


@app.post("/api/source-requests/{request_id}/approve")
def approve_source(request_id: str, payload: SourceRequestModeration) -> dict:
    if not _validate_admin_token(payload.token):
        return {"success": False, "message": "Unauthorized."}
    success, message = approve_source_request(request_id)
    return {"success": success, "message": message}


@app.post("/api/source-requests/{request_id}/reject")
def reject_source(request_id: str, payload: SourceRequestModeration) -> dict:
    if not _validate_admin_token(payload.token):
        return {"success": False, "message": "Unauthorized."}
    success, message = reject_source_request(request_id, note=payload.note)
    return {"success": success, "message": message}


@app.get("/weather", response_class=HTMLResponse)
def weather_page(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="weather.html",
        context={},
    )


@app.get("/business", response_class=HTMLResponse)
def business_page(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="business.html",
        context={},
    )


@app.get("/headlines", response_class=HTMLResponse)
def headlines(request: Request) -> HTMLResponse:
    return home(request)


@app.get("/support", response_class=HTMLResponse)
def support_page(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="support.html",
        context={},
    )


@app.get("/privacy", response_class=HTMLResponse)
def privacy_page(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="privacy.html",
        context={},
    )


@app.get("/", response_class=HTMLResponse)
def home(request: Request) -> HTMLResponse:
    source_configs, policy = load_sources()
    articles = fetch_articles(
        source_configs,
        per_source_limit=max(8, min(HEADLINES_PER_SOURCE_LIMIT, 30)),
    )
    source_index = {s.name: s for s in source_configs}
    sports_sources = [s.name for s in source_configs if s.topic == "sports"]
    claims = validate_claims(
        articles=articles,
        source_index=source_index,
        min_tier1_sources=policy.get("min_tier1_sources", 2),
    )
    claims = select_relevant_headlines(
        claims,
        per_topic_limit=max(0, PER_TOPIC_HEADLINE_LIMIT),
        total_limit=max(0, TOTAL_HEADLINE_LIMIT),
    )

    return templates.TemplateResponse(
        request=request,
        name="index.html",
        context={
            "claims": claims,
            "source_configs": source_configs,
            "sports_sources": sports_sources,
            "policy": policy,
            "substack_publications": list_substack_publications(),
            "subscriber_count": len(load_subscribers()),
            "subscriber_max": MAX_SUBSCRIBERS,
        },
    )
