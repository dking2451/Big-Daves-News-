from __future__ import annotations

import os
import logging

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
from app.subscribers import MAX_SUBSCRIBERS, add_subscriber, load_subscribers
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


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/facts")
def facts() -> dict:
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

    return {
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


@app.get("/api/weather")
def weather(lat: float | None = None, lon: float | None = None, zip_code: str | None = None) -> dict:
    try:
        if zip_code:
            lat_val, lon_val, label = geocode_zip(zip_code)
            snapshot = weather_from_coordinates(lat=lat_val, lon=lon_val, location_label=label)
        elif lat is not None and lon is not None:
            snapshot = weather_from_coordinates(lat=lat, lon=lon, location_label="Current location")
        else:
            return {"success": False, "message": "Provide zip_code or lat/lon."}

        return {
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
    except Exception as exc:
        message = str(exc)
        if "429" in message or "rate limit" in message.lower() or "too many requests" in message.lower():
            message = "Weather provider is temporarily busy. Please retry in 1-2 minutes."
        elif "timeout" in message.lower():
            message = "Weather lookup timed out. Please retry in a moment."
        return {"success": False, "message": message}


@app.get("/api/market-chart")
def market_chart(symbol: str, range: str = "3mo") -> dict:  # noqa: A002
    try:
        data = fetch_market_chart(symbol=symbol, range_key=range)
        return {"success": True, "chart": data}
    except Exception as exc:
        return {"success": False, "message": str(exc)}


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
