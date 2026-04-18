# Live Sports — pre-ship QA (`ls-release-qa`)

Run on **iPhone** and **iPad** (portrait + landscape on iPad). Record pass/fail and build number.

## Ocho mode UX

- [ ] **Cold launch:** Sports opens in **standard** mode (not The Ocho). `SportsView` → `ochoModeEnabled` defaults to `false`.
- [ ] **Enter / exit Ocho:** Toolbar control toggles purple chrome, hero, sections; **Exit** returns to standard list and provider behavior.
- [ ] **Readability:** Ocho hero, ribbons, and Sasquatch asset readable in light/dark.

## Feed quality & labels

- [ ] **Badges:** `LIVE FEED` vs curated/showcase (or equivalent) match server semantics on cards.
- [ ] **Times:** Row copy uses **local** time / status (no hard-coded EDT strings in primary line).
- [ ] **Filter:** With Ocho **off**, alt-only discovery rows behave per product spec; with Ocho **on**, sectioned feed fills.

## Provider & Away mode

- [ ] **Provider:** Availability rings/labels sane for major providers + **Paramount+** where mapped.
- [ ] **Away mode:** Temporary provider override applies, then **reverts** when turned off (`SportsProviderPreferences`).

## Alerts, deep links, quiet hours

- [ ] **Permission:** Enable sports alerts in Settings → system prompt / Settings app as expected.
- [ ] **Refresh:** Foreground app → `SportsAlertsManager.refreshScheduledAlerts` runs (`BigDavesNewsApp` `scenePhase` active); pending local notifications list updates (within ~10 min throttle unless forced).
- [ ] **Fetch:** Alert scheduling uses **`include_ocho=false`** (`ReminderManager` / `APIClient.fetchSportsNow`) — not the Ocho-expanded feed.
- [ ] **Ocho session:** While **in** The Ocho, `ingestLatestSports` is **skipped** so a refresh doesn’t reschedule from Ocho-only items (`SportsView` VM). Background refresh still uses core slate.
- [ ] **Quiet hours:** Toggle quiet hours; fire times that fall in window **do not** schedule (or verify documented behavior).
- [ ] **Digest mode:** Start/close digest notifications match toggles.
- [ ] **Tap notification:** Payload `deep_link` = `sports` → `AppDelegate` / `AppNavigationState.openSports()` → **Sports** tab.

## Empty / loading / error

- [ ] **Loading:** Initial load shows loading / skeleton consistent with `SportsView` + VM.
- [ ] **Error:** Kill network → friendly error + retry when applicable (`errorMessage` states).
- [ ] **Empty slate:** No crash; empty state or copy acceptable for **standard** and **Ocho** paths.

## Regression smoke

- [ ] **Tabs:** No layout breakage on smallest phone + large iPad.
- [ ] **Favorites:** League/team favorites still filter/boost as before.
- [ ] **Live tab badge:** `SportsLiveStatus` / tab badge still reflects live games when data present.

## Code refs (hardening)

| Area | File |
|------|------|
| Alert scheduling + quiet hours | `Sources/ReminderManager.swift` (`SportsAlertsManager`) |
| Ocho off → ingest | `Sources/SportsView.swift` (`LiveSportsViewModel.refresh`) |
| Deep link `sports` | `Sources/AppDelegate.swift`, `AppNavigationState.swift` |
| Foreground refresh | `Sources/BigDavesNewsApp.swift` |

When this checklist is fully **pass** on required devices, mark **`ls-release-qa`** completed in `stickiness_differentiation_plan.md`.
