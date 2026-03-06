# Big Daves News iOS App (Starter)

This folder contains a SwiftUI starter client for the live API:

- Base URL: `https://big-daves-news-web.onrender.com`
- Headlines: `/api/facts`
- Weather: `/api/weather?zip_code=...`
- Business chart: `/api/market-chart?symbol=...&range=...`

## Option A: Generate with XcodeGen (fastest)

1. Install XcodeGen (if needed):
   - `brew install xcodegen`
2. From this folder:
   - `xcodegen generate`
3. Open `BigDavesNewsApp.xcodeproj` in Xcode.
4. Set your Team + Bundle ID, then run on Simulator.

## Option B: Manual Xcode project

1. Create new Xcode iOS App project named `BigDavesNewsApp` (SwiftUI).
2. Replace the generated Swift files with files under `Sources/`.
3. Add all files in `Sources/` to the app target.
4. Run.

## Notes

- This starter targets iOS 16+ (uses `Charts` for business graphs).
- It includes local ticker favorites persistence (`UserDefaults`).
- It includes a Settings tab with:
  - email signup to your `/api/subscribe` endpoint
  - local daily reminder scheduling (notification permission required)
  - APNs device token auto-sync to:
    - `/api/push/register-token`
    - `/api/push/unregister-token`
- It is read-only client-side and uses your existing Render backend.

## Versioning for TestFlight

Use `project.yml` as the single source of truth for iOS version/build:

- `MARKETING_VERSION` -> user-facing app version (for example `1.0.0`, `1.1.0`)
- `CURRENT_PROJECT_VERSION` -> build number (must increase every upload)

Fast workflow:

```bash
# Bump build number only (most TestFlight uploads)
python3 scripts/version_bump.py

# Bump to a new app version and auto-increment build
python3 scripts/version_bump.py --set-version 1.1.0

# Set both explicitly
python3 scripts/version_bump.py --set-version 1.1.0 --set-build 1
```

Then regenerate before archiving:

```bash
xcodegen generate
```
