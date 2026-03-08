from __future__ import annotations

import os
import logging
import time
from datetime import datetime, timezone

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
from app.watch import list_watch_shows, release_badge_for_date, release_badge_label
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


PER_TOPIC_HEADLINE_LIMIT = _env_int("HEADLINES_PER_TOPIC_LIMIT", 5)
TOTAL_HEADLINE_LIMIT = _env_int("HEADLINES_TOTAL_LIMIT", 40)


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


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/facts")
def facts() -> dict:
    started = time.perf_counter()
    try:
        source_configs, policy = load_sources()
        articles = fetch_articles(source_configs, per_source_limit=12)
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


@app.get("/api/watch")
def watch(limit: int = 20, device_id: str = "", hide_seen: bool = True, only_saved: bool = False) -> dict:
    shows, source = list_watch_shows(limit=limit)
    normalized_device = normalize_device_id(device_id)
    seen_set = get_watch_seen_set(normalized_device) if normalized_device else set()
    saved_set = get_watch_saved_set(normalized_device) if normalized_device else set()
    saved_meta = get_watch_saved_meta(normalized_device) if normalized_device else {}
    caught_up_map = get_watch_caught_up_map(normalized_device) if normalized_device else {}
    user_reactions = get_watch_user_reactions(normalized_device) if normalized_device else {}
    prefs = get_watch_preferences(normalized_device) if normalized_device else {
        "watch_episode_alerts": False,
        "upcoming_release_reminders": False,
    }
    if only_saved and saved_set:
        shows = [show for show in shows if show.show_id in saved_set]
    elif only_saved:
        shows = []
    if hide_seen and seen_set:
        shows = [show for show in shows if show.show_id not in seen_set]

    vote_stats = get_watch_vote_stats([show.show_id for show in shows])
    scored: list[tuple[float, object]] = []
    for show in shows:
        stats = vote_stats.get(show.show_id, {"up": 0, "down": 0})
        community_delta = max(-20.0, min(20.0, (stats["up"] - stats["down"]) * 0.6))
        personal_reaction = user_reactions.get(show.show_id, "")
        is_seen = show.show_id in seen_set
        caught_up_release = caught_up_map.get(show.show_id, "")
        badge = release_badge_for_date(show.release_date)
        is_upcoming_release = (
            show.show_id in saved_set
            and badge == "upcoming"
            and bool(show.release_date)
        )
        has_new_episode = (
            show.show_id in saved_set
            and badge in {"new", "this_week"}
            and bool(show.release_date)
            and (not caught_up_release or show.release_date > caught_up_release)
        )
        if personal_reaction == "up":
            personal_delta = 6.0 if is_seen else 4.0
        elif personal_reaction == "down":
            personal_delta = -8.0 if is_seen else -6.0
        else:
            personal_delta = 0.0
        new_episode_delta = 10.0 if (prefs.get("watch_episode_alerts", False) and has_new_episode) else 0.0
        upcoming_delta = 4.0 if (prefs.get("upcoming_release_reminders", False) and is_upcoming_release) else 0.0
        score = float(show.trend_score) + community_delta + personal_delta + new_episode_delta + upcoming_delta
        scored.append((score, show))
    scored.sort(key=lambda item: item[0], reverse=True)
    shows = [item[1] for item in scored]
    score_by_show_id = {candidate.show_id: score for score, candidate in scored}

    def serialize_show(show, adjusted_score: float) -> dict:
        stats = vote_stats.get(show.show_id, {"up": 0, "down": 0})
        badge = release_badge_for_date(show.release_date)
        caught_up_release = caught_up_map.get(show.show_id, "")
        is_saved = show.show_id in saved_set
        has_new_episode = (
            is_saved
            and badge in {"new", "this_week"}
            and bool(show.release_date)
            and (not caught_up_release or show.release_date > caught_up_release)
        )
        is_upcoming_release = (
            is_saved
            and badge == "upcoming"
            and bool(show.release_date)
        )
        return {
            "id": show.show_id,
            "title": show.title,
            "poster_url": show.poster_url,
            "synopsis": show.synopsis,
            "providers": show.providers,
            "primary_provider": show.providers[0] if show.providers else "",
            "genres": show.genres,
            "primary_genre": show.genres[0] if show.genres else "",
            "release_date": show.release_date,
            "release_badge": badge,
            "release_badge_label": release_badge_label(badge),
            "season_episode_status": show.season_episode_status,
            "trend_score": round(adjusted_score, 2),
            "seen": show.show_id in seen_set,
            "saved": is_saved,
            "saved_at_utc": saved_meta.get(show.show_id, ""),
            "is_new_episode": has_new_episode if prefs.get("watch_episode_alerts", False) else False,
            "is_upcoming_release": is_upcoming_release if prefs.get("upcoming_release_reminders", False) else False,
            "caught_up_release_date": caught_up_release,
            "user_reaction": user_reactions.get(show.show_id, ""),
            "upvotes": int(stats["up"]),
            "downvotes": int(stats["down"]),
        }
    return {
        "success": True,
        "source": source,
        "device_id": normalized_device,
        "preferences": prefs,
        "count": len(shows),
        "items": [
            serialize_show(
                show,
                score_by_show_id.get(show.show_id, float(show.trend_score)),
            )
            for show in shows
        ],
    }


