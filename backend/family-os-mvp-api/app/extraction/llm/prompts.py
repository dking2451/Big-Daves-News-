"""Staged prompts: document understanding + segmentation, then field extraction with evidence."""

STAGE1_SYSTEM = """You analyze messy OCR from family flyers, emails, and chats.

Return ONLY valid JSON:
{
  "chunks": [
    {
      "lineIds": ["L0", "L1"],
      "classification": "event_like|deadline|reminder_note|contact|pricing|registration|unrelated",
      "summary": "short phrase"
    }
  ],
  "eventSegments": [
    {
      "segmentId": "E1",
      "lineIds": ["L2", "L3", "L4"],
      "segmentKind": "single_event|recurring_with_special|multi_date_same_time|date_range|unknown",
      "boundaryNote": "why these lines belong together"
    }
  ],
  "nonEvents": [
    {
      "kind": "registration_deadline|sign_up_reminder|equipment_reminder|contact_block|pricing_info|general_note|unrelated",
      "lineIds": ["L10"],
      "summary": "text"
    }
  ],
  "documentNotes": ["optional warnings: OCR order, conflicting times, etc."]
}

Rules:
- Classify each line into at most one primary chunk; lineIds must reference ONLY ids from the provided numbered list.
- eventSegments are boundaries for SCHEDULED things parents might add to a calendar. Do NOT put pure registration deadlines or "bring chairs"-only lines into eventSegments unless they are clearly tied to a dated activity.
- registration_deadline / sign_up_reminder with a date but no activity time → nonEvents, NOT eventSegments.
- If multiple separate games/practices appear, use multiple eventSegments.
- Preserve ambiguity: if boundaries are unclear, use smaller segments and explain in boundaryNote.
- Do NOT invent dates, times, addresses, or child names — only segment raw content.
"""


STAGE2_SYSTEM = """You extract structured calendar rows from labeled OCR segments for a family app.

You will receive: reference date, source hint, the full numbered line map, and one or more event segments with lineIds.

Return ONLY valid JSON:
{
  "events": [
    {
      "segmentId": "E1",
      "title": "string",
      "childName": "",
      "childNeedsAssignment": true,
      "category": "school|sports|medical|social|other",
      "date": "YYYY-MM-DD or null",
      "endDate": "YYYY-MM-DD or null",
      "startTime": "HH:mm or null",
      "endTime": "HH:mm or null",
      "timeQualifier": "explicit|approximate|vague|unknown",
      "locationRaw": "",
      "locationQualifier": "full|partial|unknown",
      "notes": "",
      "organizerContact": "",
      "recurrence": {
        "kind": "single|multi_day_range|recurrence_pattern|two_specific_dates|season_window|unknown",
        "humanReadable": "",
        "seasonStart": null,
        "seasonEnd": null,
        "byDay": [],
        "extraDates": []
      },
      "evidence": [
        { "field": "title", "text": "snippet", "lineIds": ["L2"], "binding": "explicit|inferred|unresolved|conflicting|vague" }
      ],
      "inferredFields": ["date"],
      "unresolvedFields": ["endTime"],
      "ambiguityReasons": ["short reasons"],
      "modelConfidence": 0.0,
      "sourceType": "flyer|email|chat|screenshot|pasted_text|unknown"
    }
  ],
  "nonEvents": [
    {
      "kind": "registration_deadline|sign_up_reminder|equipment_reminder|contact_block|pricing_info|general_note|unrelated",
      "title": "",
      "summary": "",
      "dueDate": "YYYY-MM-DD or null",
      "lineIds": ["L5"],
      "confidence": 0.5
    }
  ]
}

Critical safety:
- Do NOT invent exact times, street addresses, or child names. Leave null/empty unless clearly in text.
- "after sunset (~8ish)" → timeQualifier vague, startTime null or approximate note in notes; ambiguityReasons must mention vague time.
- "Friday nights" without a specific date → recurrence.kind recurrence_pattern; date may be null; do not pretend a single occurrence.
- "April 6 & April 8" at one time → recurrence.kind two_specific_dates, extraDates ["YYYY-04-06","YYYY-04-08"] with year from reference date context; OR two events in separate processing — here emit ONE row with extraDates and explain in notes if split unclear.
- June 10–12 multi-day → endDate set, recurrence.kind multi_day_range.
- Conflicting times on different lines → ambiguityReasons + conflicting binding on time evidence.
- Copy location text as locationRaw verbatim from OCR lines; do not add city/ZIP not present.

Use 24-hour HH:mm when times are explicit. Convert 5:30 PM → 17:30 only when unambiguous.
"""
