---
name: Stickiness Differentiation Plan
overview: Define a phased, implementation-ready roadmap to improve daily retention and market differentiation through habit loops, personalization, and native utility. Prioritize a shippable first sprint with clear acceptance criteria and measurable outcomes.
todos:
  - id: t1-saved-queue
    content: Design and implement unified Saved queue for articles and shows (backend + iOS).
    status: completed
  - id: f1-event-tracking
    content: Add core client/server events for brief opens, article saves/opens, and watch reactions.
    status: completed
  - id: t2-resume-card
    content: Add Continue/Resume card in Brief from last-opened article or show.
    status: completed
  - id: t3-evening-wrap
    content: Implement time-aware Evening Wrap section in Brief.
    status: completed
  - id: t4-brief-streak
    content: Add daily brief streak tracking and subtle in-app reinforcement.
    status: completed
  - id: ls-m1-data-pipeline
    content: Build Live Sports now/next-4-hours backend pipeline with caching and timezone normalization.
    status: completed
  - id: ls-m2-provider-filter
    content: Add provider profile and network mapping for provider-aware sports availability.
    status: completed
  - id: ls-m2-5-temp-provider
    content: Add temporary provider override mode for away-from-home viewing and instant revert to default provider.
    status: completed
  - id: ls-m3-favorites
    content: Add favorites preferences for teams and leagues with persistence and sync.
    status: completed
  - id: ls-m4-ios-screen
    content: Add Live Sports iOS screen with Live Now and Starting Soon sections.
    status: completed
  - id: ls-m5-smart-sort
    content: Implement Live Sports ranking (live plus available first, favorites boost).
    status: completed
  - id: ls-m6-telemetry
    content: Add sports telemetry events (open, provider filter, follow toggle, card open).
    status: completed
  - id: ls-v2-apple-sports
    content: Add Apple Sports companion deep-links and detail routing.
    status: completed
  - id: ls-v2-team-rail
    content: Add Your Teams Today personalized rail in Brief/Home from sports favorites.
    status: completed
  - id: ls-v2-alerts
    content: Add game start and close-game alerts with quiet hours and digest mode.
    status: completed
  - id: ls-v3-ocho-obscure
    content: Add Ocho filter for obscure sports (bare knuckle boxing, triangle bareknuckle boxing in the Mighty Trygon, slap fighting, MMA, American sumo wrestling, Australian rules football) as a fallback when mainstream slate is light.
    status: completed
  - id: ui-polish-pass
    content: Run cross-screen UI polish pass (consistent spacing rhythm, card elevation consistency, and subtle haptics for high-frequency actions).
    status: completed
isProject: false
---

# Stickiness and Differentiation Roadmap

## Outcomes

- Increase daily/weekly retention via recurring habit surfaces (`Brief`, reminders, evening wrap).
- Build user-specific value via saves, follows, and recommendation signals.
- Improve App Review defensibility by emphasizing native behaviors over passive content browsing.

## Next Up (Top Priority)

1. **Live Sports QA + App Store hardening**
  - Run test pass for alerts scheduling, deep-link opens, and quiet-hour behavior before release.
2. **LS-V2.4 Recommendation Blending**
  - Feed sports preferences into Brief/Headlines ranking.
3. **Post-ship Ocho feed quality expansion**
  - Add additional real-feed adapters and reduce showcase fallback frequency.

### Live Sports Release QA Checklist (Pre-Ship)

- **Ocho mode UX**
  - Toggle Ocho on/off on iPhone + iPad; verify default is off on cold launch.
  - Verify Ocho header readability, sasquatch framing, and purple icon/indicator consistency.
- **Feed quality and transparency**
  - Verify `LIVE FEED` vs `SHOWCASE` badges appear correctly on cards.
  - Confirm Ocho list shows local-time status lines (no EDT/ET dependency in row copy).
  - Validate Ocho filtering only shows alternate sports when enabled.
- **Provider behavior**
  - Validate provider availability matching for major providers plus `Paramount+`.
  - Confirm temporary provider (Away Mode) still works and reverts correctly.
- **Alerts and deep-links**
  - Validate game start and close-game alerts scheduling/refresh on app active.
  - Tap sports alert notifications and confirm deep-link opens Sports tab.
  - Validate quiet-hours and digest settings behavior.
- **General ship hardening**
  - Validate empty/loading/error states in Sports for both normal and Ocho modes.
  - Smoke-test on phone + iPad for layout regressions and interaction polish.

## Phase 1 (Now, 2 weeks)

- **T1 Unified Saved Queue (Articles + Shows)**
  - Add article save/unsave actions from Headlines and a unified Saved destination with segmented control.
  - Acceptance: save/unsave works, persists across launches, and supports both articles and shows.
- **T2 Continue/Resume Card**
  - Track last-opened article/show and surface one-tap resume in Brief.
  - Acceptance: resume card appears after interaction and deep-links correctly.
- **T3 Evening Wrap MVP**
  - Add a time-aware wrap section in Brief showing top updates, weather delta, and watch picks.
  - Acceptance: visible in evening window and refreshes cleanly.
- **T4 Brief Streak + Gentle Reinforcement**
  - Track daily brief-open streak and show subtle in-app reinforcement.
  - Acceptance: increments once/day, resets on missed day.

## Phase 2 (Next, 2 weeks)

- **T5 My Topics (Follow/Unfollow)**
  - Add topic preferences and apply ranking boosts in Headlines/Watch.
- **T6 Notification Preference Matrix**
  - Add granular toggles for digest, weather severity, watch episodes, and breaking alerts.
- **T7 Digest Notification Mode**
  - Bundle content into low-noise daily digests with deep-link to Brief.

