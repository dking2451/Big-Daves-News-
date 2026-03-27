"""
Watch rank debug payloads (development / tuning). Gated by env + query in main.
"""

from __future__ import annotations

from typing import Any

from app.models import WatchShow
from app.watch_ranking import (
    ShowFeatures,
    WatchUserContext,
    breakdown_from_your_list,
    breakdown_more_picks,
    breakdown_tonights_pick,
    recommendation_reason_key,
)


def collect_context_debug_labels(ctx: WatchUserContext) -> list[str]:
    labels: list[str] = []
    if not ctx.saved_set and not any(v == "up" for v in ctx.user_reactions.values()):
        labels.append("cold_start")
    if len(ctx.saved_set) <= 1 and len(ctx.user_reactions) <= 1:
        labels.append("sparse_history")
    if not ctx.provider_preference_scores and not ctx.saved_set:
        labels.append("no_inferred_provider_prefs")
    down = sum(1 for v in ctx.user_reactions.values() if v == "down")
    if down >= 8:
        labels.append("many_passed")
    if sum(1 for v in ctx.watch_progress.values() if v == "finished") >= 12:
        labels.append("heavy_finished_history")
    # Heuristic: user has prefs but no catalog show matches inferred providers
    if ctx.saved_set and ctx.provider_preference_scores:
        any_match = False
        for show in ctx.show_by_id.values():
            provs = getattr(show, "providers", []) or []
            keys = {str(p).strip().lower() for p in provs}
            if keys & set(ctx.provider_preference_scores.keys()):
                any_match = True
                break
        if not any_match:
            labels.append("provider_limited_vs_catalog")
    return labels


def summarize_top_factors(flat: dict[str, float], *, n: int = 6) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    pos = [(k, v) for k, v in flat.items() if v > 0.001]
    neg = [(k, v) for k, v in flat.items() if v < -0.001]
    pos.sort(key=lambda x: -x[1])
    neg.sort(key=lambda x: x[1])
    out_p = [{"key": k, "value": round(v, 3)} for k, v in pos[:n]]
    out_n = [{"key": k, "value": round(v, 3)} for k, v in neg[:n]]
    return out_p, out_n


def _rollup_tonight(flat: dict[str, float]) -> dict[str, float]:
    return {
        "provider_fit": flat.get("provider_fit", 0.0),
        "saved_affinity": flat.get("saved_direct", 0.0) + flat.get("saved_similar", 0.0),
        "genre_affinity": flat.get("genre_affinity", 0.0),
        "freshness": flat.get("freshness_new_episode", 0.0) + flat.get("freshness_new_season", 0.0),
        "urgency": flat.get("urgency_watching", 0.0),
        "engagement": flat.get("engagement_liked", 0.0),
        "metadata_confidence_score": 1.0 if flat.get("metadata_trusted_poster", 0.0) > 0 else 0.35,
        "repetition_penalty": flat.get("penalty_repetition_hero_24h", 0.0),
        "trend_tiebreak": flat.get("trend_tiebreak", 0.0),
        "penalties_other": flat.get("penalty_finished", 0.0) + flat.get("penalty_passed", 0.0),
    }


def _rollup_list(flat: dict[str, float]) -> dict[str, float]:
    return {
        "provider_fit": flat.get("provider_fit", 0.0),
        "saved_affinity": flat.get("saved_base", 0.0) + flat.get("save_recency_boost", 0.0),
        "genre_affinity": 0.0,
        "freshness": flat.get("freshness_new_episode", 0.0) + flat.get("freshness_boost", 0.0),
        "urgency": flat.get("urgency_watching", 0.0),
        "engagement": flat.get("engagement_trend_norm", 0.0),
        "list_tier_band": flat.get("list_tier_band", 0.0),
        "repetition_penalty": 0.0,
        "penalties_other": flat.get("penalty_passed", 0.0) + flat.get("penalty_finished", 0.0) + flat.get("offset_finished_new_season", 0.0),
    }


def _rollup_more(flat: dict[str, float]) -> dict[str, float]:
    return {
        "provider_fit": flat.get("provider_fit", 0.0),
        "saved_affinity": flat.get("saved_affinity_saved", 0.0) + flat.get("saved_affinity_similar", 0.0),
        "genre_affinity": flat.get("genre_affinity", 0.0),
        "freshness": flat.get("freshness", 0.0),
        "urgency": 0.0,
        "engagement": flat.get("engagement_liked", 0.0) + flat.get("engagement_community", 0.0),
        "metadata_confidence_score": 1.0 if flat.get("metadata_trusted_poster", 0.0) > 0 else 0.35,
        "repetition_penalty": flat.get("penalty_repetition_feed", 0.0) + flat.get("penalty_repetition_hero_recent", 0.0),
        "trend_catalog": flat.get("trend_catalog", 0.0),
        "penalties_other": flat.get("penalty_passed", 0.0) + flat.get("penalty_finished", 0.0),
    }


