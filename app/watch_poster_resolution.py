"""
Trust-first TV poster resolution for Watch.

Principle: a wrong poster is worse than a blank/placeholder. TMDB is canonical.
Resolution order: (1) TMDB TV id (with ingest name check), (2) TMDB find by IMDb id,
(3) TMDB find by TVDB id, (4) strict /search/tv with scored top-N disambiguation.
iTunes and other broad artwork sources are not used for TV series.

Confidence is on a 0–100 scale (see module constants). Scores at or above
ACCEPT_MIN_STRICT (85) pass outright; BORDERLINE_MIN..ACCEPT_MIN_STRICT-1 may use
TVMaze alignment. Scores 80–84 may be accepted only via `_safe_relaxed_acceptance`
(strong title + year + type checks), never a blind first-hit.

API poster_status on watch items:
  trusted — canonical TMDB artwork (safe to load remotely).
  missing — no acceptable poster (no key, no candidates, id without art, etc.).
  unresolved_low_confidence — search had candidates but confidence below threshold.
  unverified_remote — non-TMDB image URL (clients should prefer a local premium placeholder).
"""

from __future__ import annotations

import json
import logging
import os
import re
import time
from dataclasses import dataclass, field, replace
from datetime import datetime, timezone
from difflib import SequenceMatcher
from typing import Any
from urllib.parse import quote_plus, urlencode
from urllib.request import Request, urlopen

from app.models import WatchShow

logger = logging.getLogger(__name__)

# Stale policy: skip live TMDB when catalog row was refreshed within this window.
_TMDB_CACHE_MAX_AGE_DAYS = int(os.getenv("TMDB_CACHE_MAX_AGE_DAYS", "30"))
_HTTP_RETRY_ATTEMPTS = int(os.getenv("TMDB_HTTP_RETRY_ATTEMPTS", "3"))

# --- Confidence tiers (0–100 integer scale) ---------------------------------
CONFIDENCE_TMDB_TV_ID = 100
CONFIDENCE_TMDB_EXTERNAL_FIND = 95
# Strict title-search acceptance (default).
ACCEPT_MIN_STRICT = 85
# Relaxed floor: only used when `_safe_relaxed_acceptance` passes (strong title + year sanity).
ACCEPT_MIN_RELAXED = 80
# Backward-compatible alias (strict threshold for TVMaze borderline trigger).
ACCEPT_MIN = ACCEPT_MIN_STRICT
# Lowest confidence we ever persist as trusted (for API unresolved_low_confidence cutover).
LOWEST_ACCEPTED_CONFIDENCE = ACCEPT_MIN_RELAXED
BORDERLINE_MIN = 75  # accept only with strong secondary evidence
# Below BORDERLINE_MIN → reject (placeholder)
# Top-2 score gap for /search/tv disambiguation (short titles need wider separation).
_TOP2_MARGIN_DEFAULT = 4
_TOP2_MARGIN_SHORT_TITLE = 8
_STRICT_ACCEPT_SHORT_TITLE = 90  # ambiguous one-word / very short titles

# Client-visible poster state (serialize as poster_status).
POSTER_STATUS_TRUSTED = "trusted"
POSTER_STATUS_MISSING = "missing"
POSTER_STATUS_UNRESOLVED_LOW_CONFIDENCE = "unresolved_low_confidence"
POSTER_STATUS_UNVERIFIED_REMOTE = "unverified_remote"


def poster_status_for_outcome(outcome: PosterResolveOutcome) -> str:
    """Map resolver outcome to API poster_status for UI/contract."""
    if outcome.trusted:
        return POSTER_STATUS_TRUSTED
    path = (outcome.resolution_path or "").strip()
    if path == "rejected_low_confidence":
        return POSTER_STATUS_UNRESOLVED_LOW_CONFIDENCE
    reason = (outcome.rejection_reason or "").strip().lower()
    if reason.startswith("low_confidence"):
        return POSTER_STATUS_UNRESOLVED_LOW_CONFIDENCE
    return POSTER_STATUS_MISSING


@dataclass
class PosterResolveOutcome:
    """Result of one poster resolution attempt; also used for observability."""

    poster_url: str
    tmdb_tv_id: int | None
    confidence: int
    resolution_path: str  # tmdb_tv_id | tmdb_cached | tmdb_find_imdb | tmdb_find_tvdb | tmdb_search | rejected | placeholder
    trusted: bool
    candidate_name: str = ""
    candidate_first_air: str = ""
    rejection_reason: str = ""
    debug_notes: list[str] = field(default_factory=list)
    backdrop_url: str = ""
    tmdb_canonical_title: str = ""
    tmdb_first_air_date: str = ""

    def debug_summary(self) -> str:
        payload = {
            "path": self.resolution_path,
            "confidence": self.confidence,
            "trusted": self.trusted,
            "candidate": self.candidate_name,
            "first_air": self.candidate_first_air,
            "tmdb_tv_id": self.tmdb_tv_id,
            "reject": self.rejection_reason,
            "notes": self.debug_notes[:8],
        }
        return json.dumps(payload, ensure_ascii=False)[:900]


# --- Title normalization & aliases -------------------------------------------

# Map catalogue title → preferred search / compare string (TMDB listing).
_TITLE_ALIASES: dict[str, str] = {
    "marshall": "marshals",
    "marshals": "marshals",
}


