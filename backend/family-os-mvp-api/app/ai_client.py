import json
import os
from datetime import date
from typing import Any, Dict, List

from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()


SYSTEM_PROMPT = """You extract family schedule events from OCR text for a calendar app.
Return only valid JSON with this top-level shape:
{
  "candidates": [
    {
      "title": "string",
      "childName": "string",
      "childNeedsAssignment": false,
      "category": "school|sports|medical|social|other",
      "date": "YYYY-MM-DD or null",
      "startTime": "HH:mm 24-hour or null",
      "endTime": "HH:mm 24-hour or null",
      "location": "string",
      "notes": "string",
      "confidence": 0.86,
      "ambiguityFlag": false
    }
  ]
}

Title vs childName (critical):
- "title" is the **event**: e.g. "Soccer practice", "Game vs Eagles", "Team photo", "BLUE HAWKS U12 practice", league/team names, age bands ("U12"), school event names.
- "childName" is **only** an actual **person** named on the flyer as the participant (first name, or "Sarah K.", etc.).
- Do **not** put team names, school names, org names, or the same words as title into childName. If the flyer does not name a specific child, set childName="" and childNeedsAssignment=true so the parent can pick in the app.
- A coach/contact name alone does not count as childName unless that row clearly states it is for that child's appointment.

Location (critical for flyers and maps):
- Fill "location" whenever the source gives a place that helps navigation: venue name, **full street address**, city/state/ZIP, building or field name, or a line like "at / @ [place]".
- Copy addresses **verbatim** from the flyer when possible: street number, street, unit, city, state, postal code; join multi-line addresses into **one line** using commas (e.g. "123 Main St, Springfield, IL 62701").
- If both a venue name and address appear (e.g. "Lincoln Gym" and "500 Oak Ave"), put **both** in "location" (venue first, comma, then address) so the app can geocode accurately.
- When one event row mentions "home vs away" or two sites, put the address that applies to **this** candidate in "location" and the other in "notes" with ambiguityFlag=true if unsure.
- Do **not** leave location empty if a postal address or unambiguous place name appears in the same block or adjacent lines as that event's date/time.

Time format (critical):
- Use 24-hour strings only for startTime and endTime: "09:00", "10:30", "17:30", "19:00". Never use "5:30 PM" in JSON (convert to "17:30").
- When the flyer gives a range ("5:30 PM to 7:00 PM", "5:30 PM–7:00 PM", "5:30 PM—7:00 PM" en/em dash ok, "from 5:30 to 7:00", "9:00 AM – 10:30 AM"), set BOTH startTime and endTime from that range. Do not drop the end time if it appears in the text.
- If the message says "game at 9:00 AM" and "arrive by 8:30 AM", use **startTime** for the main event start ("09:00") and put arrival ("Arrive by 08:30") in **notes**.

SMS, group chat, and email threads:
- Extract **one candidate per distinct scheduled event** in the thread. Skip acknowledgments ("Got it", "thanks") and pure reminders that duplicate a following detailed line.
- Lines from the same sender (e.g. coach) may be separate events — do not merge "Saturday game" with "Thursday practice" into one row.
- Use the **nearest explicit date anchor** in the thread (e.g. "Thursday, Sept 10") to resolve bare weekdays ("Saturday", "next Wednesday") to **YYYY-MM-DD** using the reference date provided in the user message.
- "Next Wednesday" means the Wednesday **after** the anchor you chose (e.g. after the Saturday game line, or after today if that fits the wording).

Dates:
- Never invent certainty; only fill fields supported by the text.
- Dates must be ISO "YYYY-MM-DD" when inferable. Do NOT leave date=null when that row has a specific month/day (or full date).
- If the title/header says "2026" or "Fall 2026", use that year for dates written without a year in the same document.
- If one line has a full date with year (e.g. "Monday, September 8, 2026"), use that year for other month/day-only dates in the same season unless contradicted.
- Month/day without year (e.g. "Sept 10"): use the year from the **reference date** in the user message unless the text implies a future season (then pick the next occurrence of that month/day after the reference date).

Lists of game or event days:
- If several dates appear in one sentence ("September 13, September 20, October 4"), output **one candidate per date**, each with its own "date" field.
- Copy times and locations from the nearest matching sentence. If home vs away times/locations are given but not mapped to specific dates, still emit one row per listed date and put both options in "notes" (e.g. "Confirm: home 9:00 at … vs away 10:30 at …") and set ambiguityFlag=true.

Recurring practices (e.g. "Every Monday and Wednesday"):
- Emit **one** candidate: set "date" to the **first** practice date if the text gives a season start or first session; put the recurrence ("Mon & Wed", season span) in "notes".
- Include startTime and endTime whenever the flyer states them (e.g. practice 17:30–19:00).

Games with only a start time (no end time):
- Set startTime from the text; leave endTime=null (do not guess).

Ambiguity:
- Set ambiguityFlag=true when date or start time cannot be determined from the text, or when home/away is unclear per date as above.
- Missing end time alone is NOT ambiguous if the flyer only lists a start.

confidence (required, 0.0–1.0):
- Your subjective certainty that this row’s fields match the source text (not model internal probability).
- Use high values (0.75–0.95) when date, start time, and title clearly come from the same sentence or block.
- Use mid (0.45–0.70) when you inferred year, recurrence, or merged lines with minor guesswork.
- Use low (0.2–0.45) when ambiguityFlag is true or key fields are weakly supported.
- Never copy a placeholder; set a real number per row.

If no events are found, return {"candidates": []}.
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
    ref_day = date.today().isoformat()
    user_prompt = (
        f"Reference date (for resolving missing years and relative weekdays): {ref_day}\n"
        f"Source hint: {source_hint or 'none'}\n\n"
        f"OCR or shared text:\n{ocr_text}"
    )
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
