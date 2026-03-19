# Family OS MVP - Quick Start

This MVP is split into:
- `ios/FamilyOSMVP` (SwiftUI app)
- `backend/family-os-mvp-api` (FastAPI extraction API)

## 1) Start backend

```bash
cd backend/family-os-mvp-api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export OPENAI_API_KEY="your_key_here"
export OPENAI_MODEL="gpt-4.1-mini"
uvicorn app.main:app --reload --port 8000
```

Health check:

```bash
curl http://localhost:8000/health
```

## 2) Start iOS app

```bash
cd ios/FamilyOSMVP
xcodegen generate
open FamilyOSMVP.xcodeproj
```

In app settings:
- confirm backend URL is `http://localhost:8000` for simulator
- for real devices use your machine LAN IP

## 3) MVP test flow
1. Complete onboarding.
2. Add one manual event.
3. Edit the event and verify updates on Home.
4. Delete an event and verify it is removed.
5. Relaunch app and confirm event state persists.
6. In DEBUG, open extraction review sandbox from Settings and verify ambiguity handling.

## JSON resilience checks
- Duplicate IDs: store dedupes by `id`, keeping the most recently updated entry.
- Corrupted file: app moves invalid file aside as `.corrupt.<timestamp>.json` and relaunches cleanly.
- Edit/delete persistence: all mutations save atomically and survive relaunch.
