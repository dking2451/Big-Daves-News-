from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import time

import httpx


@dataclass
class WeatherAlert:
    headline: str
    severity: str
    event: str
    effective: str
    ends: str
    description: str


@dataclass
class RainTimelinePoint:
    time: str
    precipitation_probability: float
    precipitation_in: float


@dataclass
class DailyForecastPoint:
    date: str
    weather_code: int
    weather_text: str
    weather_icon: str
    temp_max_f: float
    temp_min_f: float
    precipitation_probability_max: float


@dataclass
class WeatherSnapshot:
    location_label: str
    temperature_f: float
    wind_mph: float
    weather_code: int
    weather_text: str
    weather_icon: str
    observed_at: str
    latitude: float
    longitude: float
    map_url: str
    map_embed_url: str
    alerts: list[WeatherAlert]
    rain_timeline: list[RainTimelinePoint]
    forecast_5day: list[DailyForecastPoint]


WEATHER_CODE_TEXT = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Fog",
    48: "Depositing rime fog",
    51: "Light drizzle",
    53: "Moderate drizzle",
    55: "Dense drizzle",
    61: "Slight rain",
    63: "Moderate rain",
    65: "Heavy rain",
    71: "Slight snow",
    73: "Moderate snow",
    75: "Heavy snow",
    80: "Rain showers",
    95: "Thunderstorm",
}


DEFAULT_HTTP_HEADERS = {
    "User-Agent": "BigDavesNewsWeather/1.0 (+https://big-daves-news-web.onrender.com)",
    "Accept": "application/json",
}

_CACHE: dict[str, tuple[float, dict]] = {}
FORECAST_CACHE_TTL_SECONDS = 300
GEOCODE_CACHE_TTL_SECONDS = 86400
ALERTS_CACHE_TTL_SECONDS = 600


def _cache_get(cache_key: str, ttl_seconds: int) -> dict | None:
    cached = _CACHE.get(cache_key)
    if not cached:
        return None
    saved_at, payload = cached
    if (time.time() - saved_at) <= ttl_seconds:
        return payload
    return None


def _cache_set(cache_key: str, payload: dict) -> None:
    _CACHE[cache_key] = (time.time(), payload)


def _get_json_with_retries(url: str, params: dict | None = None, attempts: int = 3, timeout: float = 20) -> dict:
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            with httpx.Client(timeout=timeout, headers=DEFAULT_HTTP_HEADERS, http2=False) as client:
                response = client.get(url, params=params)
                response.raise_for_status()
                return response.json()
        except Exception as exc:
            last_error = exc
            if attempt < attempts:
                # Small exponential backoff helps with transient TLS EOF/network hiccups.
                # If we hit rate limits, back off more aggressively.
                sleep_s = 1.2 * attempt if "429" in str(exc) else 0.35 * attempt
                time.sleep(sleep_s)
                continue
            break
    if last_error is not None:
        raise last_error
    raise RuntimeError("Weather request failed unexpectedly.")


def _weather_text(code: int) -> str:
    return WEATHER_CODE_TEXT.get(code, "Weather update")


def _weather_icon(code: int) -> str:
    if code == 0:
        return "☀️"
    if code in {1, 2, 3}:
        return "⛅"
    if code in {45, 48}:
        return "🌫️"
    if code in {51, 53, 55, 61, 63, 65, 80}:
        return "🌧️"
    if code in {71, 73, 75}:
        return "❄️"
    if code == 95:
        return "⛈️"
    return "🌤️"


def _fetch_us_alerts(lat: float, lon: float) -> list[WeatherAlert]:
    cache_key = f"alerts:{lat:.3f}:{lon:.3f}"
    payload = _cache_get(cache_key, ALERTS_CACHE_TTL_SECONDS)
    if payload is None:
        payload = _get_json_with_retries(
            "https://api.weather.gov/alerts/active",
            params={"point": f"{lat},{lon}"},
            attempts=2,
            timeout=15,
        )
        _cache_set(cache_key, payload)

    alerts: list[WeatherAlert] = []
    for feature in payload.get("features", [])[:5]:
        props = feature.get("properties", {})
        description = (props.get("description") or "").strip()
        if len(description) > 260:
            description = description[:257].rstrip() + "..."
        alerts.append(
            WeatherAlert(
                headline=(props.get("headline") or "Weather alert").strip(),
                severity=(props.get("severity") or "Unknown").strip(),
                event=(props.get("event") or "Advisory").strip(),
                effective=(props.get("effective") or "").strip(),
                ends=(props.get("ends") or "").strip(),
                description=description,
            )
        )
    return alerts


