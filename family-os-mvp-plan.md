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
