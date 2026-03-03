# Fact-Checked News Agent (MVP)

This project pulls articles from trusted news sources, extracts candidate factual claims, and marks claims as validated only when corroborated by multiple reputable sources.

## What this MVP does

- Pulls RSS entries from an allowlisted source config (`data/sources.json`)
- Extracts fact-like claim candidates from title/summary text
- Aggregates evidence by claim text
- Assigns:
  - `validated` + `High` confidence when tier-1 corroboration threshold is met
  - lower confidence/status when corroboration is weaker
- Serves:
  - API endpoint: `/api/facts`
  - Web dashboard: `/`

## Quickstart

1. Create and activate a virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Run the app:

```bash
uvicorn app.main:app --reload
```

4. Open:

- `http://127.0.0.1:8000/`
- `http://127.0.0.1:8000/api/facts`

## Notes

- Current claim extraction is heuristic and intentionally conservative.
- For production, replace extraction with structured LLM extraction and add a stronger claim-matching strategy.
- Keep `data/sources.json` strict to avoid low-quality sources.

## Daily 8AM Central Email

You can run a background scheduler that sends an email summary and report link every day at 8:00 AM America/Chicago.

1. Copy and edit environment variables:

```bash
cp .env.example .env
```

Set these values in `.env`:

- `EMAIL_SMTP_HOST` (for Gmail, use `smtp.gmail.com`)
- `EMAIL_SMTP_PORT` (typically `587`)
- `EMAIL_USERNAME`
- `EMAIL_APP_PASSWORD` (app password, not your normal email password)
- `EMAIL_FROM`
- `EMAIL_TO`
- `REPORT_URL` (public page URL to your report)
- `REPORT_API_URL` (JSON endpoint URL)

2. Install dependencies:

```bash
source .venv/bin/activate
pip install -r requirements.txt
```

3. Send a one-time test email:

```bash
python -m app.daily_scheduler --send-now
```

4. Install macOS LaunchAgent (keeps scheduler running):

```bash
./scripts/install_scheduler_launchagent.sh "$(pwd)"
```

Logs will be in `logs/scheduler.out.log` and `logs/scheduler.err.log`.

## Stable Public URL (No Mac Required)

Use the included `render.yaml` to deploy a permanent web URL and a cloud daily email job.

1. Push this project to GitHub.
2. In Render, create a **Blueprint** from your repo (it reads `render.yaml`).
3. Set environment variables:
   - **Web service**:
     - `NEWS_BRAND`
     - `ADMIN_TOKEN`
     - `USE_DYNAMIC_PUBLIC_REPORT_URL=false` (recommended on cloud deployments)
     - `DATABASE_URL` is auto-injected from the Render Postgres database via `render.yaml`
     - Optional hosted LLM (recommended for cloud chat):
       - `HOSTED_LLM_API_KEY`
       - `HOSTED_LLM_MODEL` (for example `openai/gpt-4o-mini`)
       - `HOSTED_LLM_BASE_URL` (default `https://openrouter.ai/api/v1` for OpenRouter-compatible setup)
       - `HOSTED_LLM_TIMEOUT_SECONDS` (optional)
   - **Cron email service only**:
     - `EMAIL_SMTP_HOST`
     - `EMAIL_SMTP_PORT`
     - `EMAIL_USERNAME`
     - `EMAIL_APP_PASSWORD`
     - `EMAIL_FROM`
     - `EMAIL_TO`
     - `REPORT_URL` (set to your Render/custom domain URL)
     - `REPORT_API_URL` (set to `https://<domain>/api/facts`)
     - `SCHEDULER_TIMEZONE` (`America/Chicago`)
     - `DAILY_SEND_HOUR_LOCAL` (`8`)
     - `DAILY_SEND_MINUTE_LOCAL` (`0`)
     - `DAILY_SEND_WINDOW_MINUTES` (`59`, recommended for Render cron jitter)
     - `DATABASE_URL` is auto-injected from the same Render Postgres database
4. Deploy.
5. Add custom domain in Render:
   - Render dashboard -> Settings -> Custom Domains
   - add your domain (e.g. `bigdavesnews.com`)
   - update DNS records at your registrar as instructed
6. Update `REPORT_URL` and `REPORT_API_URL` to the final custom domain.

### Notes

- The cron service runs hourly and sends when current local time falls within the configured send window (`08:00` + `DAILY_SEND_WINDOW_MINUTES`).
- Persistent app data uses Postgres when `DATABASE_URL` is set (Render), otherwise local SQLite (`data/big_daves_news.db` by default; override with `DATA_DB_PATH`). Existing JSON stores are auto-migrated on first run.
- In cloud deployments, `FREE_LLM_BASE_URL=http://127.0.0.1:11434` points to the Render container itself, not your Mac. Use hosted LLM env vars for `Talk to the News` in production.
- If old email links reference expired tunnel domains, set `USE_DYNAMIC_PUBLIC_REPORT_URL=false` and ensure `REPORT_URL` points at your Render/custom domain.
