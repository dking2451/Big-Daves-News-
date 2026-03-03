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
