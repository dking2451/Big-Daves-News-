# Watch Hub — phased architecture

## Label recommendation: **“My List”** (Phase 1)

| Label | Why |
|-------|-----|
| **My List** ✓ | Matches user mental model (“my queue”), fits streaming apps, pairs with “Added to your list” toast. |
| Saved | Accurate for backend flag but feels utilitarian; overflow menu **Saved** still means cross-tab articles + shows. |
| Watch Hub | Reserve for Phase 2 umbrella; using it now over-promises before sections exist. |

**Overflow ••• → Saved** stays the **global** bookmark hub. **Watch header → My List** opens the **Watch Hub** (TV-focused).

---

## Phase 1 (foundation)

- **Entry:** `WatchCompactScreenHeader` — bookmark + **My List**, next to Filter+Help.
- **Toast:** `WatchMyListSaveFeedback` + `WatchSaveConfirmationBanner`; **View My List** → `AppNavigationState.openWatchMyList()`.
- **Routing:** `WatchMyListRoute.list` + `NavigationPath` on `WatchView`’s phone stack.

## Phase 2 (shipped shell — `WatchHubView`)

Single scroll destination (`WatchHubView.swift`):

| Section | Behavior |
|---------|----------|
| **Continue Watching** | Horizontal mock cards + `ProgressView` (copy discloses sample data until playhead API exists). |
| **My List** | Same saved feed + sort + `WatchMyListShowRow` as before; empty state + **Browse Shows**. |
| **Recommended for You** | Second `fetchWatchShows(onlySaved: false)` strip; excludes saved IDs; compact cards + provider launch. |
| **Upcoming From Your List** | Saved titles with `isUpcomingRelease` or release badge `this_week` / `upcoming`. |

`WatchMyListView` remains for a **standalone My List** screen if you deep-link or reuse elsewhere; primary UX is **Watch Hub**.

### Phase 2b (future polish)

- Replace **Continue Watching** mocks with server playhead / last watched percent.
- Add `WatchListItemProgressState` (`notStarted` / `watching` / `completed`) on API + badges on rows.
- Optional nested routes: `enum WatchHubRoute { case hub; case myListOnly }` if you split flows.

---

## Files map

| Area | Role |
|------|------|
| `WatchView.swift` | Path → `WatchHubView`, toast, `setSaved` → feedback |
| `WatchHubView.swift` | Phase 2 hub sections |
| `WatchMyListView.swift` | Standalone list + `WatchMyListDisplay` helpers |
| `WatchMyListSupport.swift` | `WatchMyListRoute`, save toast |
| `AppNavigationState.swift` | `openWatchMyList()` |