def normalize_tv_series_title(raw: str) -> str:
    """
    Lowercase, strip punctuation, collapse whitespace, & → and, drop noisy suffixes
    (season markers, 'series', 'tv show', episode markers).
    """
    t = (raw or "").strip().lower()
    if not t:
        return ""
    t = t.replace("&", " and ")
    t = re.sub(r"\s*\(\s*\d{4}\s*(?:-\s*\d{4})?\s*\)\s*$", "", t)
    t = re.sub(
        r"\b(season|series|complete series|limited series)\s+[\d]+\b.*$",
        "",
        t,
        flags=re.IGNORECASE,
    )
    t = re.sub(
        r"\s*-\s*season\s+[\w\d]+.*$",
        "",
        t,
        flags=re.IGNORECASE,
    )
    t = re.sub(r"\s+season\s+[\w\d]+.*$", "", t, flags=re.IGNORECASE)
    t = re.sub(r"\s+part\s+\d+.*$", "", t, flags=re.IGNORECASE)
    t = re.sub(r"\b(tv show|television series|the series)\b", "", t, flags=re.IGNORECASE)
    t = re.sub(r"\bepisode\s+[\w\d]+\b.*$", "", t, flags=re.IGNORECASE)
    t = re.sub(r"[^a-z0-9\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()

    alias_key = t.replace(" ", "")
    if alias_key in _TITLE_ALIASES:
        return _TITLE_ALIASES[alias_key]
    if t in _TITLE_ALIASES:
        return _TITLE_ALIASES[t]
    return t


def _token_set(norm: str) -> set[str]:
    return {w for w in norm.split() if len(w) > 1}


def ingest_titles_coherent_for_poster_mapping(ingest_title: str, tmdb_or_catalog_title: str) -> bool:
    """
    True when ingest title plausibly matches TMDB listing or stored canonical title.
    False for unrelated pairs (e.g. Silo vs House of the Dragon).
    """
    a = (ingest_title or "").strip()
    b = (tmdb_or_catalog_title or "").strip()
    if not a or not b:
        return True
    wanted = normalize_tv_series_title(a)
    other = normalize_tv_series_title(b)
    if not wanted or not other:
        return True
    if wanted == other:
        return True
    if len(wanted) >= 6 and (wanted in other or other in wanted):
        return True
    wt, ot = _token_set(wanted), _token_set(other)
    if wt and wt <= ot:
        return True
    if wt and ot:
        inter = wt & ot
        recall = len(inter) / len(wt) if wt else 0.0
        if len(wanted) <= 10 and recall < 1.0:
            return False
        if recall >= 0.85:
            return True
    sim = SequenceMatcher(None, wanted, other).ratio()
    return sim >= 0.82


def is_ambiguous_short_title(show: WatchShow) -> bool:
    """One-word / very short normalized titles need stricter acceptance and top-2 margin."""
    n = normalize_tv_series_title(show.title or "")
    if not n:
        return True
    if len(n) <= 5:
        return True
    if len(n.split()) == 1 and len(n) < 10:
        return True
    return False


def effective_accept_min_strict(show: WatchShow) -> int:
    return _STRICT_ACCEPT_SHORT_TITLE if is_ambiguous_short_title(show) else ACCEPT_MIN_STRICT


def top2_margin_for_show(show: WatchShow) -> int:
    return _TOP2_MARGIN_SHORT_TITLE if is_ambiguous_short_title(show) else _TOP2_MARGIN_DEFAULT


def _http_get_json_once(url: str, timeout_seconds: float, headers: dict[str, str] | None = None) -> object:
    request = Request(url, headers=headers or {})
    with urlopen(request, timeout=timeout_seconds) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw)


def _http_get_json(url: str, timeout_seconds: float, headers: dict[str, str] | None = None) -> object:
    """TMDB HTTP GET with small exponential backoff (does not retry on 4xx)."""
    last_exc: Exception | None = None
    for attempt in range(max(1, _HTTP_RETRY_ATTEMPTS)):
        try:
            return _http_get_json_once(url, timeout_seconds, headers)
        except Exception as exc:
            last_exc = exc
            if attempt < _HTTP_RETRY_ATTEMPTS - 1:
                delay = 0.5 * (2**attempt)
                time.sleep(min(delay, 4.0))
    assert last_exc is not None
    raise last_exc


def catalog_refresh_is_stale(iso_ts: str) -> bool:
    """True when missing, unparsable, or older than TMDB_CACHE_MAX_AGE_DAYS."""
    raw = (iso_ts or "").strip()
    if not raw:
        return True
    try:
        s = raw.replace("Z", "+00:00")
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        age = datetime.now(timezone.utc) - dt.astimezone(timezone.utc)
        return age.days >= max(1, _TMDB_CACHE_MAX_AGE_DAYS)
    except Exception:
        return True


def _backdrop_url_from_path(backdrop_path: str) -> str:
    p = str(backdrop_path or "").strip()
    if not p:
        return ""
    return f"https://image.tmdb.org/t/p/w780{p}"


def _poster_url_from_path(poster_path: str) -> str:
    p = str(poster_path or "").strip()
    if not p:
        return ""
    return f"https://image.tmdb.org/t/p/w500{p}"