def _diversity_meta(
    show_id: str,
    pre: list[tuple[float, WatchShow, ShowFeatures]],
    post: list[tuple[float, WatchShow, ShowFeatures]],
) -> tuple[int, str]:
    ids_pre = [t[1].show_id for t in pre]
    ids_post = [t[1].show_id for t in post]
    try:
        i_pre = ids_pre.index(show_id)
        i_post = ids_post.index(show_id)
    except ValueError:
        return 0, ""
    delta = i_post - i_pre
    if delta == 0:
        return 0, ""
    if delta > 0:
        return delta, f"demoted_{delta}_slots_for_diversity_mix"
    return delta, f"promoted_{-delta}_slots_after_diversity"


def build_per_item_rank_debug(
    surface: str,
    show: WatchShow,
    ctx: WatchUserContext,
    feat: ShowFeatures,
    rank_score: float,
    *,
    pre_diversity_order: list[tuple[float, WatchShow, ShowFeatures]] | None = None,
    post_diversity_order: list[tuple[float, WatchShow, ShowFeatures]] | None = None,
) -> dict[str, Any]:
    key, _reason_copy = recommendation_reason_key(show, feat, ctx)
    catalog_trend = round(float(show.trend_score or 0.0), 3)
    if surface == "tonight_pick":
        final, flat = breakdown_tonights_pick(show, feat)
        rollup = _rollup_tonight(flat)
    elif surface == "from_your_list":
        final, flat = breakdown_from_your_list(show, ctx, feat)
        rollup = _rollup_list(flat)
    else:
        final, flat = breakdown_more_picks(show, feat)
        rollup = _rollup_more(flat)

    top_pos, top_neg = summarize_top_factors(flat)
    div_delta = 0
    div_note = ""
    if surface == "more_picks" and pre_diversity_order is not None and post_diversity_order is not None:
        div_delta, div_note = _diversity_meta(show.show_id, pre_diversity_order, post_diversity_order)

    return {
        "surface": surface,
        "show_id": show.show_id,
        "title": show.title,
        "rank_score": round(rank_score, 3),
        "trend_score": catalog_trend,
        "watch_state": feat.watch_state,
        "is_saved": feat.is_saved,
        "is_liked": feat.is_liked,
        "is_passed": feat.is_passed,
        "final_computed_score": round(final, 3),
        "rollup_scores": {k: round(float(v), 3) for k, v in rollup.items()},
        "components_flat": {k: round(float(v), 4) for k, v in flat.items()},
        "top_positive_factors": top_pos,
        "top_penalties": top_neg,
        "recommendation_reason_key": key,
        "diversity_rank_delta": div_delta,
        "diversity_note": div_note,
    }


def build_tonight_hero_debug(
    ranked: list[tuple[float, WatchShow, ShowFeatures]],
    excluded: list[dict[str, str]],
    ctx: WatchUserContext,
    *,
    winner_score: float,
    winner_show: WatchShow,
    winner_feat: ShowFeatures,
) -> dict[str, Any]:
    win_debug = build_per_item_rank_debug(
        "tonight_pick",
        winner_show,
        ctx,
        winner_feat,
        winner_score,
    )
    runner_ups: list[dict[str, Any]] = []
    for sc, sh, ft in ranked[1:4]:
        _final, flat = breakdown_tonights_pick(sh, ft)
        gap = round(sc - winner_score, 3)
        rkey, _ = recommendation_reason_key(sh, ft, ctx)
        runner_ups.append(
            {
                "show_id": sh.show_id,
                "title": sh.title,
                "rank_score": round(sc, 3),
                "gap_vs_winner": gap,
                "top_positive_factors": summarize_top_factors(flat)[0][:4],
                "top_penalties": summarize_top_factors(flat)[1][:4],
                "recommendation_reason_key": rkey,
                "why_below_winner": _why_below_tonight(winner_feat, ft, flat),
            }
        )

    excl_sample = excluded[:14]
    return {
        "chosen": win_debug,
        "runner_ups": runner_ups,
        "excluded_count": len(excluded),
        "excluded_sample": excl_sample,
    }


def _why_below_tonight(
    wf: ShowFeatures,
    rf: ShowFeatures,
    runner_flat: dict[str, float],
) -> str:
    if runner_flat.get("penalty_repetition_hero_24h", 0) < -0.01:
        return "runner_hero_repetition_penalty"
    if wf.is_saved and not rf.is_saved:
        return "winner_saved_runner_not"
    if wf.watch_state == "watching" and rf.watch_state != "watching":
        return "winner_watching_runner_not"
    if wf.new_episode_this_week and not rf.new_episode_this_week:
        return "winner_stronger_freshness_signal"
    if wf.is_liked and not rf.is_liked:
        return "winner_liked_engagement"
    return "compare_components_flat_and_rollups"
