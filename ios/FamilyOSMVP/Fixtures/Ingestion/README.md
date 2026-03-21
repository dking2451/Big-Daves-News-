# Ingestion test samples (paste / share)

Plain-text fixtures to **copy into Family OS MVP → Home → Paste event text** (or Share from another app) to exercise AI extraction and the review screen.

**Requirements**

- **Backend reachable** — Settings → Backend URL must point to your running API (simulator: `http://127.0.0.1:8000`, device: your Mac’s LAN IP).
- **Nothing saves automatically** — you still review and accept/reject on the next screen.

**Quick copy on macOS** (from repo root):

```bash
cat ios/FamilyOSMVP/Fixtures/Ingestion/01_sms_team_practice.txt | pbcopy
```

Then in the app: **Paste from Clipboard** → **Extract Events**.

| File | What it stresses |
|------|------------------|
| `01_sms_team_practice.txt` | Short SMS: one child, time, place |
| `02_school_newsletter_block.txt` | Dense flyer: multiple events, mixed detail |
| `03_group_thread_vague.txt` | Messy thread: missing/unclear date or time (ambiguity) |
| `04_sports_tournament_flyer.txt` | Table-ish schedule, same day multiple games |
| `05_appointment_email.txt` | Email tone, address block, one medical slot |

Edit dates in the `.txt` files to stay **in the future** if you want them to show under Upcoming after save.
