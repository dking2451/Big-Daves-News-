#!/usr/bin/env python3
"""
Correlate watch_catalog + TMDB resolution for one show_id (ops / root-cause triage).

Usage (from repo root):
  PYTHONPATH=. python scripts/diagnose_watch_poster.py tvmaze-12345
  PYTHONPATH=. python scripts/diagnose_watch_poster.py tmdb-94997 --skip-cache

Log hints:
  grep watch_poster_event /path/to/logs
  grep watch_catalog /path/to/logs
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Repo root: parent of scripts/
_ROOT = Path(__file__).resolve().parents[1]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))


def main() -> int:
    parser = argparse.ArgumentParser(description="Diagnose Watch poster mapping for one show_id.")
    parser.add_argument("show_id", help="API id, e.g. tvmaze-54281 or tmdb-94997")
    parser.add_argument(
        "--skip-cache",
        action="store_true",
        help="Bypass tmdb_cached fast path (force live TMDB round trip)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=8.0,
        help="HTTP timeout seconds for TMDB/TVMaze",
    )
    args = parser.parse_args()

    from app.watch_backfill import inspect_show_resolution

    payload = inspect_show_resolution(
        args.show_id,
        skip_catalog_fast_path=args.skip_cache,
        timeout_seconds=args.timeout,
    )
    print(json.dumps(payload, indent=2, default=str))
    return 0 if payload.get("success") else 1


if __name__ == "__main__":
    raise SystemExit(main())