@app.post("/api/watch/seen")
def watch_seen(payload: WatchSeenRequest) -> dict:
    success, message = set_watch_seen(
        device_id=payload.device_id,
        show_id=payload.show_id,
        seen=bool(payload.seen),
    )
    return {
        "success": success,
        "message": message,
        "device_id": normalize_device_id(payload.device_id),
        "show_id": normalize_show_id(payload.show_id),
        "seen": bool(payload.seen),
    }


@app.post("/api/watch/reaction")
def watch_reaction(payload: WatchReactionRequest) -> dict:
    success, message = set_watch_reaction(
        device_id=payload.device_id,
        show_id=payload.show_id,
        reaction=payload.reaction,
    )
    normalized_reaction = (payload.reaction or "").strip().lower()
    return {
        "success": success,
        "message": message,
        "device_id": normalize_device_id(payload.device_id),
        "show_id": normalize_show_id(payload.show_id),
        "reaction": normalized_reaction if normalized_reaction in {"up", "down", "none"} else "",
    }


@app.post("/api/watch/watchlist")
def watch_watchlist(payload: WatchlistRequest) -> dict:
    success, message = set_watch_saved(
        device_id=payload.device_id,
        show_id=payload.show_id,
        saved=bool(payload.saved),
    )
    return {
        "success": success,
        "message": message,
        "device_id": normalize_device_id(payload.device_id),
        "show_id": normalize_show_id(payload.show_id),
        "saved": bool(payload.saved),
    }


@app.post("/api/watch/caught-up")
def watch_caught_up(payload: WatchCaughtUpRequest) -> dict:
    success, message = set_watch_caught_up(
        device_id=payload.device_id,
        show_id=payload.show_id,
        release_date=payload.release_date,
    )
    return {
        "success": success,
        "message": message,
        "device_id": normalize_device_id(payload.device_id),
        "show_id": normalize_show_id(payload.show_id),
        "release_date": (payload.release_date or "").strip(),
    }


@app.get("/api/watch/preferences")
def watch_preferences(device_id: str = "") -> dict:
    normalized_device = normalize_device_id(device_id)
    prefs = get_watch_preferences(normalized_device)
    return {
        "success": True,
        "device_id": normalized_device,
        "watch_episode_alerts": bool(prefs.get("watch_episode_alerts", False)),
        "upcoming_release_reminders": bool(prefs.get("upcoming_release_reminders", False)),
    }


@app.post("/api/watch/preferences")
def update_watch_preferences(payload: WatchPreferencesRequest) -> dict:
    success, message = set_watch_preferences(
        device_id=payload.device_id,
        watch_episode_alerts=bool(payload.watch_episode_alerts),
        upcoming_release_reminders=bool(payload.upcoming_release_reminders),
    )
    return {
        "success": success,
        "message": message,
        "device_id": normalize_device_id(payload.device_id),
        "watch_episode_alerts": bool(payload.watch_episode_alerts),
        "upcoming_release_reminders": bool(payload.upcoming_release_reminders),
    }


@app.post("/api/talk-to-news")
def talk_to_news(payload: TalkToNewsRequest) -> dict:
    question = payload.question.strip()
    if not question:
        return {"answer": "Please enter a question first.", "mode": "validation"}

    source_configs, policy = load_sources()
    min_tier1 = policy.get("min_tier1_sources", 2)

    # First pass retrieval.
    articles = fetch_articles(source_configs, per_source_limit=12)
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
    articles = fetch_articles(source_configs, per_source_limit=8)
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
