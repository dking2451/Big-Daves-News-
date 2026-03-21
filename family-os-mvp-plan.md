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
  - inline directions from Home cards,
  - top-level **Next Up** card and deterministic weekly summary card,
  - quick-add floating action sheet for sub-10 second capture.
- Upcoming planner added as separate page:
  - full upcoming list with filters (child/category/recurrence),
  - no Home clutter for long-range planning,
  - conflict detection by child/time overlap,
  - conflict badge and "Conflicts only" filter,
  - severity-aware issue language (conflict vs tight-turn warning).
- Duplicate handling added:
  - manual add warns on likely duplicate and supports "update existing" or "keep both",
  - extraction review supports duplicate handling mode (update existing vs keep both).
- Conflict logic hardened:
  - duplicate-like same-event pairs excluded from conflicts,
  - weekly summary now counts unique conflicted events (not pairwise overlap inflation),
  - warning-tier tight transitions surfaced separately from true conflicts.
- Recurrence implemented:
  - event-level recurrence options (none/daily/weekly/monthly),
  - recurrence indicators in cards/detail,
  - multi-instance recurrence expansion in upcoming windows.
- Apple integrations live:
  - Get Directions -> Apple Maps,
  - Add to Apple Calendar (EventKit),
  - Create Reminder (EventKit Reminders).
- Local reminders now live:
  - automatic iOS local notification scheduling on create/update,
  - automatic removal/resync on edit/delete/relaunch,
  - default offsets at 1 hour and 30 minutes before event start.
- **Share Sheet import (MVP, minimal):**
  - Extension: **text first** (plain / URL string), then **single image**; App Group files `handoff.json` + optional `import.jpg`.
  - Main app: `RootContentView` + `ShareHandoff.consume()` + sheet with **`ShareImportView`** → same extraction + **`ReviewExtractedEventsView`** as in-app flows (no silent saves).
- User Profile groundwork expanded:
  - Manage Children UI (add/rename/remove),
  - child list persistence and quick-select sync,
  - per-child color assignment with persistence,
  - per-child defaults (category/recurrence/favorite locations),
  - Home + Upcoming event tinting by child color.

## Phase Focus: Retention + Trust + Polish

### Product Principles (This Phase)
1. Low friction > feature richness.
2. Trust > automation.
3. Clarity > cleverness.
4. Speed > completeness.
5. Real usefulness > "cool AI".

## Next 2 Sprint Roadmap

### Sprint 1 (Reliability + Daily Use)
- Add lightweight diagnostics card in Settings:
  - backend URL, health status, event count, last extraction result.
- Run checklist-based QA and close defects for 5 pilot users:
  - notification reliability edge cases (permission denied, edits, relaunch),
  - conflict/warning trust checks with dense recurring schedules,
  - quick-add speed and empty-state clarity.

### Sprint 2 (Memory Load Reduction + Habit Loop)
- Add reminder defaults (off by default; simple opt-in per event type).
- Add quick-add templates from learned patterns (1-tap insert in Manual Add).
- Improve empty states to be action-oriented (seed, quick-add, examples).
- Close polish gaps (spacing, typography, loading/error consistency, accessibility labels/help text).

## Explicitly Not Building (Now)
- Authentication, multi-user household accounts, cloud sync.
- New external integrations (Google Calendar, Gmail, school SIS, etc.).
- Payments/subscriptions and growth loops.
- Autonomous AI actions (auto-creating/editing/deleting events without explicit user approval).
- Large architecture changes or backend expansion beyond current FastAPI scope.

## Retention-Focused Features (Prioritized)
1. **What’s Next Strip (Home)**  
   - Short description: surface next critical event(s) with leave-time context and one tap to details/reminder.  
   - Why it matters: gives immediate value on every open and reduces mental scanning.  
   - Complexity: Low-Medium.  
   - Codebase fit: `Views/HomeView.swift`, `EventStore` query helpers.
2. **Weekly Snapshot (Planning Card)**  
   - Short description: generated "This week at a glance" card (busy days, conflicts, medical/school highlights).  
   - Why it matters: supports weekly planning ritual; parents return each week.  
   - Complexity: Medium.  
   - Codebase fit: `HomeView`, optional helper in `EventStore`.
