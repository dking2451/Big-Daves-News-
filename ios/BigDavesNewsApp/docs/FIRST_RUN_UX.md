# First-run & first 60 seconds (Big Dave’s News)

## What ships

1. **Launch** — On first install (personalization not completed), a **brief splash** (~420 ms) runs while `SportsLiveStatus` refresh starts; **no extra network gates** before showing UI.
2. **Onboarding** — Existing multi-step flow (genres → providers → sports → done). **Skip** on the welcome screen routes to **Watch** via `AppNavigationState.routeToFirstPersonalizedExperience()` so users don’t land on a generic Headlines home first.
3. **Completion** — **Start Exploring** saves prefs, sets a one-time **first-value tooltip** flag, switches to **Watch**, and bumps `openWatchTonightPick()` so Tonight’s Pick scrolls into view when data is ready.
4. **First value** — **Tonight’s Pick** hero (existing ranking from `LocalUserPreferences`) plus **FirstValueHintOverlay**: “We picked this for you” (tap or ~6 s auto-dismiss). The hero already shows **Open in [Provider]** when the catalog matches (`HeroWatchCardView` + `StreamingProviderLauncher`).
5. **Watch guide** — If the first-value hint is pending, the **How Watch works** sheet is **deferred** until the hint is dismissed or cleared, avoiding two modals at once. That sheet documents the Watch header (**bookmark** = saved TV list, **filter** = filters) and card actions; see [`WATCH_TAB.md`](WATCH_TAB.md) for the full Watch UX map.

## State keys

| Key | Purpose |
|-----|---------|
| `bdn-personalization-onboarding-completed-v1` | Onboarding done (same as `PersonalizationOnboardingViewModel.completedKey`). |
| `bdn-first-value-tooltip-pending` | One-time hint after **saved** completion (`FirstRunExperience`). Cleared on dismiss or if Watch loads with **no** shows. |

## Why this helps retention

- **Time-to-value** drops: users see a **concrete answer** (“what to watch tonight”) instead of a generic feed.
- **Investment + payoff**: selections immediately **change ranking**, reinforcing that the app “knows” them.
- **Habit hook**: Watch is action-oriented (open streamer, save, rate), which supports **daily return** more than passive browsing.

## Where the “first value moment” is

- **Primary:** Watch tab → **Tonight’s Pick** hero, aligned with onboarding prefs and provider choice, with **Open in [Provider]** when applicable.
- **Secondary:** Optional **FirstValueHintOverlay** explicitly frames that moment as personalized (“We picked this for you”).

## Slow data: risks & mitigations

| Risk | Mitigation in app |
|------|-------------------|
| API slow / empty | Watch already shows **skeletons** while loading; **empty state** with retry; if load finishes with **no** rows, the first-value hint is **cleared** so the user isn’t stuck with a pending tooltip. |
| Hero missing while list has items | Rare (ranking edge); hero uses `filteredShows.first`. Pull-to-refresh and filters remain available. |
| Deep link vs first-run | Deep links still set `AppNavigationState` tabs from `AppDelegate`. If you need “URL always wins” over onboarding, add logic to dismiss the onboarding sheet when a deep link is handled (not implemented here). |

## Optional: Brief instead of Watch

`AppNavigationState.openBriefAsFirstExperience()` is available for A/B tests or product rules; default path is `routeToFirstPersonalizedExperience()` → Watch.
