from __future__ import annotations

import csv
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx


RANGE_WINDOWS = {
    "1d": timedelta(days=1),
    "1w": timedelta(days=7),
    "3mo": timedelta(days=90),
    "6mo": timedelta(days=180),
    "1y": timedelta(days=365),
    "max": None,
}

SYMBOL_LABELS = {
    "^DJI": "Dow Jones Industrial Average",
    "^IXIC": "NASDAQ Composite",
}


def normalize_symbol(symbol: str) -> str:
    raw = symbol.strip().upper()
    if raw in {"DOW", "DJI", "^DJI"}:
        return "^DJI"
    if raw in {"NASDAQ", "IXIC", "^IXIC", "NASDAC"}:
        return "^IXIC"
    return raw


def stooq_symbol(symbol: str) -> str:
    normalized = normalize_symbol(symbol)
    if normalized == "^IXIC":
        # Stooq does not provide ^IXIC directly; ^NDQ is the closest NASDAQ index feed.
        return "^ndq"
    if normalized.startswith("^"):
        return normalized.lower()
    if "." in normalized:
        return normalized.lower()
    return f"{normalized.lower()}.us"


def fetch_market_chart(symbol: str, range_key: str) -> dict[str, Any]:
    normalized_symbol = normalize_symbol(symbol)
    normalized_range = range_key if range_key in RANGE_WINDOWS else "3mo"
    window = RANGE_WINDOWS[normalized_range]
    symbol_for_source = stooq_symbol(normalized_symbol)

    with httpx.Client(timeout=25) as client:
        response = client.get(
            "https://stooq.com/q/d/l/",
            params={"s": symbol_for_source, "i": "d"},
        )
        response.raise_for_status()
        csv_text = response.text

    points = []
    rows = list(csv.DictReader(csv_text.splitlines()))
    for row in rows:
        date_raw = (row.get("Date") or "").strip()
        close_raw = (row.get("Close") or "").strip()
        if not date_raw or not close_raw:
            continue
        try:
            dt = datetime.strptime(date_raw, "%Y-%m-%d").replace(tzinfo=timezone.utc)
            close = float(close_raw)
        except ValueError:
            continue

        points.append({"t": dt.isoformat(), "v": close})

    if not points:
        raise ValueError("No market data returned.")

    points.sort(key=lambda p: p["t"])

    if window is not None:
        latest_dt = datetime.fromisoformat(points[-1]["t"])
        start_dt = latest_dt - window
        points = [point for point in points if datetime.fromisoformat(point["t"]) >= start_dt]
        if not points:
            raise ValueError("No market data in selected time range.")

    last_close = points[-1]["v"]
    prev_close = points[-2]["v"] if len(points) > 1 else last_close

    return {
        "symbol": normalized_symbol,
        "display_name": SYMBOL_LABELS.get(normalized_symbol, normalized_symbol),
        "currency": "USD",
        "range": normalized_range,
        "interval": "1d",
        "previous_close": prev_close,
        "regular_market_price": last_close,
        "points": points,
    }
