# Streaming provider launch (Watch)

## Overview

`StreamingProviderLaunch.swift` centralizes:

- **Catalog** — `StreamingProviderDefinition` + `StreamingProviderCatalog.definitions`
- **Launch logic** — `StreamingProviderLauncher` (`canOpenURL`, `UIApplication.shared.open`)
- **UI** — `StreamingProviderLaunchControl` (hero + card styles)

## Info.plist: `LSApplicationQueriesSchemes`

iOS requires every **custom URL scheme** you pass to `UIApplication.shared.canOpenURL(_:)` to be declared under **`LSApplicationQueriesSchemes`** (up to ~50 schemes). Without this, `canOpenURL` returns `false` even when the app is installed.

Declared schemes (see `Sources/Info.plist`) match `querySchemes` on each `StreamingProviderDefinition`. When you add a provider or a new scheme, **update both** the catalog and this array.

## Configuration model (`StreamingProviderDefinition`)

| Field | Purpose |
|--------|--------|
| `id` | Stable key (e.g. `netflix`) |
| `displayName` | Short name for menus and copy |
| `matchKeywords` | Lowercased substrings matched against API `primaryProvider` / `providers` |
| `querySchemes` | Schemes for `canOpenURL` (no `://`) — **must** be in Info.plist |
| `supportsTitleDeepLink` | If `true`, `titleAppURLTemplate` may be used (rare; needs stable IDs from backend) |
| `titleAppURLTemplate` | Optional; use `{title}` placeholder, percent-encoded |
| `homeAppURL` | Deep link to app home / browse |
| `universalWebURL` | HTTPS fallback (Safari; may open app via Universal Links) |
| `appStoreURL` | App Store product page if app not installed |
| `primaryActionTitle` | e.g. “Open in Netflix”, “Open in HBO Max” |
| `offerWebAndSearchFallbacks` | If `true` and title deep link isn’t used, shows a **Menu** with web / search / App Store |

## Launch order (`StreamingProviderLauncher.open(for:)`)

1. Known catalog match from `primaryProvider` / `providers`
2. If `supportsTitleDeepLink` and template → try title URL
3. If **any** `querySchemes` passes `canOpenURL` → open `homeAppURL`
4. Else open `universalWebURL`
5. Else open `appStoreURL`
6. Else Google search for title + provider

## UX when title-level deep links aren’t available

The app defaults to **opening the provider app to home** when installed (best one-tap flow). Because most providers don’t expose stable **title** URLs without backend IDs, `StreamingProviderLaunchControl` uses a **Menu** (same tap target as the primary label) with:

- Primary row matching `primaryActionTitle` (same as automatic path)
- Provider website
- Web search for the show title
- App Store (when the app doesn’t appear installed)

This avoids silent failure and avoids pretending we can deep-link to a specific episode without data.

## Integration points

- **Hero** — `WatchTonightHeroCard` uses `StreamingProviderLaunchControl(style: .heroPrimary)`
- **Cards** — `WatchShowCard` uses `StreamingProviderLaunchControl(style: .cardCompact)` above the reaction row

Unknown providers still get **“Find where to watch”** → Google search.
