# Watch Hub — phased architecture

## Label recommendation: **“My List”** (Phase 1)

| Label | Why |
|-------|-----|
| **My List** ✓ | Matches user mental model (“my queue”), fits streaming apps, pairs with “Added to your list” toast. |
| Saved | Accurate for backend flag but feels utilitarian; overflow menu **Saved** still means cross-tab articles + shows. |
| Watch Hub | Reserve for Phase 2 umbrella; using it now over-promises before sections exist. |

**Overflow ••• → Saved** stays the **global** bookmark hub. **Watch header → My List** is the **TV-only** list (Phase 1 screen).

---

## Phase 1 (shipped in app)

- **Entry:** `WatchCompactScreenHeader` — bookmark + **My List** (`WatchMyListHeaderButton` style), next to Filter / Help.
- **Destination:** `WatchMyListView` (full screen push on phone, full-screen cover on iPad split).
- **Toast:** `WatchMyListSaveFeedback` + `WatchSaveConfirmationBanner` after successful save; **View My List** calls `AppNavigationState.openWatchMyList()`.
- **Routing:** `WatchMyListRoute` + `NavigationPath` on `WatchView`’s phone stack for programmatic push from toast.

### Phase 2 extension (plan only)

**Container:** Introduce `WatchHubView` as a single `NavigationStack` root that hosts **sections**, without deleting `WatchMyListView`:

```
WatchHubView (future)
├── ContinueWatchingStrip (horizontal, `ProgressView`, mock `lastPosition`)
├── Section: My List → embed `WatchMyListView` **or** `WatchMyListSection` extracted from today’s list body
├── Section: RecommendedForYouStrip (reuse `WatchShowCard` + same API as main feed subset)
├── Section: UpcomingFromYourList (filter `next_episode_air_date` / badges from saved IDs)
```

**Saved show state (future):** Add `WatchListItemState` enum (`notStarted`, `watching`, `completed`) in API + `WatchShowItem` optional field; UI badges on `WatchMyListShowRow` / hub cards. Phase 1 does **not** add columns—only plan enums + `// MARK: - Phase 2` stubs if needed.

**Why Phase 1 is not throwaway:** `WatchMyListView` + row component stay **one section** inside the hub; navigation route stays `.myList` or becomes `.hub(.myList)` with a nested enum:

```swift
enum WatchHubRoute: Hashable {
    case myList
    // case fullHub // later
}
```

---

## Files map

| Area | Phase 1 | Phase 2 |
|------|---------|---------|
| `WatchView.swift` | Path, toast overlay, `setSaved` → feedback | Tab to `WatchHubView` root if product wants unified hub |
| `WatchComponents.swift` | My List header control | Hub chrome |
| `WatchMyListView.swift` | List + empty CTA | Embedded section |
| `WatchMyListSupport.swift` | Route, feedback, banner | Optional hub coordinator |
| `AppNavigationState.swift` | `openWatchMyList()` | Hub deep links |
