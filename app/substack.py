from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import List

import feedparser


@dataclass
class SubstackSource:
    name: str
    rss: str


@dataclass
class SubstackPost:
    publication: str
    title: str
    url: str
    published: str | None = None


def load_substack_sources(config_path: str = "data/substack_sources.json") -> List[SubstackSource]:
    path = Path(config_path)
    if not path.exists():
        return []

    payload = json.loads(path.read_text())
    return [SubstackSource(**item) for item in payload.get("sources", [])]


def list_substack_publications() -> List[str]:
    return [source.name for source in load_substack_sources()]


def fetch_latest_substack_posts(
    per_source_limit: int = 5,
    total_limit: int = 25,
    publication: str | None = None,
) -> List[SubstackPost]:
    posts: List[SubstackPost] = []
    for source in load_substack_sources():
        if publication and source.name != publication:
            continue
        parsed = feedparser.parse(source.rss)
        for entry in parsed.entries[:per_source_limit]:
            posts.append(
                SubstackPost(
                    publication=source.name,
                    title=getattr(entry, "title", "").strip(),
                    url=getattr(entry, "link", "").strip(),
                    published=getattr(entry, "published", None),
                )
            )

    return posts[:total_limit]
