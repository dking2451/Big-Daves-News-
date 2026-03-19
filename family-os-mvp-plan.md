# Family OS MVP Plan

## 1) MVP Implementation Plan (Planner-First)

### Phase 1: Foundation (Day 1)
- Create a separate iOS MVP project folder and a separate FastAPI backend folder.
- Define shared event and extraction schemas first.
- Wire local event persistence in iOS (JSON file) so app behavior is testable offline.

### Phase 2: Core iOS Flow (Days 2-3)
- Build onboarding and home screen with upcoming events + this week summary.
- Build manual add event form and event detail screen.
- Add settings screen with backend URL and clear local data action.

### Phase 3: Planner Hardening (Days 4-5)
- Add robust JSON handling (duplicate ID dedupe + corruption recovery).
- Add edit/delete persistence and relaunch reliability checks.
- Keep extraction review available only as a controlled test path.

### Phase 4: Backend + Prompt Quality (Day 6)
- Add FastAPI health and upload endpoints.
- Add extraction endpoint that calls OpenAI and returns normalized event candidates.
- Add strict JSON validation and graceful fallback errors.

### Phase 5: Pilot Hardening (Day 7)
- Add sample data, smoke-test checklist, and README run instructions.
- Test complete flow with 5-user pilot assumptions (no auth, no integrations).
- Prepare for TestFlight build validation.

## 2) Recommended Folder Structure

```text
ios/
  FamilyOSMVP/
    project.yml
    README.md
    Sources/
      Info.plist
      FamilyOSMVPApp.swift
      Models/
        FamilyEvent.swift
        ExtractedEventCandidate.swift
      Services/
        EventStore.swift
        APIClient.swift
        OCRService.swift
      Utilities/
        DateParsing.swift
      Views/
        MainTabView.swift
        WelcomeView.swift
        HomeView.swift
        ManualAddEventView.swift
        UploadScheduleView.swift
        ReviewExtractedEventsView.swift
        EventDetailView.swift
        SettingsView.swift
        Components/
          EventCard.swift
        UIKit/
          ImagePicker.swift
      Assets.xcassets/
        Contents.json

backend/
  family-os-mvp-api/
    README.md
    requirements.txt
    .env.example
    app/
      main.py
      schemas.py
      ai_client.py
      extractor.py
```

## 3) API Contract (MVP)

Base URL: `http://localhost:8000`

### `GET /health`
- Purpose: liveness check.
- Response:
```json
{ "status": "ok" }
```

### `POST /v1/upload-image` (deferred from app UX)
- Purpose: kept for future import flow; not used by current iOS navigation.
- Content-Type: `multipart/form-data`
- Form field: `file`
- Response:
```json
{
  "uploadId": "uuid",
  "filename": "schedule.png",
  "contentType": "image/png",
  "sizeBytes": 123456
}
```

### `POST /v1/extract-events`
- Purpose: convert source text into candidate events (manual/test path for now).
- Content-Type: `application/json`
- Request:
```json
{
  "ocrText": "raw OCR text from flyer or screenshot",
  "sourceHint": "school flyer"
}
```
- Response:
```json
{
  "candidates": [
    {
      "title": "Soccer Practice",
      "childName": "Mia",
      "category": "sports",
      "date": "2026-03-21",
      "startTime": "17:30",
      "endTime": "18:30",
      "location": "Lincoln Field",
      "notes": "Bring shin guards",
      "confidence": 0.86,
      "ambiguityFlag": false
    }
  ]
}
```

### Error Model
- Response codes: `400` validation, `500` extraction/internal failures.
- Error response:
```json
{
  "error": {
    "code": "EXTRACTION_FAILED",
    "message": "Could not extract events from provided text."
  }
}
```

## 4) Likely Breakpoints / Slowdowns
- OCR quality varies heavily with blurry photos and dense flyers.
- Ambiguous dates/times (for example "next Friday") need explicit review.
- Time zone assumptions can cause wrong event times if parsing is too aggressive.
- OpenAI output drift can happen without strict schema + fallback parsing.
- Camera permissions and photo permissions are common pilot setup friction.

## 5) Simplest Viable OCR/Extraction Path
- Current release: planner-first with extraction review as test-only path.
- Policy for ambiguous extraction:
  - If date is unclear, leave `date` blank (`null`).
  - If time is unclear, set `ambiguityFlag = true` and leave time fields blank (`null`).
  - Do not invent structured certainty.

## Future Release Backlog
- User Profile: add a **Manage Children** section.
  - View learned child names.
  - Rename and delete child names.
  - Set default child per event category (optional).
  - Reuse names in quick-select during manual event entry.
