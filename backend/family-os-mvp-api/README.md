# Family OS MVP Backend (FastAPI)

Tiny extraction backend for the Family OS MVP iOS app.

## Features
- `GET /health`
- `POST /v1/upload-image` (basic upload endpoint for debugging)
- `POST /v1/extract-events` (OCR text -> structured event candidates via OpenAI)

## Local Setup

```bash
cd backend/family-os-mvp-api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Set env vars:

```bash
export OPENAI_API_KEY="your_key_here"
export OPENAI_MODEL="gpt-4o-mini"
```

Run:

```bash
uvicorn app.main:app --reload --port 8000

Production (Render) uses `--proxy-headers` behind the edge proxy; see `render.yaml`.
```

API docs:
- [http://localhost:8000/docs](http://localhost:8000/docs)

## Render deploy (recommended)

This repo already uses Render, so keep this MVP isolated as its own service.

1. In Render dashboard, create a **Blueprint** service from repo.
2. Point to:
   - `backend/family-os-mvp-api/render.yaml`
3. Set secret env var:
   - `OPENAI_API_KEY`
4. Deploy and verify:
   - `GET /health` returns `{"status":"ok"}`

**Important:** The iOS app’s default backend URL must match the **exact HTTPS URL** Render shows for **this** Web Service (e.g. `https://something.onrender.com`). If you see **404** on `/health`, the service is missing, the URL is wrong, or a different app is bound to that hostname—open the Render dashboard, open the **family-os-mvp-api** (or equivalent) service, and copy **its** URL into the app’s Settings → Backend.

Example production curl (replace host with your live service URL):

```bash
curl -s https://<your-family-os-api>.onrender.com/health
```

```bash
curl -s -X POST https://<your-family-os-api>.onrender.com/v1/extract-events \
  -H "Content-Type: application/json" \
  -d '{
    "ocrText": "Soccer practice for Mia on 2026-03-21 from 17:30 to 18:30 at Lincoln Field.",
    "sourceHint": "sports schedule"
  }'
```

## Notes
- This backend intentionally stays minimal for MVP speed.
- iOS does OCR on-device with Vision and sends extracted text to `/v1/extract-events`.
- The app auto-loads `.env` values at startup (via `python-dotenv`) for local convenience.
