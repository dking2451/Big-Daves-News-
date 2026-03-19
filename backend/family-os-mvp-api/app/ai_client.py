import json
import os
from typing import Any, Dict, List

from openai import OpenAI


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
- If date is unclear, set date=null.
- If time is unclear, set startTime=null and endTime=null and set ambiguityFlag=true.
- If either date or time is ambiguous in wording, keep nulls where uncertain.
- Use confidence between 0 and 1.
- Keep candidates concise and useful for parent review.
- If no events are found, return {"candidates": []}.
"""


def get_client() -> OpenAI:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set")
    return OpenAI(api_key=api_key)


def extract_events_with_ai(ocr_text: str, source_hint: str | None = None) -> Dict[str, List[Dict[str, Any]]]:
    client = get_client()
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
    user_prompt = f"Source hint: {source_hint or 'none'}\n\nOCR text:\n{ocr_text}"

    response = client.chat.completions.create(
        model=model,
        temperature=0.1,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
    )

    content = response.choices[0].message.content or '{"candidates":[]}'
    parsed = json.loads(content)
    if not isinstance(parsed, dict) or "candidates" not in parsed:
        return {"candidates": []}
    if not isinstance(parsed["candidates"], list):
        return {"candidates": []}
    return parsed
