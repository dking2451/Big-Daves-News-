# Personalization onboarding

## What ships

- **5-step flow** (swipeable `TabView` + custom progress): Welcome → Genres → Streaming → Sports (leagues / teams) → Done.
- **Reusable UI**: `PreferenceChip`, `OnboardingScreenLayout`, `OnboardingProgressBar` (`OnboardingComponents.swift`).
- **State**: `PersonalizationOnboardingViewModel` + `LocalUserPreferences` (`UserDefaults`, Codable).
- **First launch**: `RootTabView` presents `PersonalizationOnboardingContainer` until `bdn-personalization-onboarding-completed-v1` is true.
- **Legacy**: Users who completed `bdn-user-prefs-onboarding-completed` are migrated so they don’t see the flow again.
- **Settings**: **My preferences** → `UserPreferencesEditorView` (same store).

## Integrating

1. **Launch gate** (already wired): `RootTabView` uses `@AppStorage("bdn-personalization-onboarding-completed-v1")` and `.sheet { PersonalizationOnboardingContainer }`.
2. **Re-show onboarding** (e.g. debug): reset the key and present the sheet again.
3. **Extend steps**: add a `Step` case, a new `TabView` page, and persist any new fields in `LocalUserPreferences` without changing the overall flow.

## Why this is low-friction

- One tap to start; **Skip** on every step; swipe between pages.
- No account, no passwords; data stays on device.
- Large chips, grouped background, **Dynamic Type** / **VoiceOver** labels on `PreferenceChip`.

## How it improves recommendations

- **Watch**: `applyWatchRanking` boosts titles matching genres + providers.
- **Sports**: `SportsViewModel` orders live / starting-soon by **teams + leagues** from local prefs + synced favorites.
- **Brief**: `BriefViewModel` re-ranks watch picks and sports rows using the same store.

## Future extensions

- Add **Brief-only** signals (e.g. news topics) by extending `LocalUserPreferences` and scoring in `BriefViewModel`—no redesign of the onboarding shell.
- Optional: sync to backend later by POSTing the same payload after login.
