# Family OS MVP iOS App

Lightweight SwiftUI planner MVP for parent schedule management.

## Requirements
- Xcode 15+
- iOS 17 target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed (`brew install xcodegen`)

## Generate project and run

```bash
cd ios/FamilyOSMVP
xcodegen generate
open FamilyOSMVP.xcodeproj
```

Run on simulator or device.

### Share Extension + App Group (TestFlight / device)

The project includes **`FamilyOSMVPShareExtension`** and entitlements for App Group **`group.com.familyos.mvp`**.

1. In Xcode, select the **FamilyOSMVP** target → **Signing & Capabilities** → ensure **App Groups** includes `group.com.familyos.mvp` (should match `Sources/FamilyOSMVP.entitlements`).
2. Repeat for **FamilyOSMVPShareExtension** → `ShareExtension/ShareExtension.entitlements`.
3. In the [Apple Developer Portal](https://developer.apple.com), enable the same App Group on both App IDs (main app + extension) or use automatic signing and let Xcode manage it.

**Flow:** Extension resolves **plain text first**, then **URL as text**, then **one JPEG** (`ShareHandoff`: `handoff.json` + optional fixed `import.jpg`). Opens **`familyosmvp://import`** → **`ShareImportView`** → **Extract events** → existing **`ReviewExtractedEventsView`** (no saves until confirm).

## MVP Features
- Onboarding welcome
- Home with Today/This Week summary
- Manual add event form
- Event edit/delete with persistence
- JSON resilience (duplicate ID resolution + corrupted file recovery)
- Event detail view
- Settings with backend URL + clear local data
- **Share Sheet import:** Messages / Mail / Notes / Safari / Photos → in-app Import review → OCR (images) + backend extraction → review before save

## Deferred for later release
- Rich attachment / multi-item share pipelines
- Background inbox processing

## Ambiguity policy (for backend extraction responses)
- If date is unclear, keep it blank (`null`).
- If time is unclear, set `ambiguityFlag = true` and keep times blank (`null`).
- Never invent structured certainty.

## Test ingestion (paste / share)

Sample SMS, flyer, and email-style text lives in **`Fixtures/Ingestion/`** — copy a file’s contents into **Paste Text** to test extraction (see that folder’s `README.md`).

## Backend URL
By default app uses:

`http://localhost:8000`

For a physical iPhone, use your machine LAN IP, for example:

`http://192.168.1.23:8000`
