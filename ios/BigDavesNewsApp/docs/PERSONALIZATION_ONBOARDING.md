# Personalization onboarding

## What ships

- **7-step flow** (swipeable `TabView` + custom progress): Welcome → Genres → Streaming → **Live TV for sports** (`SportsProviderPreferences`) → **Sports leagues** → **Sports teams** → Done.
- **Reusable UI**: `OnboardingScreenLayout` (pinned footer + scroll + `ScrollViewProxy` for league jump), `OnboardingProgressBar`, `PreferenceChip` (`OnboardingComponents.swift`).
- **Selection UI** (`OnboardingSelectionComponents.swift`): **choice cards** (`OnboardingChoiceCard` + `OnboardingGenreCardGrid` / `OnboardingStreamingCardGrid`), **list rows** (`OnboardingSelectableRow`), **leagues** (search + horizontal **spotlight deck** + **categorized** sections), **teams** (search + league jump pills + `TeamLeagueGroupSection`; leagues chosen on the prior step are **ordered first**).
- **Team data**: `Resources/TeamsCatalog.json` (bundled rosters); `SportsFavoritesCatalog` falls back to embedded lists if the JSON is missing.
- **State**: `PersonalizationOnboardingViewModel` + `LocalUserPreferences` (`UserDefaults`, Codable). On completion, **live TV provider** is written to `bdn-sports-provider-key-ios` and **`bdn-sports-availability-only-ios`** is set to `true` when a specific provider is chosen (so Sports can match broadcast availability).
- **First launch**: `RootTabView` presents `PersonalizationOnboardingContainer` until `bdn-personalization-onboarding-completed-v1` is true.
- **Legacy**: Users who completed `bdn-user-prefs-onboarding-completed` are migrated so they don’t see the flow again.
- **Settings**: **My preferences** → `UserPreferencesEditorView` (same store).

## Integrating

1. **Launch gate** (already wired): `RootTabView` uses `@AppStorage("bdn-personalization-onboarding-completed-v1")` and `.fullScreenCover { PersonalizationOnboardingContainer }`.
2. **Replay**: Settings → Help → **Replay personalization onboarding**, or the Help screen → **Onboarding** → same. Calls `PersonalizationOnboardingReplay.trigger()` (resets completion flag, clears first-value tooltip pending, posts `Notification.Name.bdnReplayPersonalizationOnboarding`).
3. **Re-show manually** (e.g. debug): reset `bdn-personalization-onboarding-completed-v1` in UserDefaults, or delete/reinstall the app.
4. **Extend steps**: add a `Step` case, a new `TabView` page, and persist any new fields in `LocalUserPreferences` without changing the overall flow.

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
