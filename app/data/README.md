# Curated data files

## `stadium_schedule.json`

Stopgap **Stadium / Bally Sports Live** linear listings for the Live Sports **Ocho** bundle (no public API).

### How to update

1. Open `stadium_schedule.json`.
2. Set `updated_at` to the time you edited (UTC ISO-8601).
3. Add or edit objects under `events`:
   - **`id`**: stable string (unique). Avoid spaces; use `kebab-case`.
   - **`title`**: on-air title as users should see it.
   - **`start_time_utc`**: ISO-8601 in **UTC** (e.g. `2026-03-24T17:00:00Z`).
   - **`status_text`**: short line (replay vs live, etc.).
   - **`home_team`**, **`away_team`**: optional; use `""` if not applicable.
   - **`network`**: usually `"Stadium"` (shown in the app).

4. Deploy or restart the API so the file is picked up (responses are cached ~5 minutes).

### Optional: custom path (e.g. Render disk)

Set env `STADIUM_SCHEDULE_JSON_PATH` to an absolute path; otherwise the repo file under `app/data/` is used.

### App behavior

- Rows appear when the client requests **Ocho / alt-sports** content (`include_ocho`), regardless of provider/availability filters.
- Each item is labeled **`stadium_curated`** in API `source_type` (not ESPN live data).