def try_resolve_from_fresh_catalog_cache(show: WatchShow) -> PosterResolveOutcome | None:
    """
    Skip live TMDB when watch_catalog merged a fresh trusted poster + id (runtime cache hit).
    Never bypasses ID-first: requires stable tmdb_tv_id on the show.
    """
    tv_id = tmdb_tv_id_for_show(show)
    if tv_id is None:
        return None
    url = str(show.poster_url or "").strip()
    if not url.startswith("https://image.tmdb.org/"):
        return None
    if "placehold.co" in url.lower():
        return None
    last_ref = str(getattr(show, "tmdb_last_refreshed_at", "") or "").strip()
    if not last_ref or catalog_refresh_is_stale(last_ref):
        return None
    canon_check = str(getattr(show, "tmdb_canonical_title", "") or "").strip()
    if canon_check and not ingest_titles_coherent_for_poster_mapping(show.title, canon_check):
        logger.debug(
            "watch_poster skip catalog fast path (ingest vs canonical mismatch) show_id=%s ingest=%r canon=%r",
            show.show_id,
            (show.title or "")[:80],
            canon_check[:80],
        )
        return None
    conf = getattr(show, "poster_confidence", None)
    if conf is None:
        conf = CONFIDENCE_TMDB_TV_ID
    cname = canon_check or str(show.title or "").strip()
    cfa = str(getattr(show, "tmdb_catalog_first_air_date", "") or show.release_date or "").strip()
    return PosterResolveOutcome(
        poster_url=url,
        tmdb_tv_id=tv_id,
        confidence=int(conf),
        resolution_path="tmdb_cached",
        trusted=True,
        candidate_name=cname[:200],
        candidate_first_air=cfa[:32],
        backdrop_url=str(getattr(show, "tmdb_backdrop_url", "") or "")[:800],
        tmdb_canonical_title=cname[:200],
        tmdb_first_air_date=cfa[:32],
        debug_notes=["catalog_cache_hit"],
    )


def _poster_placeholder_url(title: str) -> str:
    label = quote_plus((title or "Watch").strip()[:40] or "Watch")
    return f"https://placehold.co/300x450/1f2937/ffffff.png?text={label}"


def tmdb_tv_id_for_show(show: WatchShow) -> int | None:
    raw = getattr(show, "tmdb_tv_id", None)
    if raw is not None:
        try:
            return int(raw)
        except (TypeError, ValueError):
            pass
    sid = (show.show_id or "").strip()
    if sid.startswith("tmdb-"):
        try:
            return int(sid.split("-", 1)[1])
        except (ValueError, IndexError):
            return None
    return None


def _year_int_from_release(raw: str) -> int | None:
    s = (raw or "").strip()
    if len(s) >= 4 and s[:4].isdigit():
        try:
            y = int(s[:4])
            if 1900 <= y <= 2100:
                return y
        except ValueError:
            pass
    return None


def _show_expects_live_action(show: WatchShow) -> bool:
    """Rough heuristic: penalize animation/cartoon candidates for drama-heavy listings."""
    g = " ".join(show.genres or []).lower()
    if "animation" in g or "anime" in g or "kids" in g:
        return False
    if "invincible" in (show.title or "").lower():
        return False
    return True


_TMDB_ANIMATION_GENRE_ID = 16


def _genre_ids_from_candidate(c: dict) -> list[int]:
    raw = c.get("genre_ids")
    if not isinstance(raw, list):
        return []
    out: list[int] = []
    for x in raw:
        try:
            out.append(int(x))
        except (TypeError, ValueError):
            continue
    return out


def _safe_relaxed_acceptance(
    show: WatchShow,
    candidate: dict[str, Any],
    raw_search_score: int,
    confidence_after_validation: int,
) -> bool:
    """
    Allow 80–84 only when title match is already strong and year/type checks pass.
    Never enables weak fuzzy matches or animation/live-action mismatches.
    """
    if confidence_after_validation < ACCEPT_MIN_RELAXED or raw_search_score < 76:
        return False
    names = [
        str(candidate.get("name") or "").strip(),
        str(candidate.get("original_name") or "").strip(),
    ]
    wanted = normalize_tv_series_title(show.title)
    if not wanted or len(wanted) < 4:
        return False
    ok_title = False
    for n in names:
        if not n:
            continue
        cn = normalize_tv_series_title(n)
        if not cn:
            continue
        if wanted == cn:
            ok_title = True
            break
        if len(wanted) >= 6 and (wanted in cn or cn in wanted):
            ok_title = True
            break
    if not ok_title:
        return False
    year_hint = _year_int_from_release(show.release_date)
    fa = str(candidate.get("first_air_date") or "").strip()
    c_year = _year_int_from_release(fa)
    if year_hint is not None and c_year is not None:
        if abs(c_year - year_hint) > 1:
            return False
    if _show_expects_live_action(show) and _TMDB_ANIMATION_GENRE_ID in _genre_ids_from_candidate(candidate):
        return False
    return True


def _effective_accept_search(
    confidence: int,
    show: WatchShow,
    cand: dict[str, Any],
    raw_search_score: int,
) -> bool:
    strict_floor = effective_accept_min_strict(show)
    if confidence >= strict_floor:
        return True
    if is_ambiguous_short_title(show):
        return False
    if confidence >= ACCEPT_MIN_STRICT:
        return True
    if confidence >= ACCEPT_MIN_RELAXED:
        return _safe_relaxed_acceptance(show, cand, raw_search_score, confidence)
    return False


def log_watch_poster_resolution_event(show: WatchShow, outcome: PosterResolveOutcome) -> None:
    """Structured, grep-friendly log line for every resolution outcome."""
    y = (outcome.candidate_first_air or "")[:4] if outcome.candidate_first_air else ""
    logger.info(
        "watch_poster_event title=%r show_id=%s existing_tmdb=%s path=%s accepted=%s "
        "tmdb_tv_id=%s candidate_title=%r candidate_year=%s confidence=%s reject=%s",
        (show.title or "")[:120],
        show.show_id,
        tmdb_tv_id_for_show(show),
        outcome.resolution_path,
        outcome.trusted,
        outcome.tmdb_tv_id,
        (outcome.candidate_name or "")[:120],
        y,
        outcome.confidence,
        (outcome.rejection_reason or "")[:200],
    )


