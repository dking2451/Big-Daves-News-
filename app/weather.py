from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

import httpx


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


def weather_from_coordinates(lat: float, lon: float, location_label: str = "Your location") -> WeatherSnapshot:
    with httpx.Client(timeout=20) as client:
        response = client.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": lat,
                "longitude": lon,
                "current": "temperature_2m,weather_code,wind_speed_10m",
                "temperature_unit": "fahrenheit",
                "wind_speed_unit": "mph",
                "timezone": "auto",
            },
        )
        response.raise_for_status()
        payload = response.json()

    current = payload.get("current", {})
    temp_f = float(current.get("temperature_2m", 0.0))
    wind_mph = float(current.get("wind_speed_10m", 0.0))
    weather_code = int(current.get("weather_code", 0))
    observed_at = current.get("time", datetime.utcnow().isoformat())

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
    )


def geocode_zip(zip_code: str) -> tuple[float, float, str]:
    clean_zip = zip_code.strip()
    with httpx.Client(timeout=20) as client:
        response = client.get(
            "https://geocoding-api.open-meteo.com/v1/search",
            params={
                "name": clean_zip,
                "count": 1,
                "language": "en",
                "format": "json",
            },
        )
        response.raise_for_status()
        payload = response.json()

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
