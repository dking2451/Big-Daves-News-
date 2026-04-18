# Big Daves News iOS App (Starter)

This folder contains a SwiftUI starter client for the live API:

- Base URL: `https://big-daves-news-web.onrender.com`
- Headlines: `/api/facts`
- Weather: `/api/weather?zip_code=...`
- Business chart: `/api/market-chart?symbol=...&range=...`

## Option A: Xcode project (recommended)

Open **`BigDavesNewsApp-iOS-tvOS.xcodeproj`** in Xcode. It contains the **iOS** app, **tvOS** app, and unit-test target.

### Apple TV (Simulator)

Use this **only** project file for both phone/tablet and TV:

`ios/BigDavesNewsApp/BigDavesNewsApp-iOS-tvOS.xcodeproj`

(Do **not** open `ios/FamilyOSMVP/FamilyOSMVP.xcodeproj` for Big Daves News TV—that is a different app.)

1. Install a **tvOS Simulator** runtime if needed: **Xcode → Settings → Platforms** → add **tvOS**.
2. In Xcode, select scheme **`BigDavesNewsTV`** (not `BigDavesNewsApp`).
3. Set the run destination to an **Apple TV** simulator (e.g. **Apple TV 4K (3rd generation)**).
4. Run (**⌘R**).

**Important:** Do **not** add **tvOS** to the **`BigDavesNewsApp`** (iPhone) target’s “Supported Destinations” in Xcode. That target must stay **iPhone/iPad only**; it compiles `Sources/` (WebKit, etc.), which does not build for tvOS. The **TV** app is the separate **`BigDavesNewsTV`** target and scheme.

### XcodeGen (optional)

`project.yml` is kept for **version metadata** and experimentation. A plain `xcodegen generate` emits **`BigDavesNewsApp.xcodeproj`** from the YAML `name` and currently reflects the **iOS app only**—it does **not** replace the full iOS + tvOS project on its own. Prefer opening **`BigDavesNewsApp-iOS-tvOS.xcodeproj`** unless you have updated `project.yml` to match every target in that bundle.

1. Install XcodeGen (if needed): `brew install xcodegen`
2. From this folder (only if you intentionally regenerate from YAML): `xcodegen generate`
3. Set your Team + Bundle ID, then run on Simulator.

## Option B: Manual Xcode project

1. Create new Xcode iOS App project named `BigDavesNewsApp` (SwiftUI).
2. Replace the generated Swift files with files under `Sources/`.
3. Add all files in `Sources/` to the app target.
4. Run.

## Future features

See [`docs/FUTURE_FEATURES.md`](docs/FUTURE_FEATURES.md) for a small backlog (e.g. Watch UX follow-ups). Add items there after you test and decide what’s worth building.

## Watch tab (product + engineering)

See [`docs/WATCH_TAB.md`](docs/WATCH_TAB.md) for the Watch header (**My List**, Filter, Help) and [`docs/WATCH_HUB_PHASES.md`](docs/WATCH_HUB_PHASES.md) for phased **Watch Hub** plans (Phase 1 shipped: My List + save toast; Phase 2: full hub).

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

Before archiving, confirm **Marketing Version** and **Build** in Xcode match `project.yml` (or regenerate from YAML only if your `project.yml` fully describes this project).

```bash
# Optional; see "XcodeGen" above — prefer editing BigDavesNewsApp-iOS-tvOS.xcodeproj in Xcode
# xcodegen generate
```