def _finish(show: WatchShow, outcome: PosterResolveOutcome) -> PosterResolveOutcome:
    log_watch_poster_resolution_event(show, outcome)
    return outcome


def score_tmdb_tv_candidate(
    show: WatchShow,
    candidate: dict[str, Any],
    *,
    year_hint: int | None,
) -> int:
    """
    Score a TMDB /search/tv hit 0–100 (heuristic). Not used for direct id matches.
    """
    if not isinstance(candidate, dict):
        return 0
    names = [
        str(candidate.get("name") or "").strip(),
        str(candidate.get("original_name") or "").strip(),
    ]
    wanted = normalize_tv_series_title(show.title)
    if not wanted:
        return 0

    best_title_score = 0
    for n in names:
        if not n:
            continue
        cn = normalize_tv_series_title(n)
        if not cn:
            continue
        if wanted == cn:
            best_title_score = max(best_title_score, 88)
        elif wanted in cn or cn in wanted:
            best_title_score = max(best_title_score, 80)
        else:
            wt, ct = _token_set(wanted), _token_set(cn)
            if wt and wt <= ct:
                best_title_score = max(best_title_score, 78)
            elif wt:
                inter = wt & ct
                if not inter:
                    sim = SequenceMatcher(None, wanted, cn).ratio()
                    best_title_score = max(best_title_score, int(sim * 55))
                else:
                    recall = len(inter) / len(wt)
                    union = wt | ct
                    jacc = len(inter) / len(union) if union else 0.0
                    best_title_score = max(
                        best_title_score,
                        int(35 + 40 * jacc * recall),
                    )

    score = best_title_score

    fa = str(candidate.get("first_air_date") or "").strip()
    c_year = _year_int_from_release(fa)
    if year_hint is not None and c_year is not None:
        if c_year == year_hint:
            score += 8
        elif abs(c_year - year_hint) > 1:
            score -= 28
        else:
            score -= 10

    if _show_expects_live_action(show) and _TMDB_ANIMATION_GENRE_ID in _genre_ids_from_candidate(candidate):
        score -= 38

    ol = str(candidate.get("original_language") or "").strip().lower()
    if ol and ol not in {"en", ""}:
        score -= 5

    oc = candidate.get("origin_country")
    if isinstance(oc, list) and oc:
        countries = {str(c).upper() for c in oc if c}
        primary = (show.providers[0] if show.providers else "").lower()
        if "us" in countries and ("hbo" in primary or "apple" in primary or "netflix" in primary or "hulu" in primary):
            score += 4

    return max(0, min(100, score))


def _tmdb_find_tv_id_by_imdb(imdb_raw: str, api_key: str, timeout_seconds: float) -> int | None:
    """
    TMDB /find/{imdb_id}?external_source=imdb_id — returns tv_results[].id
    Structure ready for PART 1 step 2; requires show.imdb_id on WatchShow when wired.
    """
    key = (imdb_raw or "").strip()
    if not key:
        return None
    if not key.startswith("tt") and key.isdigit():
        key = f"tt{key}"
    if not key.startswith("tt"):
        return None
    query = urlencode({"api_key": api_key, "external_source": "imdb_id"})
    url = f"https://api.themoviedb.org/3/find/{key}?{query}"
    try:
        data = _http_get_json(url, timeout_seconds=timeout_seconds)
    except Exception as exc:
        logger.debug("TMDB find by IMDb failed: %s", exc)
        return None
    if not isinstance(data, dict):
        return None
    tv_results = data.get("tv_results")
    if not isinstance(tv_results, list) or not tv_results:
        return None
    first = tv_results[0]
    if not isinstance(first, dict):
        return None
    try:
        return int(first.get("id"))
    except (TypeError, ValueError):
        return None


def _tmdb_find_tv_id_by_tvdb(tvdb_raw: str, api_key: str, timeout_seconds: float) -> int | None:
    """TMDB /find/{tvdb_id}?external_source=tvdb_id — returns tv_results[].id"""
    key = (tvdb_raw or "").strip()
    if not key or not key.isdigit():
        return None
    query = urlencode({"api_key": api_key, "external_source": "tvdb_id"})
    url = f"https://api.themoviedb.org/3/find/{key}?{query}"
    try:
        data = _http_get_json(url, timeout_seconds=timeout_seconds)
    except Exception as exc:
        logger.debug("TMDB find by TVDB failed: %s", exc)
        return None
    if not isinstance(data, dict):
        return None
    tv_results = data.get("tv_results")
    if not isinstance(tv_results, list) or not tv_results:
        return None
    first = tv_results[0]
    if not isinstance(first, dict):
        return None
    try:
        return int(first.get("id"))
    except (TypeError, ValueError):
        return None


def _fetch_tmdb_tv_details(tv_id: int, api_key: str, timeout_seconds: float) -> dict | None:
    query = urlencode({"api_key": api_key})
    url = f"https://api.themoviedb.org/3/tv/{tv_id}?{query}"
    try:
        data = _http_get_json(url, timeout_seconds=timeout_seconds)
    except Exception as exc:
        logger.debug("TMDB TV details failed id=%s: %s", tv_id, exc)
        return None
    return data if isinstance(data, dict) else None