## Phase 3 (Later, 2-4 weeks)

- **T8 For You Ranking v1**
  - Rank blend from reads, saves, reactions, followed topics, recency.
- **T9 Why Recommended Chips**
  - Add explanation chips tied to explicit user signals.
- **T10 Hyperlocal Signal Expansion**
  - Expand ZIP-aware local relevance and regional source quality.

## Phase 4 (New: Live Sports Stickiness Track)

- **LS-M1 Live Sports Data Pipeline**
  - Build backend `sports_now` aggregation for `live now` and `next 4 hours`.
  - Normalize team/league/time/network/status fields and add cache (5-10 minute TTL).
  - Status: completed.
- **LS-M2 Provider Mapping + Availability**
  - Store user TV provider and map game networks to provider availability.
  - Return `available_on_provider` and readable network labels.
  - Status: completed.
- **LS-M2.5 Temporary Provider Override (Away Mode)**
  - Add a temporary provider selection for travel/away scenarios without changing default provider.
  - Revert to default provider instantly when override is disabled.
  - Status: completed.
- **LS-M3 Favorites Preferences (Teams + Leagues)**
  - Add favorites storage/sync for teams and leagues plus selected provider.
  - Reuse device-based preference model and settings sync behavior.
  - Status: completed.
- **LS-M4 iOS Live Sports Screen**
  - Add new `Live Sports` surface with:
    - `Live Now`
    - `Starting Soon (next 4h)`
  - Add provider and favorites filters.
  - Status: completed (provider filter live; favorites filter pending LS-M3).
- **LS-M5 Smart Sort v1**
  - Prioritize: live+available, upcoming+available, favorites, then all others.
  - Status: completed.
- **LS-M6 Telemetry**
  - Track `sports_open`, `sports_filter_provider`, `sports_follow_toggle`, `sports_card_open`.
  - Status: completed (`sports_open`, `sports_filter_provider`, `sports_follow_toggle`, `sports_card_open`, window/temporary provider events, and sports-alert open/settings telemetry shipped).

### Live Sports V2 (Differentiator)

- **LS-V2.1 Apple Sports Companion**
  - Add optional Apple Sports deep-link from game cards for richer details.
  - Status: completed.
- **LS-V2.2 Personalized Team Rail**
  - Add `Your Teams Today` rail in Brief/Home.
  - Status: completed (Brief rail shipped).
- **LS-V2.3 Sports Alerts**
  - Add start-soon and close-game alerts with quiet-hours and digest controls.
  - Status: completed (settings controls, scheduling engine, and Sports deep-link opens shipped).
- **LS-V2.4 Recommendation Blending**
  - Use sports preferences to influence headlines/brief ranking.

### Live Sports V3 (Fun/Discovery)

- **LS-V3.1 The Ocho Filter (Obscure Sports)**
  - Add an `Ocho` mode/filter in Sports to surface non-mainstream events when major-league slate is thin.
  - Initial sports set: bare knuckle boxing, triangle bareknuckle boxing in the Mighty Trygon, slap fighting, MMA, American sumo wrestling, Australian rules football.
  - Include clear labeling so users understand these are discovery/filler events, not primary league feed.
  - Status: completed (Ocho mode UX shipped, source labeling added, and real-feed coverage expanded with controlled showcase backfill).

### UX Polish (Completed)

- **UI-P1 Cross-Screen Polish Pass**
  - Standardize section spacing rhythm across core tabs.
  - Extend premium card feel consistency and add subtle haptics for save/favorite/filter interactions.
  - Status: completed.

## Technical Foundation (Parallel)

- **F1 Event Tracking Schema**
  - Track: `brief_open`, `article_open`, `article_save`, `watch_reaction`, `push_open`, `resume_open`.
- **F2 Retention Dashboard**
  - Monitor: DAU/WAU, D1/D7/D30, sessions/user/day, push CTR, save rate.

## Initial File Map (for Phase 1 implementation)

- iOS UI and interactions
  - [ios/BigDavesNewsApp/Sources/HeadlinesView.swift](/Users/dave/Desktop/Cursor/ios/BigDavesNewsApp/Sources/HeadlinesView.swift)
  - [ios/BigDavesNewsApp/Sources/BriefView.swift](/Users/dave/Desktop/Cursor/ios/BigDavesNewsApp/Sources/BriefView.swift)
  - [ios/BigDavesNewsApp/Sources/WatchView.swift](/Users/dave/Desktop/Cursor/ios/BigDavesNewsApp/Sources/WatchView.swift)
  - [ios/BigDavesNewsApp/Sources/SettingsView.swift](/Users/dave/Desktop/Cursor/ios/BigDavesNewsApp/Sources/SettingsView.swift)
- iOS API models/client
  - [ios/BigDavesNewsApp/Sources/API.swift](/Users/dave/Desktop/Cursor/ios/BigDavesNewsApp/Sources/API.swift)
- Backend API/data layer
  - [app/main.py](/Users/dave/Desktop/Cursor/app/main.py)
  - [app/watch.py](/Users/dave/Desktop/Cursor/app/watch.py)
  - [app/models.py](/Users/dave/Desktop/Cursor/app/models.py)
  - [app/db.py](/Users/dave/Desktop/Cursor/app/db.py)

## Execution Order

1. Implement **T1 Unified Saved Queue** end-to-end (API + iOS UI + persistence).
2. Add **F1 event tracking** hooks for saved/open actions.
3. Implement **T2 Resume Card** in Brief using tracked last-opened content.
4. Implement **T3 Evening Wrap** as a time-aware extension of Brief.
5. Add **T4 Streak** and validate retention instrumentation.