3. **Reminder Defaults (Local Notifications)**  
   - Short description: simple reminder offsets (for example 30m before) with event-level override.  
   - Why it matters: reliability and "don’t forget" utility are core stickiness drivers.  
   - Complexity: Medium.  
   - Codebase fit: `ManualAddEventView`, `EventDetailView`, iOS notification helper service.
4. **Template Quick-Add from Patterns**  
   - Short description: one-tap event templates generated from frequent historical patterns.  
   - Why it matters: reduces creation friction, improves habit use.  
   - Complexity: Medium.  
   - Codebase fit: existing `EventStore.manualEntrySuggestions`, `ManualAddEventView`.
5. **Diagnostics + Recovery Clarity**  
   - Short description: visible app health and "what failed / what to do next" messages.  
   - Why it matters: trust improves when failures are understandable and recoverable.  
   - Complexity: Low.  
   - Codebase fit: `SettingsView`, `APIClient`, extraction review status messages.

## AI Usage Strategy (Opinionated)

### Use AI Right Now
- Summarization of existing structured events (weekly digest, tomorrow focus).
- Lightweight planning assistance ("what’s next", "busy windows", "conflict highlights").
- Pattern recognition from local history (repeatable quick-add suggestions).

### Do Not Use AI Yet
- Autonomous writes/actions (creating, moving, deleting events without explicit confirmation).
- Complex agentic orchestration across apps/systems.
- Probabilistic recommendations presented as certainty.
- Any flow that hides source data or makes edits non-transparent.

### 2-3 Simple AI Features (Low Complexity, Existing Data)
1. **Weekly Summary Text**  
   - Generate short plain-language weekly brief from local events.
2. **Tomorrow Prep Summary**  
   - "Tomorrow has 3 events, first at 8:00 AM, leave by 7:35 AM" style hint.
3. **Recurring Pattern Suggestions**  
   - Promote top recurring patterns into suggested quick-add templates.

## UX Improvements (Actionable)

### Home Screen
- Keep "Next Up" + Weekly Summary as the stable top dashboard anchors.
- Add warning metric alongside conflicts where it improves trust context.
- Keep one strong blue CTA per viewport; secondary actions neutral.

### Event Creation
- Auto-apply child defaults immediately on child selection.
- Promote child favorite locations above generic suggestions.
- Keep save path linear: validate -> duplicate decision -> save confirmation.

### Conflict Handling
- Keep inline conflict summaries visible in Upcoming rows.
- Keep severity hierarchy consistent: conflict > warning > none.
- Make conflict-only filter state obvious (selected chip + badge count).

### Empty States
- Home empty: quick actions ("Add Event", "Load Demo", "Create Weekly Template").
- Upcoming empty: suggest filter reset and one-tap add.
- Review empty: explain why extraction returned none + suggest manual fallback.

## Stability + Premium Feel Checklist (Pre-TestFlight)
- No crashes on add/edit/delete/duplicate/conflict paths.
- JSON persistence survives relaunch with no data loss or corruption.
- All async actions have loading and failure states (validate, health, extraction).
- All destructive actions have confirmation (clear/delete/overwrite duplicate).
- UI consistency: spacing, typography, button contrast, icon clarity, 44pt tap targets.
- Accessibility: labels for icon buttons, VoiceOver-friendly event summaries, Dynamic Type checks.
- Performance: Home and Upcoming render smoothly with 200+ events.
- Startup readiness: app launch to usable home state within target budget on test devices.

## Success Metrics (Simple, Practical)
- Weekly Active Usage: number of days app opened per week per tester.
- Planning Activity: events created/edited per week.
- Trust Signals: duplicate updates chosen vs canceled saves; conflict resolutions completed.
- Reminder Utility: percentage of events with reminder enabled.
- Qualitative Feedback: "reduced mental load" score from weekly pilot check-ins.

## Definition of Done for This Phase
- 5 pilot users use the app weekly with minimal support.
- Conflict and duplicate flows are understood without explanation.
- Child defaults measurably reduce add-event friction.
- "What’s Next" and weekly summary surfaces are used repeatedly.
- Beta checklist passes on simulator + physical device with no critical regressions.