def validate_tv_candidate_with_secondary_source(
    show: WatchShow,
    *,
    chosen_name: str,
    chosen_first_air: str,
    confidence_before: int,
    timeout_seconds: float,
) -> tuple[int, list[str]]:
    """
    TVMaze title/year alignment — optional bump or penalty for borderline TMDB hits.
    Does not replace TMDB as primary metadata.
    """
    notes: list[str] = []
    q = normalize_tv_series_title(show.title) or (show.title or "").strip()
    if len(q) < 2:
        return confidence_before, notes
    try:
        params = urlencode({"q": q})
        url = f"https://api.tvmaze.com/search/shows?{params}"
        data = _http_get_json(
            url,
            timeout_seconds=timeout_seconds,
            headers={"User-Agent": "BigDavesNews/1.0 (Watch poster validation)"},
        )
    except Exception as exc:
        notes.append(f"tvmaze_skip:{exc!s}")
        return confidence_before, notes

    if not isinstance(data, list) or not data:
        notes.append("tvmaze_no_results")
        return max(0, confidence_before - 5), notes

    top = data[0]
    if not isinstance(top, dict):
        return confidence_before, notes
    inner = top.get("show")
    if not isinstance(inner, dict):
        return confidence_before, notes
    tvmaze_name = str(inner.get("name") or "").strip()
    tvmaze_prem = str(inner.get("premiered") or "").strip()[:4]
    chosen_y = _year_int_from_release(chosen_first_air)
    maze_y: int | None = int(tvmaze_prem) if tvmaze_prem.isdigit() else None

    mz_norm = normalize_tv_series_title(tvmaze_name)
    ch_norm = normalize_tv_series_title(chosen_name)
    aligned = False
    if mz_norm and ch_norm and (mz_norm == ch_norm or mz_norm in ch_norm or ch_norm in mz_norm):
        aligned = True
    if maze_y and chosen_y and maze_y == chosen_y:
        aligned = True

    if aligned:
        notes.append("tvmaze_aligned")
        return min(100, confidence_before + 10), notes

    notes.append("tvmaze_mismatch")
    return max(0, confidence_before - 18), notes


def _search_tmdb_tv_unique_queries(show: WatchShow, year_hint: int | None) -> list[str]:
    base_title = normalize_tv_series_title(show.title)
    if not base_title:
        return []
    queries: list[str] = []
    if base_title != (show.title or "").strip().lower():
        queries.append(base_title)
    queries.append((show.title or "").strip())

    seen_q: set[str] = set()
    unique_queries: list[str] = []
    for q in queries:
        k = q.strip().lower()
        if not k or k in seen_q:
            continue
        seen_q.add(k)
        unique_queries.append(q.strip())
    return unique_queries


def _run_tv_search_queries(
    unique_queries: list[str],
    show: WatchShow,
    api_key: str,
    timeout_seconds: float,
    *,
    year_hint: int | None,
    notes: list[str],
    into: dict[int, tuple[dict, int]] | None = None,
) -> dict[int, tuple[dict, int]]:
    """Merge TMDB /search/tv hits into into[cid] = (cand, best_score)."""
    bucket = into if into is not None else {}
    for q in unique_queries:
        params = urlencode(
            {
                "api_key": api_key,
                "query": q,
                "include_adult": "false",
            }
        )
        url = f"https://api.themoviedb.org/3/search/tv?{params}"
        try:
            data = _http_get_json(url, timeout_seconds=timeout_seconds)
        except Exception as exc:
            notes.append(f"search_error:{q[:20]}:{exc!s}")
            continue
        if not isinstance(data, dict):
            continue
        results = data.get("results") or []
        if not isinstance(results, list):
            continue
        for cand in results[:20]:
            if not isinstance(cand, dict):
                continue
            try:
                cid = int(cand.get("id"))
            except (TypeError, ValueError):
                continue
            sc = score_tmdb_tv_candidate(show, cand, year_hint=year_hint)
            prev = bucket.get(cid)
            if prev is None or sc > prev[1]:
                bucket[cid] = (cand, sc)
    return bucket


def _search_tmdb_tv_best_candidate(
    show: WatchShow,
    api_key: str,
    timeout_seconds: float,
    *,
    year_hint: int | None,
) -> tuple[dict | None, int, list[str]]:
    """
    /search/tv with per-id best score, optional year-suffixed follow-up, and top-2 margin.
    """
    notes: list[str] = []
    unique_queries = _search_tmdb_tv_unique_queries(show, year_hint)
    if not unique_queries:
        return None, 0, ["empty_title"]

    best_by_id: dict[int, tuple[dict, int]] = {}
    _run_tv_search_queries(
        unique_queries, show, api_key, timeout_seconds, year_hint=year_hint, notes=notes, into=best_by_id
    )

    top_score = max((t[1] for t in best_by_id.values()), default=-1)
    if year_hint and top_score < 82 and (show.title or "").strip():
        yq = f"{(show.title or '').strip()} {year_hint}"
        if yq.lower() not in {q.lower() for q in unique_queries}:
            _run_tv_search_queries([yq], show, api_key, timeout_seconds, year_hint=year_hint, notes=notes, into=best_by_id)

    if not best_by_id:
        return None, 0, notes + ["no_search_results"]

    ranked = sorted(best_by_id.values(), key=lambda x: x[1], reverse=True)
    best_cand, best_score = ranked[0]
    margin = top2_margin_for_show(show)
    if len(ranked) >= 2:
        second_score = ranked[1][1]
        if best_score - second_score < margin and best_score < 92:
            notes.append(f"ambiguous_top2:best={best_score}:second={second_score}:need_margin={margin}")
            return None, best_score, notes

    return best_cand, best_score, notes


