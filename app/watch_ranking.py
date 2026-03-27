"""
Watch decision-engine ranking: separate surfaces (Tonight / My List / More Picks),
inspectable weights, recommendation reasons, repetition-aware penalties.

TUNE: All W_* constants and caps below are the primary knobs for product iteration.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any

from app.models import WatchShow
from app.watch import (
    effective_last_air_for_compare,
    effective_next_air_for_schedule,
    watch_release_badge,
)

if TYPE_CHECKING:
    from app.watch_feedback import WatchRepetitionHints

# --- Tonight's Pick weights (TUNE: hero — single best title tonight) ---
W_TONIGHT_PREFERRED_PROVIDER = 25.0
W_TONIGHT_SAVED = 30.0
W_TONIGHT_SIMILAR_TO_SAVED = 20.0
W_TONIGHT_TOP_GENRE = 15.0
W_TONIGHT_NEW_EPISODE_WEEK = 25.0
W_TONIGHT_NEW_SEASON_MONTH = 18.0
W_TONIGHT_CURRENTLY_WATCHING = 18.0
W_TONIGHT_LIKED = 20.0
W_TONIGHT_FINISHED = -40.0
W_TONIGHT_PASSED = -50.0
W_TONIGHT_TRUSTED_POSTER = 10.0
W_TONIGHT_HERO_AGAIN_WITHIN_HOURS = -95.0  # TUNE: strong anti-repeat for hero
W_TONIGHT_TREND_TIEBREAK_SCALE = 0.12  # TUNE: small tie-break from catalog trend_score

# --- From My List (TUNE: saved-only ordering) ---
W_LIST_SAVED_BASE = 40.0
W_LIST_WATCHING = 35.0
W_LIST_NEW_EPISODE = 45.0
W_LIST_FRESH_BOOST = 18.0
W_LIST_PROVIDER_TOP = 12.0
W_LIST_RECENT_SAVE_MAX = 22.0  # decays by age
W_LIST_PASSED = -45.0
W_LIST_FINISHED = -55.0
W_LIST_FINISHED_BUT_NEW_SEASON = 30.0  # offsets finished penalty when season is new
W_LIST_TIER_SCALE = 1000.0  # big buckets for priority bands

# --- More Picks feed (TUNE: breadth + exploration) ---
W_MORE_PROVIDER = 18.0
W_MORE_SAVED_AFFINITY = 22.0
W_MORE_LIKED_STYLE = 12.0
W_MORE_GENRE = 14.0
W_MORE_FRESH = 20.0
W_MORE_TREND = 0.08  # multiplied by trend_score
W_MORE_TRUSTED_POSTER = 8.0
W_MORE_COMMUNITY = 0.5  # per net up-down vote
W_MORE_REPETITION = -18.0  # multiplied by recent surface count
W_MORE_PASSED = -35.0
W_MORE_FINISHED = -30.0
W_MORE_DIV_PROVIDER_CAP = 3  # TUNE: max same primary provider in top N
W_MORE_DIV_GENRE_CAP = 4
W_MORE_DIV_TOP_SLOTS = 14


def _norm_provider(value: str) -> str:
    return str(value or "").strip().lower()


def _norm_genre(value: str) -> str:
    return str(value or "").strip().lower()


def _parse_shown_at(raw: str) -> datetime | None:
    try:
        t = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if t.tzinfo is None:
            t = t.replace(tzinfo=timezone.utc)
        return t.astimezone(timezone.utc)
    except Exception:
        return None


def _franchise_key(title: str) -> str:
    t = (title or "").split(":")[0].strip().lower()
    t = re.sub(r"\s+season\s*\d+.*$", "", t, flags=re.I)
    return "".join(ch for ch in t if ch.isalnum())[:18]


@dataclass
class WatchUserContext:
    """Everything the rankers need beyond the raw WatchShow row."""

    saved_set: set[str]
    saved_meta: dict[str, str]
    watch_progress: dict[str, str]
    user_reactions: dict[str, str]
    caught_up_map: dict[str, str]
    provider_preference_scores: dict[str, float]
    prefs: dict[str, bool]
    vote_stats: dict[str, dict[str, int]]
    show_by_id: dict[str, WatchShow]
    repetition: Any  # WatchRepetitionHints
    now: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    preferred_genres: set[str] = field(default_factory=set)


def build_watch_user_context(
    *,
    saved_set: set[str],
    saved_meta: dict[str, str],
    watch_progress: dict[str, str],
    user_reactions: dict[str, str],
    caught_up_map: dict[str, str],
    provider_preference_scores: dict[str, float],
    prefs: dict[str, bool],
    vote_stats: dict[str, dict[str, int]],
    shows: list[WatchShow],
    repetition: Any,
    now: datetime | None = None,
) -> WatchUserContext:
    show_by_id = {s.show_id: s for s in shows}
    ctx = WatchUserContext(
        saved_set=saved_set,
        saved_meta=saved_meta,
        watch_progress=watch_progress,
        user_reactions=user_reactions,
        caught_up_map=caught_up_map,
        provider_preference_scores=provider_preference_scores,
        prefs=prefs,
        vote_stats=vote_stats,
        show_by_id=show_by_id,
        repetition=repetition,
        now=now or datetime.now(timezone.utc),
        preferred_genres=set(),
    )
    ctx.preferred_genres = _top_genres_from_context(ctx)
    return ctx


@dataclass
class ShowFeatures:
    """Inspectable feature flags + repetition; never exposed raw to clients as a score."""

    is_saved: bool
    is_liked: bool
    is_passed: bool
    watch_state: str
    on_preferred_provider: bool
    similar_to_saved: bool
    genre_is_top_affinity: bool
    new_episode_this_week: bool
    new_season_this_month: bool
    recently_aired: bool
    trending_norm: float
    poster_trusted: bool
    hours_since_hero: float | None
    recent_more_surfaces: int
    has_fresh_after_finished: bool
    community_net: int
    save_recency_days: float | None


def _top_genres_from_context(ctx: WatchUserContext) -> set[str]:
    counts: dict[str, int] = {}
    for show_id in ctx.saved_set:
        show = ctx.show_by_id.get(show_id)
        if not show:
            continue
        for g in getattr(show, "genres", []) or []:
            k = _norm_genre(g)
            if k:
                counts[k] = counts.get(k, 0) + 2
    for show_id, reaction in ctx.user_reactions.items():
        if reaction != "up":
            continue
        show = ctx.show_by_id.get(show_id)
        if not show:
            continue
        for g in getattr(show, "genres", []) or []:
            k = _norm_genre(g)
            if k:
                counts[k] = counts.get(k, 0) + 1
    if not counts:
        return set()
    ordered = sorted(counts.items(), key=lambda x: -x[1])
    top_n = max(1, min(4, len(ordered)))
    threshold = ordered[0][1] * 0.35
    return {k for k, c in ordered[:top_n] if c >= threshold}


def _preferred_provider_keys(scores: dict[str, float]) -> set[str]:
    if not scores:
        return set()
    positives = [(k, v) for k, v in scores.items() if v > 0.5]
    if not positives:
        return set()
    positives.sort(key=lambda x: -x[1])
    return {positives[0][0], *(p[0] for p in positives[1:3] if p[1] >= positives[0][1] * 0.55)}


def _genre_overlap_similarity(show: WatchShow, ctx: WatchUserContext) -> float:
    genres = {_norm_genre(g) for g in getattr(show, "genres", []) or [] if _norm_genre(g)}
    if not genres:
        return 0.0
    best = 0.0
    for sid in ctx.saved_set:
        other = ctx.show_by_id.get(sid)
        if not other or other.show_id == show.show_id:
            continue
        og = {_norm_genre(g) for g in getattr(other, "genres", []) or [] if _norm_genre(g)}
        if not og:
            continue
        inter = genres & og
        union = genres | og
        jacc = len(inter) / max(1, len(union))
        best = max(best, jacc)
    return best


def _season_episode_heavy_new_season(status: str) -> bool:
    s = (status or "").lower()
    if "new season" in s:
        return True
    if re.search(r"\bseason\s*\d+\b", s) and ("new" in s or "weekly" in s):
        return True
    return False


def has_fresh_content_for_user(
    show: WatchShow,
    *,
    is_saved: bool,
    caught_up: str,
    badge: str,
) -> bool:
    """New episode airdate user has not explicitly caught up on, or strong new-season signal."""
    effective_last = effective_last_air_for_compare(show)
    has_new_episode = (
        badge == "new"
        and bool(effective_last)
        and (not is_saved or not caught_up or effective_last > caught_up)
    )
    if has_new_episode:
        return True
    if _season_episode_heavy_new_season(show.season_episode_status):
        if badge in {"new", "this_week", "upcoming"}:
            return True
    return False


def should_hide_finished_show(
    show: WatchShow,
    ctx: WatchUserContext,
    *,
    finished_ids: set[str],
) -> bool:
    """When hide_seen is on: drop finished shows unless there is something new to surface."""
    if show.show_id not in finished_ids:
        return False
    is_saved = show.show_id in ctx.saved_set
    caught = ctx.caught_up_map.get(show.show_id, "")
    badge = watch_release_badge(show)
    if has_fresh_content_for_user(show, is_saved=is_saved, caught_up=caught, badge=badge):
        return False
    return True


def compute_show_features(show: WatchShow, ctx: WatchUserContext) -> ShowFeatures:
    badge = watch_release_badge(show)
    is_saved = show.show_id in ctx.saved_set
    reaction = ctx.user_reactions.get(show.show_id, "")
    is_liked = reaction == "up"
    is_passed = reaction == "down"
    progress = ctx.watch_progress.get(show.show_id, "not_started")
    if progress not in {"watching", "finished"}:
        progress = "not_started"

    caught = ctx.caught_up_map.get(show.show_id, "")
    effective_last = effective_last_air_for_compare(show)
    new_episode_user = (
        is_saved
        and badge == "new"
        and bool(effective_last)
        and (not caught or effective_last > caught)
    )
    new_episode_this_week = badge in {"new", "this_week"} or new_episode_user
    status_lower = (show.season_episode_status or "").lower()
    new_season_this_month = (
        _season_episode_heavy_new_season(show.season_episode_status)
        or "new season" in status_lower
        or ("season" in status_lower and badge in {"new", "this_week"})
    )
    recently_aired = badge == "new"

    pref_prov = _preferred_provider_keys(ctx.provider_preference_scores)
    providers = getattr(show, "providers", []) or []
    on_pref = any(_norm_provider(p) in pref_prov for p in providers) if pref_prov else False

    top_genres = ctx.preferred_genres or _top_genres_from_context(ctx)
    g_show = {_norm_genre(g) for g in getattr(show, "genres", []) or [] if _norm_genre(g)}
    genre_top = bool(g_show & top_genres) if top_genres else False

    sim = _genre_overlap_similarity(show, ctx)
    primary_here = _norm_genre(show.genres[0]) if getattr(show, "genres", None) else ""
    similar_to_saved = sim >= 0.34 or (
        not is_saved
        and primary_here
        and any(
            primary_here == _norm_genre((getattr(ctx.show_by_id.get(sid), "genres", []) or [""])[0])
            for sid in ctx.saved_set
            if ctx.show_by_id.get(sid)
        )
    )

    tmax = max((float(getattr(s, "trend_score", 0.0) or 0.0) for s in ctx.show_by_id.values()), default=1.0)
    trending_norm = min(1.0, max(0.0, float(show.trend_score or 0.0) / max(tmax, 1.0)))

    poster_trusted = bool(getattr(show, "poster_trusted", False))
    pstatus = str(getattr(show, "poster_status", "") or "").strip().lower()
    if pstatus == "trusted":
        poster_trusted = True

    hints = ctx.repetition
    hero_last = hints.hero_last_shown.get(show.show_id) if hints else None
    hours_since_hero: float | None = None
    if hero_last:
        hours_since_hero = (ctx.now - hero_last).total_seconds() / 3600.0
    recent_more = hints.more_pick_counts_48h.get(show.show_id, 0) if hints else 0

    fresh_after_finished = has_fresh_content_for_user(show, is_saved=is_saved, caught_up=caught, badge=badge)

    stats = ctx.vote_stats.get(show.show_id, {"up": 0, "down": 0})
    community_net = int(stats.get("up", 0)) - int(stats.get("down", 0))

    save_recency_days: float | None = None
    if is_saved:
        raw_ts = ctx.saved_meta.get(show.show_id, "")
        dt_save = _parse_shown_at(raw_ts) if raw_ts else None
        if dt_save:
            save_recency_days = max(0.0, (ctx.now - dt_save).total_seconds() / 86400.0)

    return ShowFeatures(
        is_saved=is_saved,
        is_liked=is_liked,
        is_passed=is_passed,
        watch_state=progress,
        on_preferred_provider=on_pref,
        similar_to_saved=similar_to_saved,
        genre_is_top_affinity=genre_top,
        new_episode_this_week=new_episode_this_week,
        new_season_this_month=new_season_this_month,
        recently_aired=recently_aired,
        trending_norm=trending_norm,
        poster_trusted=poster_trusted,
        hours_since_hero=hours_since_hero,
        recent_more_surfaces=recent_more,
        has_fresh_after_finished=fresh_after_finished,
        community_net=community_net,
        save_recency_days=save_recency_days,
    )


def generate_recommendation_reason(show: WatchShow, features: ShowFeatures, ctx: WatchUserContext) -> str:
    """Pick the strongest *positive* signal as human copy (no scores / vague filler)."""
    if features.is_passed:
        return ""
    if features.watch_state == "watching" and features.new_episode_this_week:
        return "Ready to keep watching: new episode"
    if features.watch_state == "watching":
        return "Ready to keep watching"
    if features.new_episode_this_week and features.is_saved:
        return "New episode this week"
    if features.new_episode_this_week:
        return "New episode this week"
    if features.new_season_this_month:
        return "New season to dive into"
    if features.is_saved:
        return "From your saved shows"
    if features.similar_to_saved and ctx.saved_set:
        return "Because it fits your saved shows"
    if features.genre_is_top_affinity and show.genres:
        g = (show.genres[0] or "").strip()
        if g:
            low = g.lower()
            if "thrill" in low:
                return "Because you like thrillers"
            return f"Because you like {low}"
    if features.on_preferred_provider:
        return "Available on your providers"
    if features.is_liked:
        return "Picks up patterns from what you liked"
    if features.recently_aired:
        return "Recently aired"
    if features.trending_norm >= 0.86:
        return "Trending tonight"
    if features.poster_trusted:
        return "Editor-ready details"
    return "Worth a look tonight"


def tonights_eligible(show: WatchShow, ctx: WatchUserContext, features: ShowFeatures) -> bool:
    if features.is_passed:
        return False
    if features.watch_state == "finished" and not features.has_fresh_after_finished:
        return False
    return True


def score_tonights_pick(show: WatchShow, ctx: WatchUserContext, features: ShowFeatures) -> float:
    total, _ = breakdown_tonights_pick(show, features)
    return total


def breakdown_tonights_pick(show: WatchShow, features: ShowFeatures) -> tuple[float, dict[str, float]]:
    """Additive breakdown; mirrors score_tonights_pick (TUNE weights)."""
    b: dict[str, float] = {}
    total = 0.0
    t = float(show.trend_score or 0.0) * W_TONIGHT_TREND_TIEBREAK_SCALE
    b["trend_tiebreak"] = t
    total += t
    if features.on_preferred_provider:
        b["provider_fit"] = W_TONIGHT_PREFERRED_PROVIDER
        total += W_TONIGHT_PREFERRED_PROVIDER
    else:
        b["provider_fit"] = 0.0
    if features.is_saved:
        b["saved_direct"] = W_TONIGHT_SAVED
        total += W_TONIGHT_SAVED
    else:
        b["saved_direct"] = 0.0
    if features.similar_to_saved:
        b["saved_similar"] = W_TONIGHT_SIMILAR_TO_SAVED
        total += W_TONIGHT_SIMILAR_TO_SAVED
    else:
        b["saved_similar"] = 0.0
    if features.genre_is_top_affinity:
        b["genre_affinity"] = W_TONIGHT_TOP_GENRE
        total += W_TONIGHT_TOP_GENRE
    else:
        b["genre_affinity"] = 0.0
    if features.new_episode_this_week:
        b["freshness_new_episode"] = W_TONIGHT_NEW_EPISODE_WEEK
        total += W_TONIGHT_NEW_EPISODE_WEEK
    else:
        b["freshness_new_episode"] = 0.0
    if features.new_season_this_month:
        b["freshness_new_season"] = W_TONIGHT_NEW_SEASON_MONTH
        total += W_TONIGHT_NEW_SEASON_MONTH
    else:
        b["freshness_new_season"] = 0.0
    if features.watch_state == "watching":
        b["urgency_watching"] = W_TONIGHT_CURRENTLY_WATCHING
        total += W_TONIGHT_CURRENTLY_WATCHING
    else:
        b["urgency_watching"] = 0.0
    if features.is_liked:
        b["engagement_liked"] = W_TONIGHT_LIKED
        total += W_TONIGHT_LIKED
    else:
        b["engagement_liked"] = 0.0
    if features.watch_state == "finished":
        b["penalty_finished"] = W_TONIGHT_FINISHED
        total += W_TONIGHT_FINISHED
    else:
        b["penalty_finished"] = 0.0
    if features.is_passed:
        b["penalty_passed"] = W_TONIGHT_PASSED
        total += W_TONIGHT_PASSED
    else:
        b["penalty_passed"] = 0.0
    if features.poster_trusted:
        b["metadata_trusted_poster"] = W_TONIGHT_TRUSTED_POSTER
        total += W_TONIGHT_TRUSTED_POSTER
    else:
        b["metadata_trusted_poster"] = 0.0
    if features.hours_since_hero is not None and features.hours_since_hero < 24:
        b["penalty_repetition_hero_24h"] = W_TONIGHT_HERO_AGAIN_WITHIN_HOURS
        total += W_TONIGHT_HERO_AGAIN_WITHIN_HOURS
    else:
        b["penalty_repetition_hero_24h"] = 0.0
    return total, b


def explain_tonight_ineligible(features: ShowFeatures) -> str | None:
    if features.is_passed:
        return "passed"
    if features.watch_state == "finished" and not features.has_fresh_after_finished:
        return "finished_no_fresh_content"
    return None


def rank_tonights_pick_with_exclusions(
    shows: list[WatchShow],
    ctx: WatchUserContext,
) -> tuple[list[tuple[float, WatchShow, ShowFeatures]], list[dict[str, str]]]:
    ranked: list[tuple[float, WatchShow, ShowFeatures]] = []
    excluded: list[dict[str, str]] = []
    for show in shows:
        feat = compute_show_features(show, ctx)
        if not tonights_eligible(show, ctx, feat):
            reason = explain_tonight_ineligible(feat) or "not_eligible"
            excluded.append(
                {
                    "show_id": show.show_id,
                    "title": show.title,
                    "excluded_reason": reason,
                }
            )
            continue
        sc = score_tonights_pick(show, ctx, feat)
        ranked.append((sc, show, feat))
    ranked.sort(key=lambda x: x[0], reverse=True)
    return ranked, excluded


def rank_tonights_pick(
    shows: list[WatchShow],
    ctx: WatchUserContext,
) -> list[tuple[float, WatchShow, ShowFeatures]]:
    ranked, _ = rank_tonights_pick_with_exclusions(shows, ctx)
    return ranked


def _list_priority_tier(features: ShowFeatures, show: WatchShow, badge: str) -> int:
    """Lower tier number = higher priority (1 best)."""
    watching = features.watch_state == "watching"
    finished = features.watch_state == "finished"
    new_ep = features.new_episode_this_week
    if watching and new_ep:
        return 1
    if watching:
        return 2
    if features.is_saved and new_ep:
        return 3
    next_air = effective_next_air_for_schedule(show)
    available_now = bool(next_air) or badge == "new" or "stream" in (show.season_episode_status or "").lower()
    recent_save = features.save_recency_days is not None and features.save_recency_days <= 14
    if features.is_saved and recent_save and available_now:
        return 4
    if features.is_saved:
        return 5
    if finished and (new_ep or features.new_season_this_month):
        return 6
    return 7


def score_from_your_list(show: WatchShow, ctx: WatchUserContext, features: ShowFeatures) -> float:
    total, _ = breakdown_from_your_list(show, ctx, features)
    return total


def breakdown_from_your_list(show: WatchShow, ctx: WatchUserContext, features: ShowFeatures) -> tuple[float, dict[str, float]]:
    badge = watch_release_badge(show)
    tier = _list_priority_tier(features, show, badge)
    b: dict[str, float] = {}
    total = 0.0
    band = W_LIST_TIER_SCALE * float(8 - tier)
    b["list_priority_tier"] = float(tier)
    b["list_tier_band"] = band
    total += band
    if features.is_saved:
        b["saved_base"] = W_LIST_SAVED_BASE
        total += W_LIST_SAVED_BASE
    else:
        b["saved_base"] = 0.0
    if features.watch_state == "watching":
        b["urgency_watching"] = W_LIST_WATCHING
        total += W_LIST_WATCHING
    else:
        b["urgency_watching"] = 0.0
    if features.new_episode_this_week:
        b["freshness_new_episode"] = W_LIST_NEW_EPISODE
        total += W_LIST_NEW_EPISODE
    else:
        b["freshness_new_episode"] = 0.0
    if features.new_season_this_month or features.recently_aired:
        b["freshness_boost"] = W_LIST_FRESH_BOOST
        total += W_LIST_FRESH_BOOST
    else:
        b["freshness_boost"] = 0.0
    if features.on_preferred_provider:
        b["provider_fit"] = W_LIST_PROVIDER_TOP
        total += W_LIST_PROVIDER_TOP
    else:
        b["provider_fit"] = 0.0
    if features.save_recency_days is not None:
        rec = W_LIST_RECENT_SAVE_MAX * max(0.0, 1.0 - min(features.save_recency_days, 21.0) / 21.0)
        b["save_recency_boost"] = rec
        total += rec
    else:
        b["save_recency_boost"] = 0.0
    if features.is_passed:
        b["penalty_passed"] = W_LIST_PASSED
        total += W_LIST_PASSED
    else:
        b["penalty_passed"] = 0.0
    if features.watch_state == "finished":
        b["penalty_finished"] = W_LIST_FINISHED
        total += W_LIST_FINISHED
        if features.new_season_this_month or features.has_fresh_after_finished:
            b["offset_finished_new_season"] = W_LIST_FINISHED_BUT_NEW_SEASON
            total += W_LIST_FINISHED_BUT_NEW_SEASON
        else:
            b["offset_finished_new_season"] = 0.0
    else:
        b["penalty_finished"] = 0.0
        b["offset_finished_new_season"] = 0.0
    tnorm = features.trending_norm * 6.0
    b["engagement_trend_norm"] = tnorm
    total += tnorm
    return total, b


def rank_from_your_list(
    saved_shows: list[WatchShow],
    ctx: WatchUserContext,
) -> list[tuple[float, WatchShow, ShowFeatures]]:
    out: list[tuple[float, WatchShow, ShowFeatures]] = []
    for show in saved_shows:
        feat = compute_show_features(show, ctx)
        sc = score_from_your_list(show, ctx, feat)
        out.append((sc, show, feat))
    out.sort(key=lambda x: x[0], reverse=True)
    return out


def score_more_picks(show: WatchShow, ctx: WatchUserContext, features: ShowFeatures) -> float:
    total, _ = breakdown_more_picks(show, features)
    return total


def breakdown_more_picks(show: WatchShow, features: ShowFeatures) -> tuple[float, dict[str, float]]:
    b: dict[str, float] = {}
    total = 0.0
    if features.on_preferred_provider:
        b["provider_fit"] = W_MORE_PROVIDER
        total += W_MORE_PROVIDER
    else:
        b["provider_fit"] = 0.0
    if features.is_saved:
        b["saved_affinity_saved"] = W_MORE_SAVED_AFFINITY
        total += W_MORE_SAVED_AFFINITY
    else:
        b["saved_affinity_saved"] = 0.0
    if features.is_liked:
        b["engagement_liked"] = W_MORE_LIKED_STYLE
        total += W_MORE_LIKED_STYLE
    else:
        b["engagement_liked"] = 0.0
    if features.similar_to_saved:
        sim = W_MORE_SAVED_AFFINITY * 0.55
        b["saved_affinity_similar"] = sim
        total += sim
    else:
        b["saved_affinity_similar"] = 0.0
    if features.genre_is_top_affinity:
        b["genre_affinity"] = W_MORE_GENRE
        total += W_MORE_GENRE
    else:
        b["genre_affinity"] = 0.0
    if features.new_episode_this_week or features.new_season_this_month:
        b["freshness"] = W_MORE_FRESH
        total += W_MORE_FRESH
    else:
        b["freshness"] = 0.0
    tt = float(show.trend_score or 0.0) * W_MORE_TREND
    b["trend_catalog"] = tt
    total += tt
    if features.poster_trusted:
        b["metadata_trusted_poster"] = W_MORE_TRUSTED_POSTER
        total += W_MORE_TRUSTED_POSTER
    else:
        b["metadata_trusted_poster"] = 0.0
    comm = max(-8.0, min(12.0, float(features.community_net) * W_MORE_COMMUNITY))
    b["engagement_community"] = comm
    total += comm
    if features.recent_more_surfaces:
        rep = W_MORE_REPETITION * min(3, features.recent_more_surfaces)
        b["penalty_repetition_feed"] = rep
        total += rep
    else:
        b["penalty_repetition_feed"] = 0.0
    if features.hours_since_hero is not None and features.hours_since_hero < 18:
        h = W_MORE_REPETITION * 0.5
        b["penalty_repetition_hero_recent"] = h
        total += h
    else:
        b["penalty_repetition_hero_recent"] = 0.0
    if features.is_passed:
        b["penalty_passed"] = W_MORE_PASSED
        total += W_MORE_PASSED
    else:
        b["penalty_passed"] = 0.0
    if features.watch_state == "finished" and not features.has_fresh_after_finished:
        b["penalty_finished"] = W_MORE_FINISHED
        total += W_MORE_FINISHED
    else:
        b["penalty_finished"] = 0.0
    return total, b


def recommendation_reason_key(show: WatchShow, features: ShowFeatures, ctx: WatchUserContext) -> tuple[str, str]:
    """(machine_key, same user-facing string as generate_recommendation_reason)."""
    text = generate_recommendation_reason(show, features, ctx)
    if features.is_passed:
        return ("passed", text)
    if features.watch_state == "watching" and features.new_episode_this_week:
        return ("watching_new_episode", text)
    if features.watch_state == "watching":
        return ("watching_continue", text)
    if features.new_episode_this_week and features.is_saved:
        return ("new_episode_saved", text)
    if features.new_episode_this_week:
        return ("new_episode", text)
    if features.new_season_this_month:
        return ("new_season", text)
    if features.is_saved:
        return ("saved", text)
    if features.similar_to_saved and ctx.saved_set:
        return ("similar_to_saved", text)
    if features.genre_is_top_affinity and show.genres:
        return ("genre_affinity", text)
    if features.on_preferred_provider:
        return ("provider_fit", text)
    if features.is_liked:
        return ("liked_pattern", text)
    if features.recently_aired:
        return ("recently_aired", text)
    if features.trending_norm >= 0.86:
        return ("trending_high", text)
    if features.poster_trusted:
        return ("metadata_trusted", text)
    return ("default", text)


def apply_diversity_more_picks(
    ranked: list[tuple[float, WatchShow, ShowFeatures]],
    *,
    limit: int,
    top_slots: int = W_MORE_DIV_TOP_SLOTS,
    provider_cap: int = W_MORE_DIV_PROVIDER_CAP,
    genre_cap: int = W_MORE_DIV_GENRE_CAP,
) -> list[tuple[float, WatchShow, ShowFeatures]]:
    """Re-order top results to limit provider / genre / franchise echo."""
    if not ranked:
        return []
    selected: list[tuple[float, WatchShow, ShowFeatures]] = []
    prov_counts: dict[str, int] = {}
    genre_counts: dict[str, int] = {}
    franchise_seen: set[str] = set()
    pool = list(ranked)

    def primary_provider(sh: WatchShow) -> str:
        p = (sh.providers[0] if getattr(sh, "providers", None) else "") or ""
        return _norm_provider(p) or "unknown"

    def primary_genre(sh: WatchShow) -> str:
        g = (sh.genres[0] if getattr(sh, "genres", None) else "") or ""
        return _norm_genre(g) or "unknown"

    while pool and len(selected) < limit:
        slot = len(selected)
        cap_p = provider_cap + (1 if slot < 3 else 0)
        cap_g = genre_cap + (1 if slot < 4 else 0)
        pick_idx: int | None = None
        for i, triple in enumerate(pool):
            _sc, show, _feat = triple
            pk = primary_provider(show)
            gk = primary_genre(show)
            fk = _franchise_key(show.title)
            if slot < top_slots:
                if prov_counts.get(pk, 0) >= cap_p:
                    continue
                if genre_counts.get(gk, 0) >= cap_g:
                    continue
                if fk and fk in franchise_seen and slot < 8:
                    continue
            pick_idx = i
            break
        if pick_idx is None:
            pick_idx = 0
        triple = pool.pop(pick_idx)
        _, show, _ = triple
        pk = primary_provider(show)
        gk = primary_genre(show)
        fk = _franchise_key(show.title)
        prov_counts[pk] = prov_counts.get(pk, 0) + 1
        genre_counts[gk] = genre_counts.get(gk, 0) + 1
        if fk:
            franchise_seen.add(fk)
        selected.append(triple)
    return selected


def rank_more_picks(
    shows: list[WatchShow],
    ctx: WatchUserContext,
    *,
    limit: int,
) -> tuple[list[tuple[float, WatchShow, ShowFeatures]], list[tuple[float, WatchShow, ShowFeatures]]]:
    scored: list[tuple[float, WatchShow, ShowFeatures]] = []
    for show in shows:
        feat = compute_show_features(show, ctx)
        sc = score_more_picks(show, ctx, feat)
        scored.append((sc, show, feat))
    scored.sort(key=lambda x: x[0], reverse=True)
    pre_diversity = list(scored)
    selected = apply_diversity_more_picks(scored, limit=limit)
    return selected, pre_diversity
