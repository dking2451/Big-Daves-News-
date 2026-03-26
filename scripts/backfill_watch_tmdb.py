#!/usr/bin/env python3
"""
Full TMDB backfill for watch_catalog: resolve missing IDs, refresh stale posters/metadata.

Requires TMDB_API_KEY. Run from repo root with venv activated:

  export TMDB_API_KEY=...
  python scripts/backfill_watch_tmdb.py
  python scripts/backfill_watch_tmdb.py --dry-run
  python scripts/backfill_watch_tmdb.py --limit 5
  python scripts/backfill_watch_tmdb.py --show-id severance-s2 --show-id the-bear-s4
  python scripts/backfill_watch_tmdb.py --title-contains severance
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description="Full watch_catalog TMDB backfill.")
    parser.add_argument("--dry-run", action="store_true", help="Resolve only; do not write DB.")
    parser.add_argument("--limit", type=int, default=None, help="Max rows to process after filters.")
    parser.add_argument(
        "--show-id",
        action="append",
        dest="show_ids",
        default=None,
        help="Restrict to one or more show_id values (repeatable).",
    )
    parser.add_argument("--title-contains", default=None, help="Case-insensitive substring filter on title.")
    parser.add_argument("--timeout", type=float, default=8.0, help="HTTP timeout per TMDB call.")
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        help="Python logging level.",
    )
    parser.add_argument(
        "--repair-fallback-first",
        action="store_true",
        help="Overwrite watch_catalog from curated FALLBACK_WATCH_SHOWS (tmdb_tv_id + poster) before backfill.",
    )
    args = parser.parse_args()

    if not os.getenv("TMDB_API_KEY", "").strip():
        print("Set TMDB_API_KEY in the environment.", file=sys.stderr)
        return 1

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if root not in sys.path:
        sys.path.insert(0, root)

    logging.basicConfig(level=getattr(logging, args.log_level, logging.INFO), format="%(message)s")

    from app.db import init_db
    from app.watch_backfill import run_full_watch_catalog_backfill
    from app.watch_catalog import repair_catalog_from_curated_fallback

    init_db()
    if args.repair_fallback_first:
        repair_catalog_from_curated_fallback(dry_run=args.dry_run)
    payload = run_full_watch_catalog_backfill(
        dry_run=args.dry_run,
        limit=args.limit,
        only_show_ids=list(args.show_ids) if args.show_ids else None,
        only_title_contains=args.title_contains,
        timeout_seconds=args.timeout,
    )
    print(json.dumps(payload, indent=2, default=str))
    return 0 if payload.get("success") else 1


if __name__ == "__main__":
    raise SystemExit(main())