def resolve_watch_poster(
    show: WatchShow,
    *,
    api_key: str,
    timeout_seconds: float,
    skip_catalog_fast_path: bool = False,
) -> PosterResolveOutcome:
    """
    Full resolution pipeline. Returns outcome; caller should apply via
    `apply_resolution_to_show` for poster URL and trust fields. TMDB id is
    persisted on the show only via apply when outcome carries an id.
    """
    notes: list[str] = []
    year_hint = _year_int_from_release(show.release_date)

    if not skip_catalog_fast_path:
        cached = try_resolve_from_fresh_catalog_cache(show)
        if cached is not None:
            return _finish(show, cached)

    work = show

    # --- 1) Direct TMDB TV id (ingest title must match TMDB listing) ----------
    while True:
        tv_id = tmdb_tv_id_for_show(work)
        if tv_id is None:
            break
        if not api_key:
            reason = "tmdb_id_but_no_api_key"
            notes.append(reason)
            url = _poster_placeholder_url(work.title)
            outcome = PosterResolveOutcome(
                poster_url=url,
                tmdb_tv_id=tv_id,
                confidence=0,
                resolution_path="placeholder",
                trusted=False,
                rejection_reason=reason,
                debug_notes=notes,
            )
            logger.warning("watch_poster show=%s %s", work.show_id, reason)
            return _finish(work, outcome)
        details = _fetch_tmdb_tv_details(tv_id, api_key, timeout_seconds)
        if not details:
            reason = "tmdb_id_no_poster_art"
            notes.append(reason)
            url = _poster_placeholder_url(work.title)
            logger.warning("watch_poster show=%s %s id=%s", work.show_id, reason, tv_id)
            return _finish(
                work,
                PosterResolveOutcome(
                    poster_url=url,
                    tmdb_tv_id=tv_id,
                    confidence=0,
                    resolution_path="placeholder",
                    trusted=False,
                    rejection_reason=reason,
                    debug_notes=notes,
                ),
            )
        poster = _poster_url_from_path(str(details.get("poster_path") or "").strip())
        name = str(details.get("name") or "").strip()
        fa = str(details.get("first_air_date") or "").strip()
        backdrop = _backdrop_url_from_path(str(details.get("backdrop_path") or "").strip())
        if not poster:
            reason = "tmdb_id_no_poster_art"
            notes.append(reason)
            url = _poster_placeholder_url(work.title)
            logger.warning("watch_poster show=%s %s id=%s", work.show_id, reason, tv_id)
            return _finish(
                work,
                PosterResolveOutcome(
                    poster_url=url,
                    tmdb_tv_id=tv_id,
                    confidence=0,
                    resolution_path="placeholder",
                    trusted=False,
                    rejection_reason=reason,
                    debug_notes=notes,
                ),
            )
        if ingest_titles_coherent_for_poster_mapping(work.title, name):
            return _finish(
                work,
                PosterResolveOutcome(
                    poster_url=poster,
                    tmdb_tv_id=tv_id,
                    confidence=CONFIDENCE_TMDB_TV_ID,
                    resolution_path="tmdb_tv_id",
                    trusted=True,
                    candidate_name=name,
                    candidate_first_air=fa,
                    backdrop_url=backdrop,
                    tmdb_canonical_title=name,
                    tmdb_first_air_date=fa,
                    debug_notes=notes,
                ),
            )
        notes.append("tmdb_id_title_mismatch")
        logger.warning(
            "watch_poster tmdb_id_rejected_title_mismatch show_id=%s tmdb_tv_id=%s ingest=%r tmdb_name=%r",
            work.show_id,
            tv_id,
            (work.title or "")[:80],
            name[:80],
        )
        if (work.show_id or "").strip().startswith("tmdb-"):
            url = _poster_placeholder_url(work.title)
            return _finish(
                work,
                PosterResolveOutcome(
                    poster_url=url,
                    tmdb_tv_id=tv_id,
                    confidence=0,
                    resolution_path="placeholder",
                    trusted=False,
                    rejection_reason="tmdb_embedded_id_title_mismatch",
                    candidate_name=name,
                    candidate_first_air=fa,
                    debug_notes=notes,
                ),
            )
        work = replace(work, tmdb_tv_id=None)

    # --- 2) IMDb external find ------------------------------------------------
    imdb_raw = getattr(work, "imdb_id", None) or ""
    if isinstance(imdb_raw, str) and imdb_raw.strip() and api_key:
        ext_id = _tmdb_find_tv_id_by_imdb(imdb_raw.strip(), api_key, timeout_seconds)
        if ext_id is not None:
            details = _fetch_tmdb_tv_details(ext_id, api_key, timeout_seconds)
            if details:
                poster = _poster_url_from_path(str(details.get("poster_path") or "").strip())
                backdrop = _backdrop_url_from_path(str(details.get("backdrop_path") or "").strip())
                cname = str(details.get("name") or "")
                cfa = str(details.get("first_air_date") or "")
                if poster and ingest_titles_coherent_for_poster_mapping(work.title, cname):
                    return _finish(
                        work,
                        PosterResolveOutcome(
                            poster_url=poster,
                            tmdb_tv_id=ext_id,
                            confidence=CONFIDENCE_TMDB_EXTERNAL_FIND,
                            resolution_path="tmdb_find_imdb",
                            trusted=True,
                            candidate_name=cname,
                            candidate_first_air=cfa,
                            backdrop_url=backdrop,
                            tmdb_canonical_title=cname,
                            tmdb_first_air_date=cfa,
                            debug_notes=notes,
                        ),
                    )
                if poster and not ingest_titles_coherent_for_poster_mapping(work.title, cname):
                    notes.append("tmdb_find_imdb_title_mismatch")
                if not poster:
                    reason = "tmdb_find_imdb_no_poster_art"
                    notes.append(reason)
                    url = _poster_placeholder_url(work.title)
                    logger.warning("watch_poster show=%s %s id=%s", work.show_id, reason, ext_id)
                    return _finish(
                        work,
                        PosterResolveOutcome(
                            poster_url=url,
                            tmdb_tv_id=ext_id,
                            confidence=0,
                            resolution_path="placeholder",
                            trusted=False,
                            rejection_reason=reason,
                            candidate_name=str(details.get("name") or ""),
                            candidate_first_air=str(details.get("first_air_date") or ""),
                            debug_notes=notes,
                        ),
                    )

    # --- 2b) TVDB external find -----------------------------------------------
    tvdb_raw = getattr(work, "tvdb_id", None) or ""
    if isinstance(tvdb_raw, str) and tvdb_raw.strip() and api_key:
        ext_tvdb = _tmdb_find_tv_id_by_tvdb(tvdb_raw.strip(), api_key, timeout_seconds)
        if ext_tvdb is not None:
            details = _fetch_tmdb_tv_details(ext_tvdb, api_key, timeout_seconds)
            if details:
                poster = _poster_url_from_path(str(details.get("poster_path") or "").strip())
                backdrop = _backdrop_url_from_path(str(details.get("backdrop_path") or "").strip())
                cname = str(details.get("name") or "")
                cfa = str(details.get("first_air_date") or "")
                if poster and ingest_titles_coherent_for_poster_mapping(work.title, cname):
                    return _finish(
                        work,
                        PosterResolveOutcome(
                            poster_url=poster,
                            tmdb_tv_id=ext_tvdb,
                            confidence=CONFIDENCE_TMDB_EXTERNAL_FIND,
                            resolution_path="tmdb_find_tvdb",
                            trusted=True,
                            candidate_name=cname,
                            candidate_first_air=cfa,
                            backdrop_url=backdrop,
                            tmdb_canonical_title=cname,
                            tmdb_first_air_date=cfa,
                            debug_notes=notes,
                        ),
                    )
                if poster and not ingest_titles_coherent_for_poster_mapping(work.title, cname):
                    notes.append("tmdb_find_tvdb_title_mismatch")
                if not poster:
                    reason = "tmdb_find_tvdb_no_poster_art"
                    notes.append(reason)
                    url = _poster_placeholder_url(work.title)
                    return _finish(
                        work,
                        PosterResolveOutcome(
                            poster_url=url,
                            tmdb_tv_id=ext_tvdb,
                            confidence=0,
                            resolution_path="placeholder",
                            trusted=False,
                            rejection_reason=reason,
                            candidate_name=cname,
                            candidate_first_air=cfa,
                            debug_notes=notes,
                        ),
                    )

    # --- 3) Strict TMDB TV search ---------------------------------------------
    if not api_key:
        reason = "no_api_key"
        notes.append(reason)
        url = _poster_placeholder_url(work.title)
        outcome = PosterResolveOutcome(
            poster_url=url,
            tmdb_tv_id=None,
            confidence=0,
            resolution_path="placeholder",
            trusted=False,
            rejection_reason=reason,
            debug_notes=notes,
        )
        logger.warning("watch_poster show=%s rejected=%s", work.show_id, reason)
        return _finish(work, outcome)

    cand, raw_search_score, s_notes = _search_tmdb_tv_best_candidate(
        work, api_key, timeout_seconds, year_hint=year_hint
    )
    notes.extend(s_notes)
    if cand is None:
        reason = "no_candidates"
        url = _poster_placeholder_url(work.title)
        outcome = PosterResolveOutcome(
            poster_url=url,
            tmdb_tv_id=None,
            confidence=0,
            resolution_path="rejected",
            trusted=False,
            rejection_reason=reason,
            debug_notes=notes,
        )
        logger.warning("watch_poster show=%s rejected=%s", work.show_id, reason)
        return _finish(work, outcome)

    try:
        cid = int(cand.get("id"))
    except (TypeError, ValueError):
        cid = None
    cname = str(cand.get("name") or "")
    cfa = str(cand.get("first_air_date") or "")

    confidence = raw_search_score
    strict_floor = effective_accept_min_strict(work)
    if BORDERLINE_MIN <= confidence < strict_floor:
        confidence, v_notes = validate_tv_candidate_with_secondary_source(
            work,
            chosen_name=cname,
            chosen_first_air=cfa,
            confidence_before=confidence,
            timeout_seconds=timeout_seconds,
        )
        notes.extend(v_notes)

    if not _effective_accept_search(confidence, work, cand, raw_search_score):
        reason = f"low_confidence:{confidence}"
        notes.append(reason)
        url = _poster_placeholder_url(work.title)
        outcome = PosterResolveOutcome(
            poster_url=url,
            tmdb_tv_id=None,
            confidence=confidence,
            resolution_path="rejected_low_confidence",
            trusted=False,
            candidate_name=cname,
            candidate_first_air=cfa,
            rejection_reason=reason,
            debug_notes=notes,
        )
        logger.warning(
            "watch_poster show=%s rejected=%s candidate=%s conf=%s raw_search=%s",
            work.show_id,
            reason,
            cname,
            confidence,
            raw_search_score,
        )
        return _finish(work, outcome)

    # High confidence — fetch canonical details by id (official poster_path)
    if cid is not None:
        details = _fetch_tmdb_tv_details(cid, api_key, timeout_seconds)
        if details:
            poster = _poster_url_from_path(str(details.get("poster_path") or "").strip())
            backdrop = _backdrop_url_from_path(str(details.get("backdrop_path") or "").strip())
            dname = str(details.get("name") or cname)
            if poster:
                if not ingest_titles_coherent_for_poster_mapping(work.title, dname):
                    notes.append("tmdb_search_detail_title_mismatch")
                    url = _poster_placeholder_url(work.title)
                    return _finish(
                        work,
                        PosterResolveOutcome(
                            poster_url=url,
                            tmdb_tv_id=None,
                            confidence=confidence,
                            resolution_path="rejected_low_confidence",
                            trusted=False,
                            candidate_name=dname,
                            candidate_first_air=str(details.get("first_air_date") or cfa),
                            rejection_reason="tmdb_search_detail_title_mismatch",
                            debug_notes=notes,
                        ),
                    )
                outcome = PosterResolveOutcome(
                    poster_url=poster,
                    tmdb_tv_id=cid,
                    confidence=confidence,
                    resolution_path="tmdb_search",
                    trusted=True,
                    candidate_name=dname,
                    candidate_first_air=str(details.get("first_air_date") or cfa),
                    backdrop_url=backdrop,
                    tmdb_canonical_title=dname,
                    tmdb_first_air_date=str(details.get("first_air_date") or cfa),
                    debug_notes=notes,
                )
                return _finish(work, outcome)

    reason = "detail_fetch_failed"
    url = _poster_placeholder_url(work.title)
    outcome = PosterResolveOutcome(
        poster_url=url,
        tmdb_tv_id=None,
        confidence=confidence,
        resolution_path="rejected",
        trusted=False,
        candidate_name=cname,
        candidate_first_air=cfa,
        rejection_reason=reason,
        debug_notes=notes,
    )
    return _finish(work, outcome)


