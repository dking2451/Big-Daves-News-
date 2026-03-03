from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Tuple

from app.models import SourceConfig
from app.source_management import load_custom_sources


def load_sources(config_path: str = "data/sources.json") -> Tuple[List[SourceConfig], Dict[str, Any]]:
    path = Path(config_path)
    if not path.exists():
        raise FileNotFoundError(f"Source config not found at {config_path}")

    data = json.loads(path.read_text())
    base_sources = [SourceConfig(**source) for source in data.get("sources", [])]
    custom_sources = load_custom_sources()
    deduped: dict[str, SourceConfig] = {}
    for source in [*base_sources, *custom_sources]:
        deduped[source.rss] = source
    source_configs = list(deduped.values())
    policy = data.get("validation_policy", {})
    return source_configs, policy