- Add **Help / How To** section for future iterations.
  - Keep icon language intuitive with no legend overlays.
  - Add short guided help screens for first-time setup and key workflows.
  - Include quick walkthrough for extraction review, recurrence, and integrations.

## Progress Snapshot (Completed)
- Planner-first iOS MVP scaffolded and running.
- FastAPI backend running locally with `/health`, extraction, and upload endpoints.
- Local JSON persistence hardened (dedupe, corruption recovery, edit/delete persistence, relaunch stability).
- Extraction ambiguity policy enforced (no invented certainty for missing date/time).
- Local-first backend wiring added for simulator/device testing.
- Add Event improved with:
  - child quick-select suggestions from learned history,
  - location suggestions by event type,
  - location validation with save-anyway fallback.
- Extraction review upgraded with:
  - calendar-based date selection,
  - non-military AM/PM time selection,
  - missing-field warnings and save guardrails,
  - quick-fill actions (today/start now/+1h/category-time presets).
- Home + planning UX upgraded:
  - Home now focuses on **Today** events,
  - Later events moved into collapsible section,
  - compact expandable rows (title/time first),
  - icon-first compact badges for category/recurrence,
  - inline directions from Home cards.
- Upcoming planner added as separate page:
  - full upcoming list with filters (child/category/recurrence),
  - no Home clutter for long-range planning.
- Recurrence implemented:
  - event-level recurrence options (none/daily/weekly/monthly),
  - recurrence indicators in cards/detail,
  - multi-instance recurrence expansion in upcoming windows.
- Apple integrations live:
  - Get Directions -> Apple Maps,
  - Add to Apple Calendar (EventKit),
  - Create Reminder (EventKit Reminders).
- User Profile groundwork expanded:
  - Manage Children UI (add/rename/remove),
  - child list persistence and quick-select sync.

## Next Functionality (Near-Term)

### Phase A: UX polish for beta
- Add conflict visibility in Upcoming:
  - detect overlaps by child and time window,
  - conflict icon badge + “Conflicts only” filter.
- Add duplicate detection:
  - warn on likely duplicates (same title/date/time/location),
  - allow “update existing” vs “keep both”.
- Add in-app diagnostics card (backend URL, health status, event count, last extraction result).

### Phase B: Manage Children (new feature)
- Add default behavior controls:
  - default child per category,
  - child-specific favorite locations,
  - child-specific recurring templates.

### Phase C: Smarter locations
- Save "verified" locations with labels.
- Add favorite locations section and recent locations section.
- Allow category -> default location mapping (for school/sports patterns).

## Robustness Roadmap
- Add lightweight unit tests for:
  - EventStore persistence and recovery,
  - dedupe conflict resolution,
  - date/time parsing edge cases.
- Add integration test script for backend:
  - `/health`,
  - extraction success path,
  - ambiguity/validation failures.
- Improve backend error mapping:
  - return specific code for quota/network/model errors,
  - surface user-friendly messages in iOS.
- Add request timeout/retry policy in iOS API client (conservative retry for transient network failures).
- Add crash-safe telemetry (minimal local logging + optional remote logging toggle later).

## Apple Integrations Roadmap

### Maps (first integration to ship)
- Add "Open in Maps" in Event Detail for saved location.
- On validation success, store resolved map name/address to improve launch accuracy.
- Optional later: add travel-time hint using MapKit ETA.

### Calendar (second integration)
- Add "Add to Apple Calendar" button per event (EventKit).
- Add one-time permission prompt with clear explanation.
- Keep one-way export first (no sync complexity yet).

### Reminders (third integration)
- Add "Create Reminder" action for event prep tasks.
- Suggested reminders:
  - "leave now" reminder,
  - "bring items" checklist from notes.
- Keep per-event manual reminder creation first.

### Email capture (fourth integration)
- Start with iOS Share Extension target (forward text/image into app).
- Parse inbound shared content into extraction review flow.
- Defer direct Mail inbox integrations to later.

## Suggested Implementation Order
1. Upcoming conflict detection + conflict-only filter
2. Duplicate detection on save/import
3. Child defaults + location favorites
4. Local notifications for critical events (pre-event reminders)
5. Share Extension for email/screenshot intake
6. Help / How To section (future onboarding)

## Definition of Done for Next Milestone
- Add/Edit/Review flows remain stable for 5 pilot users.
- Conflict and duplicate warnings reduce scheduling mistakes.
- Child defaults reduce manual input time.
- Home remains calm while Upcoming handles planning complexity.
- Regression checklist passes on simulator + physical device.
