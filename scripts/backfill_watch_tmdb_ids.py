#!/usr/bin/env python3
"""
Warm the SQLite watch_catalog table with stable tmdb_tv_id + trusted poster URLs.

Requires TMDB_API_KEY. Run from repo root:

  export TMDB_API_KEY=...
  python scripts/backfill_watch_tmdb_ids.py
  python scripts/backfill_watch_tmdb_ids.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description="Backfill watch_catalog with TMDB ids from curated fallback shows.")
    parser.add_argument("--dry-run", action="store_true", help="Resolve only; do not write DB.")
    args = parser.parse_args()

    if not os.getenv("TMDB_API_KEY", "").strip():
        print("Set TMDB_API_KEY in the environment.", file=sys.stderr)
        return 1

    # Ensure repo root on path
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if root not in sys.path:
        sys.path.insert(0, root)

    from app.db import init_db
    from app.watch_catalog import backfill_missing_tmdb_tv_ids

    init_db()
    payload = backfill_missing_tmdb_tv_ids(dry_run=args.dry_run, timeout_seconds=8.0)
    print(json.dumps(payload, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
