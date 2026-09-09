from __future__ import annotations

import os
import time

import httpx

DEFAULT_BASE_URL = "https://big-daves-news-web.onrender.com"

# Endpoints whose in-process caches expire faster than real traffic refills them.
# /api/watch holds a 15-minute cache (see app/watch.py CACHE_TTL_SECONDS) and costs
# ~20s to rebuild from TMDB/TVmaze; /api/facts rebuilds the claim aggregation.
DEFAULT_PATHS = "/api/watch,/api/facts"


def main() -> None:
    base_url = (os.getenv("WARM_CACHE_BASE_URL", "").strip() or DEFAULT_BASE_URL).rstrip("/")
    paths = [p.strip() for p in os.getenv("WARM_CACHE_PATHS", DEFAULT_PATHS).split(",") if p.strip()]
    timeout = float(os.getenv("WARM_CACHE_TIMEOUT_SECONDS", "60"))

    failures = 0
    for path in paths:
        url = f"{base_url}{path if path.startswith('/') else '/' + path}"
        started = time.monotonic()
        try:
            response = httpx.get(url, timeout=timeout)
            response.raise_for_status()
        except Exception as exc:  # noqa: BLE001 - a warm miss must not fail the whole run
            failures += 1
            elapsed = time.monotonic() - started
            print(f"warm FAILED url={url} elapsed={elapsed:.2f}s error={exc}")
            continue
        elapsed = time.monotonic() - started
        print(f"warm ok url={url} status={response.status_code} elapsed={elapsed:.2f}s")

    print(f"Cache warm completed: {len(paths) - failures}/{len(paths)} endpoints warmed")


if __name__ == "__main__":
    main()