def weather_from_coordinates(lat: float, lon: float, location_label: str = "Your location") -> WeatherSnapshot:
    params = {
        "latitude": lat,
        "longitude": lon,
        "current": "temperature_2m,weather_code,wind_speed_10m",
        "hourly": "precipitation_probability,precipitation",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
        "forecast_hours": 24,
        "forecast_days": 5,
        "temperature_unit": "fahrenheit",
        "precipitation_unit": "inch",
        "wind_speed_unit": "mph",
        "timezone": "auto",
    }
    cache_key = f"forecast:{lat:.3f}:{lon:.3f}"
    payload = _cache_get(cache_key, FORECAST_CACHE_TTL_SECONDS)
    if payload is None:
        payload = _get_json_with_retries(
            "https://api.open-meteo.com/v1/forecast",
            params=params,
            attempts=3,
            timeout=20,
        )
        _cache_set(cache_key, payload)

    current = payload.get("current", {})
    temp_f = float(current.get("temperature_2m", 0.0))
    wind_mph = float(current.get("wind_speed_10m", 0.0))
    weather_code = int(current.get("weather_code", 0))
    observed_at = current.get("time", datetime.utcnow().isoformat())
    hourly = payload.get("hourly", {})
    times = hourly.get("time", [])
    probs = hourly.get("precipitation_probability", [])
    amounts = hourly.get("precipitation", [])

    rain_timeline: list[RainTimelinePoint] = []
    for t, p, amt in zip(times, probs, amounts):
        rain_timeline.append(
            RainTimelinePoint(
                time=str(t),
                precipitation_probability=float(p or 0.0),
                precipitation_in=float(amt or 0.0),
            )
        )
    rain_timeline = rain_timeline[:12]
    daily = payload.get("daily", {})
    daily_dates = daily.get("time", [])
    daily_codes = daily.get("weather_code", [])
    daily_max = daily.get("temperature_2m_max", [])
    daily_min = daily.get("temperature_2m_min", [])
    daily_prob = daily.get("precipitation_probability_max", [])
    forecast_5day: list[DailyForecastPoint] = []
    for dt, code, tmax, tmin, pmax in zip(daily_dates, daily_codes, daily_max, daily_min, daily_prob):
        weather_code_value = int(code or 0)
        forecast_5day.append(
            DailyForecastPoint(
                date=str(dt),
                weather_code=weather_code_value,
                weather_text=_weather_text(weather_code_value),
                weather_icon=_weather_icon(weather_code_value),
                temp_max_f=float(tmax or 0.0),
                temp_min_f=float(tmin or 0.0),
                precipitation_probability_max=float(pmax or 0.0),
            )
        )

    alerts: list[WeatherAlert] = []
    try:
        alerts = _fetch_us_alerts(lat=lat, lon=lon)
    except Exception:
        alerts = []

    return WeatherSnapshot(
        location_label=location_label,
        temperature_f=temp_f,
        wind_mph=wind_mph,
        weather_code=weather_code,
        weather_text=_weather_text(weather_code),
        weather_icon=_weather_icon(weather_code),
        observed_at=observed_at,
        latitude=lat,
        longitude=lon,
        map_url=f"https://www.windy.com/{lat:.4f}/{lon:.4f}?{lat:.4f},{lon:.4f},8",
        map_embed_url=(
            "https://embed.windy.com/embed2.html"
            f"?lat={lat:.4f}&lon={lon:.4f}&zoom=7&level=surface"
            "&overlay=radar&product=radar&menu=true&message=true&marker=true"
        ),
        alerts=alerts,
        rain_timeline=rain_timeline,
        forecast_5day=forecast_5day,
    )


def geocode_zip(zip_code: str) -> tuple[float, float, str]:
    clean_zip = zip_code.strip()
    cache_key = f"geocode:{clean_zip.lower()}"
    payload = _cache_get(cache_key, GEOCODE_CACHE_TTL_SECONDS)
    if payload is None:
        payload = _get_json_with_retries(
            "https://geocoding-api.open-meteo.com/v1/search",
            params={
                "name": clean_zip,
                "count": 1,
                "language": "en",
                "format": "json",
            },
            attempts=3,
            timeout=20,
        )
        _cache_set(cache_key, payload)

    results = payload.get("results", [])
    if not results:
        raise ValueError("Could not find that ZIP/location.")

    first = results[0]
    lat = float(first["latitude"])
    lon = float(first["longitude"])
    city = first.get("name", "")
    admin = first.get("admin1", "")
    country = first.get("country_code", "")
    label = ", ".join([part for part in [city, admin, country] if part])
    return lat, lon, label or clean_zip
