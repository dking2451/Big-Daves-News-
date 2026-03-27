from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import List


@dataclass
class SourceConfig:
    name: str
    tier: int
    trust_score: float
    rss: str
    topic: str = "general"


@dataclass
class Article:
    source_name: str
    title: str
    url: str
    summary: str
    image_url: str | None = None
    published_at: datetime | None = None


@dataclass
class ClaimEvidence:
    source_name: str
    source_tier: int
    source_trust_score: float
    article_title: str
    article_url: str
    published_at: datetime | None = None


@dataclass
class Claim:
    claim_id: str
    text: str
    category: str = "World News"
    subtopic: str = "General"
    image_url: str | None = None
    evidence: List[ClaimEvidence] = field(default_factory=list)
    status: str = "unconfirmed"
    confidence: str = "Low"
    first_seen: datetime | None = None


@dataclass
class WatchShow:
    show_id: str
    title: str
    poster_url: str
    synopsis: str
    poster_source: str = "original"
    providers: List[str] = field(default_factory=list)
    genres: List[str] = field(default_factory=list)
    release_date: str = ""
    last_episode_air_date: str = ""
    next_episode_air_date: str = ""
    season_episode_status: str = ""
    trend_score: float = 0.0
    tmdb_tv_id: int | None = None
    imdb_id: str | None = None
    tvdb_id: str | None = None
    poster_trusted: bool | None = None
    poster_confidence: int | None = None
    poster_resolution_path: str = ""
    poster_match_debug: str = ""
    # API contract: trusted | missing | unresolved_low_confidence | unverified_remote
    poster_status: str = ""
    # TMDB cache (from watch_catalog merge; not curated copy)
    tmdb_backdrop_url: str = ""
    tmdb_last_refreshed_at: str = ""
    tmdb_canonical_title: str = ""
    tmdb_catalog_first_air_date: str = ""