def classify_watch_poster_failure_mode(
    *,
    api_key_present: bool,
    catalog_row: dict[str, Any] | None,
    outcome: PosterResolveOutcome,
) -> str:
    """
    Operational triage label for inspect / diagnose tooling (not persisted).
    """
    if not api_key_present:
        return "no_api_key"
    if outcome.trusted:
        it = str((catalog_row or {}).get("title") or "").strip()
        res_name = (outcome.tmdb_canonical_title or outcome.candidate_name or "").strip()
        if it and res_name and not ingest_titles_coherent_for_poster_mapping(it, res_name):
            return "trusted_ingest_vs_resolved_name_mismatch"
        ct = str((catalog_row or {}).get("tmdb_canonical_title") or "").strip()
        if it and ct and not ingest_titles_coherent_for_poster_mapping(it, ct):
            if res_name and ingest_titles_coherent_for_poster_mapping(it, res_name):
                return "ok_trusted_db_canon_stale"
            return "catalog_row_title_canon_mismatch"
        return "ok_trusted"
    rr = (outcome.rejection_reason or "").lower()
    if "low_confidence" in rr or outcome.resolution_path == "rejected_low_confidence":
        return "rejected_low_confidence"
    if outcome.resolution_path == "placeholder" and "no_api_key" in rr:
        return "no_api_key"
    if "title_mismatch" in rr:
        return "title_mismatch_rejected"
    if outcome.resolution_path in ("rejected",) and "no_candidates" in rr:
        return "no_search_candidates"
    it = str((catalog_row or {}).get("title") or "").strip()
    ct = str((catalog_row or {}).get("tmdb_canonical_title") or "").strip()
    if it and ct and not ingest_titles_coherent_for_poster_mapping(it, ct):
        return "stale_catalog_title_mismatch"
    return "other"


