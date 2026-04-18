"""OpenAI chat helper with JSON extraction (shared with legacy ai_client patterns)."""

from __future__ import annotations

import json
import os
from typing import Any, Dict, List

from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()


def get_openai_client() -> OpenAI:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set")
    return OpenAI(api_key=api_key)


def _dedupe(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for v in values:
        if v not in seen:
            seen.add(v)
            out.append(v)
    return out


def parse_json_object(text: str) -> Dict[str, Any]:
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        try:
            parsed = json.loads(text[start : end + 1])
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass
    return {}


def chat_json(
    *,
    system: str,
    user: str,
    temperature: float = 0.1,
) -> Dict[str, Any]:
    client = get_openai_client()
    primary = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    models = _dedupe([primary, "gpt-4o-mini", "gpt-4.1-mini"])
    errors: List[str] = []
    for model in models:
        try:
            response = client.chat.completions.create(
                model=model,
                temperature=temperature,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
            )
            content = response.choices[0].message.content or "{}"
            return parse_json_object(content)
        except Exception as exc:
            errors.append(f"{model}: {exc}")
    raise RuntimeError("OpenAI extraction failed for all models: " + " | ".join(errors))
