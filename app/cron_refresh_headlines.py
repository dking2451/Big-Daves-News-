from __future__ import annotations

import os

import httpx


def main() -> None:
    refresh_url = os.getenv("HEADLINE_REFRESH_API_URL", "").strip()
    if not refresh_url:
        report_api_url = os.getenv("REPORT_API_URL", "").strip()
        if report_api_url:
            refresh_url = report_api_url
        else:
            refresh_url = "http://127.0.0.1:8001/api/facts"

    response = httpx.get(refresh_url, timeout=30)
    response.raise_for_status()
    payload = response.json()
    claims = payload.get("claims", [])
    print(f"Headline refresh completed: claims={len(claims)} url={refresh_url}")


if __name__ == "__main__":
    main()
