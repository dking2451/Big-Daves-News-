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

## MVP Features
- Onboarding welcome
- Home with Today/This Week summary
- Manual add event form
- Event edit/delete with persistence
- JSON resilience (duplicate ID resolution + corrupted file recovery)
- Event detail view
- Settings with backend URL + clear local data

## Deferred for later release
- Image upload and OCR flow
- Extraction-first import UX

## Ambiguity policy (for backend extraction responses)
- If date is unclear, keep it blank (`null`).
- If time is unclear, set `ambiguityFlag = true` and keep times blank (`null`).
- Never invent structured certainty.

## Backend URL
By default app uses:

`http://localhost:8000`

For a physical iPhone, use your machine LAN IP, for example:

`http://192.168.1.23:8000`
