import json
import os
from typing import Any, Dict, List

from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()


SYSTEM_PROMPT = """You extract family schedule events from OCR text.
Return only valid JSON with this top-level shape:
{
  "candidates": [
    {
      "title": "string",
      "childName": "string",
      "category": "school|sports|medical|social|other",
      "date": "YYYY-MM-DD or null",
      "startTime": "HH:mm or null",
      "endTime": "HH:mm or null",
      "location": "string",
      "notes": "string",
      "confidence": 0.0,
      "ambiguityFlag": false
    }
  ]
}

Rules:
- Never invent structured certainty.
- Dates must be ISO "YYYY-MM-DD" when you can infer them. Do NOT leave date=null when the text gives a month and day (or full date) for that row.
- If the flyer or title includes a school/sports year (e.g. "Schedule 2026", "Fall 2026"), use that year for any dates written without a year (e.g. "September 13" -> 2026-09-13 if 2026 is established in the same document).
- If only one full date includes the year (e.g. "Monday, September 8, 2026"), assume later month/day-only lines in the same season are the same year unless the text contradicts.
- If the text lists several game days ("September 13, September 20, October 4"), output one candidate per day with date set and times/locations from the nearest sentence (home vs away if distinguished).
- If time is unclear, set startTime=null and endTime=null and set ambiguityFlag=true.
- If either date or time is ambiguous in wording, keep nulls where uncertain.
- Use confidence between 0 and 1.
- Keep candidates concise and useful for parent review.
- For recurring schedules ("every Monday and Wednesday"), you may output one row per pattern with notes, or separate rows for the first few occurrences if specific dates are given.
- If no events are found, return {"candidates": []}.
"""


def get_client() -> OpenAI:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set")
    return OpenAI(api_key=api_key)


def extract_events_with_ai(ocr_text: str, source_hint: str | None = None) -> Dict[str, List[Dict[str, Any]]]:
    client = get_client()
    primary_model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    candidate_models = [primary_model, "gpt-4o-mini", "gpt-4.1-mini"]
    user_prompt = f"Source hint: {source_hint or 'none'}\n\nOCR text:\n{ocr_text}"
    errors: list[str] = []

    for model in _dedupe(candidate_models):
        try:
            response = client.chat.completions.create(
                model=model,
                temperature=0.1,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_prompt},
                ],
            )
            content = response.choices[0].message.content or '{"candidates":[]}'
            parsed = _parse_json_object(content)
            if not isinstance(parsed, dict) or "candidates" not in parsed:
                return {"candidates": []}
            if not isinstance(parsed["candidates"], list):
                return {"candidates": []}
            return parsed
        except Exception as exc:
            errors.append(f"{model}: {exc}")

    raise RuntimeError("OpenAI extraction failed for all models: " + " | ".join(errors))


def _parse_json_object(text: str) -> Dict[str, Any]:
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    # Fallback if model wraps JSON with prose or code fences.
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        snippet = text[start : end + 1]
        parsed = json.loads(snippet)
        if isinstance(parsed, dict):
            return parsed
    return {"candidates": []}


def _dedupe(values: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        if value not in seen:
            seen.add(value)
            result.append(value)
    return result
