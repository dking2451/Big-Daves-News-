# Watch tab — current behavior

Developer-facing summary aligned with the shipping UI (header controls, Saved screen, filters).

## Layout (iPhone / compact iPad)

1. **Tonight’s Pick** — Hero (`HeroWatchCardView`): primary streaming action and save.
2. **New Episodes for You** — Horizontal strip when applicable.
3. **More Picks** — Grid of `WatchShowCard` rows.

## Header (`WatchCompactScreenHeader`)

| Control | Appearance | Action |
|--------|------------|--------|
| **My List** | **bookmark.fill** + **My List** label (`NavigationLink` / full-screen on iPad split), `.bordered` + primary tint | **iPhone:** `NavigationStack` push via `WatchMyListRoute.list` → `WatchMyListView`. **iPad split:** full-screen cover + Done. |
| **Filter** | Icon-only **line.3.horizontal.decrease.circle**, same style | Presents `WatchFilterSheet` (large detent). **Dot** on the icon when `WatchFilterPreferences.hasNonDefaultFilters` is true. |
| **Help** | Icon-only **questionmark.circle** (`AppHelpButton` with `chrome: .watchHeaderBordered`), same bordered style | Presents `AppHelpView` (same sheet as Headlines toolbar help). |

Save confirmation: after a successful save on Watch, `WatchMyListSaveFeedback` shows **Added to your list** with **View My List** (`AppNavigationState.openWatchMyList()`).

VoiceOver: labels **Saved** / **Filters** and hints describe the action (icon-only UI).

## My List (`WatchMyListView`)

- Loads `fetchWatchShows(..., onlySaved: true)` (same contract as `SavedHubView`’s shows segment).
- Title **Saved**, subtitle **Shows you want to start**.
- Toolbar **Sort**: Recently Saved, New Episodes, Ready to Watch.
- Rows: poster (`WatchShowPosterImage`), provider line, `StreamingProviderLaunchControl` (`.cardCompact`), badges via `WatchBadgeFormatting` (e.g. new episode).
- Empty: “Save shows to build your watch list.”
- Remove: context menu **Remove from Saved** → `setWatchSaved(..., saved: false)`.

## Cross-app “Saved” vs Watch header Saved

- **Overflow menu (•••) → Saved** opens `SavedHubView`: **articles** and **shows** together.
- **Watch header My List** opens the **Watch-only** saved TV list (`WatchMyListView`).

Phase 2 hub plan: [`WATCH_HUB_PHASES.md`](WATCH_HUB_PHASES.md).

## In-app help surfaces

- **Watch toolbar → info (How Watch works)** — `watchGuideSheet` in `WatchView.swift`: header icons, recommendations, card actions, badges.
- **Help (?)** — `AppHelpView` in `AppOverflowMenu.swift`: app-wide bullets including Saved hub vs Watch header.

## Related docs

- [`HERO_WATCH_CARD.md`](HERO_WATCH_CARD.md) — Tonight’s Pick hero.
- [`STREAMING_PROVIDER_LAUNCH.md`](STREAMING_PROVIDER_LAUNCH.md) — Provider launch control styles.
- [`FIRST_RUN_UX.md`](FIRST_RUN_UX.md) — First-run / Watch guide timing.