def apply_resolution_to_show(
    show: WatchShow,
    outcome: PosterResolveOutcome,
    *,
    poster_source_tag: str,
) -> None:
    show.poster_url = outcome.poster_url
    show.poster_source = poster_source_tag
    show.poster_trusted = outcome.trusted
    # Last resolved score (including rejected low-confidence candidates for debugging/UI).
    show.poster_confidence = outcome.confidence
    show.poster_resolution_path = outcome.resolution_path
    if outcome.tmdb_tv_id is not None:
        show.tmdb_tv_id = outcome.tmdb_tv_id
    show.poster_status = poster_status_for_outcome(outcome)
    if outcome.backdrop_url:
        show.tmdb_backdrop_url = outcome.backdrop_url
    if outcome.tmdb_canonical_title:
        show.tmdb_canonical_title = outcome.tmdb_canonical_title
    if outcome.tmdb_first_air_date:
        show.tmdb_catalog_first_air_date = outcome.tmdb_first_air_date
    if outcome.resolution_path != "tmdb_cached" and outcome.trusted:
        show.tmdb_last_refreshed_at = datetime.now(timezone.utc).isoformat()
    if os.getenv("WATCH_POSTER_DEBUG", "").strip().lower() in {"1", "true", "yes"}:
        show.poster_match_debug = outcome.debug_summary()
    else:
        show.poster_match_debug = ""
