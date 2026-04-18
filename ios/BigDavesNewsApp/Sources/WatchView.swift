import SwiftUI
import Foundation

/// **Watch tab hierarchy (UX):**
/// 1. **Tonight's pick** — Hero card from `filteredShows.first` with trust-building recommendation copy (no raw low match %).
/// 2. **New Episodes for You** — Horizontal strip for `isNewEpisode` from saved / seen / liked shows.
/// 3. **More Picks** — Two-column recommendation cards with sentence-style reasons and neutral mini-actions.
struct WatchView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tonightModeActive) private var tonightModeActive
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var navigation = AppNavigationState.shared
    @ObservedObject private var localUserPreferences = LocalUserPreferences.shared
    @State private var allShows: [WatchShowItem] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @StateObject private var filterPrefs = WatchFilterPreferences()
    @State private var pendingRatingShow: WatchShowItem?
    @State private var showBadgeGuide = false
    @State private var showFilterSheet = false
    @State private var showMyListFullScreen = false
    /// Phone stack: programmatic push for "View My List" from save toast.
    @State private var watchNavPath = NavigationPath()
    @State private var selectedSplitShowID: WatchShowItem.ID?
    @State private var rankDebugInspectItem: WatchShowItem?
    @State private var lastWatchRankDebugRoot: WatchRankDebugRoot?

    @AppStorage("bdn-watch-guide-seen-ios") private var hasSeenWatchGuide = false
    @AppStorage("bdn-watch-rank-debug-request-ios") private var watchRankDebugRequest = false
    @AppStorage(FirstRunExperience.firstValueTooltipPendingKey) private var firstValueTooltipPending = false
    @AppStorage("bdn-watch-seen-genre-migrated-ios") private var didMigrateSeenGenre = false
    @State private var previousMyListAPIFetch: Bool = false

    private let deviceID = WatchDeviceIdentity.current
    private var padH: CGFloat { DeviceLayout.horizontalPadding }
    private var contentMaxWidth: CGFloat { DeviceLayout.contentMaxWidth }

    /// Dark-first canvas; optional Tonight Mode dim overlay.
    private var watchScreenBackground: some View {
        ZStack {
            AppTheme.watchScreenBackground(for: colorScheme)
            if tonightModeActive {
                AppTheme.tonightBackgroundOverlay(for: colorScheme)
            }
        }
    }

    private var useSplitDetail: Bool {
        DeviceLayout.isPad && DeviceLayout.useRegularWidthTabletLayout(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        Group {
            if useSplitDetail {
                NavigationSplitView {
                    splitSidebar
                } detail: {
                    splitDetail
                }
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else {
                NavigationStack(path: $watchNavPath) {
                    phoneOrCompactColumn
                        .modifier(watchToolbar)
                        .navigationDestination(for: WatchMyListRoute.self) { _ in
                            WatchHubView()
                        }
                }
            }
        }
        .overlay(alignment: .bottom) {
            WatchSaveConfirmationBanner()
                .padding(.bottom, 6)
        }
        .fullScreenCover(isPresented: $showMyListFullScreen) {
            NavigationStack {
                WatchHubView(showsDismissButton: true)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            WatchFilterSheet(
                filterPrefs: filterPrefs,
                providerOptions: providerChipOptions,
                genreOptions: genreChipOptions,
                myListSortOptions: myListSortOptions
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $rankDebugInspectItem) { show in
            WatchRankDebugSheet(show: show, tonightSection: lastWatchRankDebugRoot?.tonightPick)
        }
        .onChange(of: filterPrefs.listScope) { _ in Task { await refresh() } }
        .onChange(of: filterPrefs.showWatched) { _ in Task { await refresh() } }
        .onChange(of: filterPrefs.selectedGenres) { _ in
            let now = filterPrefs.onlySavedAPI
            if now != previousMyListAPIFetch {
                previousMyListAPIFetch = now
                Task { await refresh() }
            }
        }
        .confirmationDialog(
            "Rate this show",
            isPresented: Binding(
                get: { pendingRatingShow != nil },
                set: { presented in
                    if !presented {
                        pendingRatingShow = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Thumbs Up") {
                guard let show = pendingRatingShow else { return }
                pendingRatingShow = nil
                Task { await setReaction(showID: show.id, reaction: "up") }
            }
            Button("Pass") {
                guard let show = pendingRatingShow else { return }
                pendingRatingShow = nil
                Task { await setReaction(showID: show.id, reaction: "down") }
            }
            Button("Skip", role: .cancel) {
                pendingRatingShow = nil
            }
        } message: {
            if let show = pendingRatingShow {
                Text("How was \(show.title)? Your rating helps personalize recommendations.")
            }
        }
        .sheet(isPresented: $showBadgeGuide) {
            watchGuideSheet
        }
        .onAppear {
            hydrateWatchFromDiskCacheIfNeeded()
        }
        .task {
            migrateLegacyGenreIfNeeded()
            previousMyListAPIFetch = filterPrefs.onlySavedAPI
            await MainActor.run {
                hydrateWatchFromDiskCacheIfNeeded()
            }
            // Stale-while-revalidate: cached rows keep the grid alive while `/api/watch` completes (backend can be slow).
            await refresh()
            if !hasSeenWatchGuide {
                if firstValueTooltipPending {
                    // Defer "How Watch works" until first-value hint dismisses (or clears below).
                } else {
                    hasSeenWatchGuide = true
                    showBadgeGuide = true
                }
            }
        }
        .onChange(of: isLoading) { loading in
            guard !loading, firstValueTooltipPending else { return }
            if allShows.isEmpty {
                firstValueTooltipPending = false
                if !hasSeenWatchGuide {
                    hasSeenWatchGuide = true
                }
            }
        }
        .onChange(of: gridShows.map(\.id).joined(separator: "|")) { _ in
            guard useSplitDetail else { return }
            let ids = gridShows.map(\.id)
            if let id = selectedSplitShowID, ids.contains(id) { return }
            selectedSplitShowID = ids.first ?? tonightsPick?.id
        }
        .onChange(of: navigation.watchMyListOpenNonce) { _ in
            guard navigation.selectedTab == .watch else { return }
            if useSplitDetail {
                showMyListFullScreen = true
            } else {
                watchNavPath.append(WatchMyListRoute.list)
            }
        }
    }

    private var watchToolbar: WatchToolbarModifier {
        WatchToolbarModifier()
    }

    private func openMyListFromToolbar() {
        if useSplitDetail {
            showMyListFullScreen = true
        } else {
            watchNavPath.append(WatchMyListRoute.list)
        }
    }

    // MARK: - Split (iPad regular)

    private var splitSidebar: some View {
        Group {
            if isLoading && allShows.isEmpty {
                List {
                    ForEach(0..<8, id: \.self) { _ in
                        WatchCardSkeleton()
                    }
                }
                .navigationTitle("Watch")
                .redacted(reason: .placeholder)
            } else if !errorMessage.isEmpty && allShows.isEmpty {
                VStack(spacing: WatchDesign.spaceSM) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Couldn't load Watch")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .navigationTitle("Watch")
            } else {
                ScrollViewReader { listProxy in
                    List(selection: $selectedSplitShowID) {
                        Section {
                            WatchCompactScreenHeader(
                                title: "Watch",
                                showsFilterDot: filterPrefs.hasNonDefaultFilters,
                                compact: true,
                                showsToolbarControls: true,
                                onMyListTap: { showMyListFullScreen = true },
                                onFilter: { showFilterSheet = true },
                                onInfoTap: {
                                    hasSeenWatchGuide = true
                                    showBadgeGuide = true
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                            if firstValueTooltipPending, tonightsPick != nil {
                                FirstValueHintOverlay(onDismiss: dismissFirstValueHint)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }

                            if let pick = tonightsPick {
                                HeroWatchCardView(
                                    model: HeroWatchCardModel(show: pick, rankingBatch: allShows),
                                    onPrimaryAction: {
                                        Task {
                                            _ = await StreamingProviderLauncher.open(for: pick)
                                        }
                                    },
                                    onSecondaryAction: {
                                        Task { await setSaved(showID: pick.id, saved: !(pick.saved ?? false)) }
                                    },
                                    onCardTap: {
                                        selectedSplitShowID = pick.id
                                        AppHaptics.selection()
                                    },
                                    tonightEmphasis: tonightModeActive,
                                    onInspectRankDebug: { rankDebugInspectItem = pick },
                                    sourceShow: pick
                                )
                                .id("tonightPickAnchor")
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }

                            if !continueWatchingStrip.isEmpty {
                                VStack(alignment: .leading, spacing: WatchDesign.spaceSM) {
                                    WatchSectionHeader(title: "Continue Watching")
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: WatchDesign.spaceSM) {
                                            ForEach(Array(continueWatchingStrip.enumerated()), id: \.element.id) { index, show in
                                                WatchHubRecommendationCard(
                                                    show: show,
                                                    listIndex: index,
                                                    batch: continueWatchingStrip
                                                )
                                                .onTapGesture {
                                                    selectedSplitShowID = show.id
                                                    AppHaptics.selection()
                                                }
                                            }
                                        }
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }

                            if !watchFromYourListStrip.isEmpty {
                                VStack(alignment: .leading, spacing: WatchDesign.spaceSM) {
                                    WatchSectionHeader(title: "From Your List")
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: WatchDesign.spaceSM) {
                                            ForEach(Array(watchFromYourListStrip.enumerated()), id: \.element.id) { index, show in
                                                WatchHubRecommendationCard(
                                                    show: show,
                                                    listIndex: index,
                                                    batch: watchFromYourListStrip
                                                )
                                                .onTapGesture {
                                                    selectedSplitShowID = show.id
                                                    AppHaptics.selection()
                                                }
                                            }
                                        }
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }

                            if !newEpisodesForYou.isEmpty {
                                VStack(alignment: .leading, spacing: WatchDesign.spaceSM) {
                                    WatchSectionHeader(title: "New Episodes for You")
                                    WatchNewEpisodesCarousel(
                                        items: newEpisodesForYou,
                                        rankingBatch: allShows,
                                        onToggleSaved: { show, saved in
                                            Task { await setSaved(showID: show.id, saved: saved) }
                                        },
                                        onSelect: { show in
                                            selectedSplitShowID = show.id
                                            AppHaptics.selection()
                                        },
                                        onCycleWatchProgress: { show in
                                            Task { await cycleWatchProgress(showID: show.id) }
                                        },
                                        onReaction: { show, reaction in
                                            Task { await setReaction(showID: show.id, reaction: reaction) }
                                        },
                                        onCaughtUp: { show in
                                            Task { await markCaughtUp(showID: show.id, releaseDate: show.releaseDate) }
                                        }
                                    )
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }

                        if !gridShows.isEmpty {
                            Section {
                                ForEach(gridShows) { show in
                                    WatchSplitSidebarRow(show: show)
                                        .tag(show.id)
                                }
                            } header: {
                                WatchSectionHeader(title: "More Picks")
                                    .textCase(nil)
                            }
                        }
                }
                .navigationTitle("")
                .scrollContentBackground(.hidden)
                .background(watchScreenBackground)
                .refreshable { await refresh() }
                .onAppear {
                    if selectedSplitShowID == nil {
                        selectedSplitShowID = tonightsPick?.id ?? gridShows.first?.id
                    }
                }
                .onChange(of: navigation.watchTonightScrollNonce) { _ in
                    guard tonightsPick != nil else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        listProxy.scrollTo("tonightPickAnchor", anchor: .top)
                    }
                }
                }
            }
        }
        .modifier(watchToolbar)
    }

    @ViewBuilder
    private var splitDetail: some View {
        if let id = selectedSplitShowID, let show = (gridShows + (tonightsPick.map { [$0] } ?? [])).first(where: { $0.id == id }) {
            ScrollView {
                WatchShowCard(
                    show: show,
                    recommendationReason: WatchCardRecommendation.listReasonLine(
                        for: show,
                        listIndex: nil,
                        rankingBatch: allShows,
                        badgeBatch: gridShows
                    ),
                    listIndex: nil,
                    badgeBatch: gridShows,
                    onCycleWatchProgress: { Task { await cycleWatchProgress(showID: show.id) } },
                    onReaction: { reaction in Task { await setReaction(showID: show.id, reaction: reaction) } },
                    onToggleSaved: { value in Task { await setSaved(showID: show.id, saved: value) } },
                    onCaughtUp: { Task { await markCaughtUp(showID: show.id, releaseDate: show.releaseDate) } },
                    onInspectRankDebug: { rankDebugInspectItem = show }
                )
                .padding()
            }
            .background(watchScreenBackground)
        } else {
            VStack(spacing: WatchDesign.spaceSM) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Select a show")
                    .font(.headline)
                Text("Choose a title from the list to see details and actions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(watchScreenBackground)
        }
    }

    // MARK: - Phone / compact iPad

    private var phoneOrCompactColumn: some View {
        Group {
            if isLoading && allShows.isEmpty {
                ScrollView {
                    watchHeaderBlock
                    LazyVStack(spacing: WatchDesign.spaceSM) {
                        ForEach(0..<6, id: \.self) { _ in
                            WatchCardSkeleton()
                        }
                    }
                    .padding(.horizontal, padH)
                    .padding(.vertical, 10)
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(watchScreenBackground)
                .redacted(reason: .placeholder)
            } else if !errorMessage.isEmpty && allShows.isEmpty {
                ScrollView {
                    watchHeaderBlock
                    AppContentStateCard(
                        kind: .error,
                        systemImage: "wifi.exclamationmark",
                        title: "Couldn't load Watch",
                        message: errorMessage,
                        retryTitle: "Try again",
                        onRetry: { Task { await refresh() } },
                        isRetryDisabled: isLoading,
                        compact: false
                    )
                    .padding(.horizontal, padH)
                }
                .background(watchScreenBackground)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        watchHeaderBlock

                        if tonightModeActive && tonightsPick != nil {
                            tonightJumpButton(scrollProxy: proxy)
                        }

                        if firstValueTooltipPending, tonightsPick != nil {
                            FirstValueHintOverlay(onDismiss: dismissFirstValueHint)
                                .padding(.horizontal, padH)
                                .padding(.bottom, 6)
                        }

                        if let pick = tonightsPick {
                            HeroWatchCardView(
                                model: HeroWatchCardModel(show: pick, rankingBatch: allShows),
                                onPrimaryAction: {
                                    Task {
                                        _ = await StreamingProviderLauncher.open(for: pick)
                                    }
                                },
                                onSecondaryAction: {
                                    Task { await setSaved(showID: pick.id, saved: !(pick.saved ?? false)) }
                                },
                                onCardTap: nil,
                                tonightEmphasis: tonightModeActive,
                                onInspectRankDebug: { rankDebugInspectItem = pick },
                                sourceShow: pick
                            )
                            .id("tonightPickAnchor")
                            .padding(.horizontal, padH)

                            // Nudge when no streaming apps have been configured yet.
                            if pick.providers.isEmpty && (pick.primaryProvider == nil || pick.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) {
                                Button {
                                    NotificationCenter.default.post(name: .bdnReplayPersonalizationOnboarding, object: nil)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "play.rectangle.on.rectangle")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.accent)
                                        Text("Add your streaming apps for direct launch links")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.subtitle)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.subtitle.opacity(0.5))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, padH)
                                .transition(.opacity)
                            }
                        }

                        if !continueWatchingStrip.isEmpty {
                            VStack(alignment: .leading, spacing: WatchDesign.spaceSM) {
                                WatchSectionHeader(title: "Continue Watching")
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: WatchDesign.spaceSM) {
                                        ForEach(Array(continueWatchingStrip.enumerated()), id: \.element.id) { index, show in
                                            WatchHubRecommendationCard(
                                                show: show,
                                                listIndex: index,
                                                batch: continueWatchingStrip
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, padH)
                            .padding(.top, 8)
                        }

                        if !watchFromYourListStrip.isEmpty {
                            VStack(alignment: .leading, spacing: WatchDesign.spaceSM) {
                                WatchSectionHeader(title: "From Your List")
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: WatchDesign.spaceSM) {
                                        ForEach(Array(watchFromYourListStrip.enumerated()), id: \.element.id) { index, show in
                                            WatchHubRecommendationCard(
                                                show: show,
                                                listIndex: index,
                                                batch: watchFromYourListStrip
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, padH)
                            .padding(.top, 8)
                        }


                        if !newEpisodesForYou.isEmpty {
                            VStack(alignment: .leading, spacing: WatchDesign.spaceSM) {
                                WatchSectionHeader(title: "New Episodes for You")
                                WatchNewEpisodesCarousel(
                                    items: newEpisodesForYou,
                                    rankingBatch: allShows,
                                    onToggleSaved: { show, saved in
                                        Task { await setSaved(showID: show.id, saved: saved) }
                                    },
                                    onSelect: { _ in },
                                    onCycleWatchProgress: { show in
                                        Task { await cycleWatchProgress(showID: show.id) }
                                    },
                                    onReaction: { show, reaction in
                                        Task { await setReaction(showID: show.id, reaction: reaction) }
                                    },
                                    onCaughtUp: { show in
                                        Task { await markCaughtUp(showID: show.id, releaseDate: show.releaseDate) }
                                    }
                                )
                            }
                            .padding(.horizontal, padH)
                            .padding(.top, 6)
                        }

                        if filterPrefs.hasNonDefaultFilters {
                            HStack(spacing: WatchDesign.spaceXS) {
                                Label("\(filteredShows.count) results", systemImage: "line.3.horizontal.decrease.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Reset Filters") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        filterPrefs.reset()
                                    }
                                    Task { await refresh() }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                            }
                            .padding(.horizontal, padH)
                            .padding(.top, 6)
                        }

                        Group {
                            if filteredShows.isEmpty {
                                emptyStateView
                            } else if !gridShows.isEmpty {
                                VStack(alignment: .leading, spacing: morePicksHeaderToGridSpacing) {
                                    WatchSectionHeader(title: "More Picks")
                                    LazyVGrid(columns: watchCardColumns, alignment: .leading, spacing: WatchDesign.spaceSM) {
                                        ForEach(Array(gridShows.enumerated()), id: \.element.id) { index, show in
                                            WatchShowCard(
                                                show: show,
                                                recommendationReason: WatchCardRecommendation.listReasonLine(
                                                    for: show,
                                                    listIndex: index,
                                                    rankingBatch: allShows,
                                                    badgeBatch: gridShows
                                                ),
                                                listIndex: index,
                                                badgeBatch: gridShows,
                                                onCycleWatchProgress: {
                                                    Task { await cycleWatchProgress(showID: show.id) }
                                                },
                                                onReaction: { reaction in
                                                    Task { await setReaction(showID: show.id, reaction: reaction) }
                                                },
                                                onToggleSaved: { value in
                                                    Task { await setSaved(showID: show.id, saved: value) }
                                                },
                                                onCaughtUp: {
                                                    Task { await markCaughtUp(showID: show.id, releaseDate: show.releaseDate) }
                                                },
                                                onInspectRankDebug: { rankDebugInspectItem = show }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, padH)
                        .padding(.vertical, watchMoreGroupVerticalPadding)
                        .frame(maxWidth: contentMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .background(watchScreenBackground)
                    .refreshable {
                        await refresh()
                    }
                    .onChange(of: navigation.watchTonightScrollNonce) { _ in
                        guard tonightsPick != nil else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo("tonightPickAnchor", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func tonightJumpButton(scrollProxy: ScrollViewProxy) -> some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                AppHaptics.lightImpact()
                withAnimation(.easeInOut(duration: 0.35)) {
                    scrollProxy.scrollTo("tonightPickAnchor", anchor: .top)
                }
            } label: {
                Label("What should I watch tonight?", systemImage: "sparkles.tv.fill")
                    .font(.footnote.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, padH)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Scrolls to Tonight's pick.")
    }

    private func dismissFirstValueHint() {
        firstValueTooltipPending = false
        if !hasSeenWatchGuide {
            hasSeenWatchGuide = true
        }
    }

    private var watchHeaderBlock: some View {
        WatchCompactScreenHeader(
            title: "Watch",
            showsFilterDot: filterPrefs.hasNonDefaultFilters,
            compact: false,
            showsToolbarControls: true,
            onMyListTap: openMyListFromToolbar,
            onFilter: { showFilterSheet = true },
            onInfoTap: {
                hasSeenWatchGuide = true
                showBadgeGuide = true
            }
        )
        .padding(.horizontal, padH)
        .padding(.top, 8)
    }

    private var watchGuideSheet: some View {
        NavigationStack {
            List {
                Section("Next to "Watch"") {
                    Label("Bookmark: opens My List, your hub for everything you've saved on Watch.", systemImage: "bookmark.fill")
                    Label("Filters: genres, providers, and list scope. A dot on the icon means filters are on.", systemImage: "line.3.horizontal.decrease")
                    Label("Info: opens this Watch guide. App-wide Help (all tabs, feedback, replay onboarding) is under ••• on Headlines and other tabs — not on this screen.", systemImage: "info.circle")
                    Label("Saved hub: ••• menu on Headlines (and most tabs) — bookmarked articles and shows from across the app in one place.", systemImage: "ellipsis.circle")
                }
                Section("Inside My List") {
                    Label("Start Watching: your best next play from saved shows, with a quick Open action.", systemImage: "play.circle")
                    Label("From Your List: titles that need attention soon, shown as a horizontal strip.", systemImage: "list.bullet")
                    Label("All saved: full list of saves. Use the sort control in the toolbar to change how rows are ordered.", systemImage: "arrow.up.arrow.down")
                    Label("Upcoming: releases coming up on titles you've already saved.", systemImage: "calendar")
                }
                Section("Recommended in My List") {
                    Label("Recommended for You uses compact cards: small icons on the poster mean the same kinds of status as full badges (trending, timing, new, and more). Open launches your streaming app when we know the provider.", systemImage: "rectangle.split.2x1")
                    Label("Horizontal strips on Watch use the same card style for quick picks from your list.", systemImage: "play.tv")
                }
                Section("How recommendations work") {
                    Label("Thumbs up or down on a show teach Watch your taste.", systemImage: "hand.thumbsup")
                    Label("Saving a show and your reactions help rank future picks and sections like Tonight's pick.", systemImage: "brain.head.profile")
                }
                Section("On each show card") {
                    Label("Bookmark: save or remove; saved titles appear in My List.", systemImage: "bookmark")
                    Label("Watching: tap to cycle Not Started → Watching → Finished.", systemImage: "checkmark.circle")
                    Label("Thumbs: like or pass to tune what we suggest next.", systemImage: "hand.thumbsup")
                }
                Section("Badges & status") {
                    Label("On the main Watch feed, chips spell out status: New, This week, Upcoming, Trending, and similar.", systemImage: "tag")
                    Label("New episode and Tonight's pick call out what to watch now; pull to refresh to update the list.", systemImage: "sparkles")
                    Label("Green TV icon: marks recently aired in the current window (from release data).", systemImage: "sparkles.tv.fill")
                }
            }
            .navigationTitle("How Watch Works")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showBadgeGuide = false }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if allShows.isEmpty {
            AppContentStateCard(
                kind: .empty,
                systemImage: "sparkles.tv.fill",
                title: "We're learning what you like",
                message: "React to a few shows — thumbs up or down — and saves help us tune your picks. Pull to refresh anytime.",
                retryTitle: "Refresh",
                onRetry: { Task { await refresh() } },
                isRetryDisabled: isLoading,
                compact: false
            )
        } else if filterPrefs.hasNonDefaultFilters {
            AppContentStateCard(
                kind: .empty,
                systemImage: "line.3.horizontal.decrease.circle",
                title: "No shows match these filters",
                message: "Try another genre or provider, or reset to see your full list again.",
                retryTitle: "Reset filters",
                onRetry: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        filterPrefs.reset()
                    }
                    Task { await refresh() }
                },
                isRetryDisabled: isLoading,
                compact: false
            )
        } else {
            AppContentStateCard(
                kind: .empty,
                systemImage: "tv",
                title: "Nothing in this view",
                message: "Try another category in Filters or pull to refresh.",
                retryTitle: "Refresh",
                onRetry: { Task { await refresh() } },
                isRetryDisabled: isLoading,
                compact: false
            )
        }
    }

    // MARK: - Ranking & sections

    private var savedInFeed: [WatchShowItem] {
        allShows.filter { $0.saved == true }
    }

    /// Shows the user has marked as "Watching" — ready to resume.
    private var continueWatchingStrip: [WatchShowItem] {
        allShows
            .filter { $0.watchProgressState == .watching }
            .sorted { $0.effectiveRankValue > $1.effectiveRankValue }
            .prefix(6)
            .map { $0 }
    }

    private var watchFromYourListStrip: [WatchShowItem] {
        let base = savedInFeed
        let sorted = base.sorted { lhs, rhs in
            let ln = lhs.isNewEpisode == true ? 1 : 0
            let rn = rhs.isNewEpisode == true ? 1 : 0
            if ln != rn { return ln > rn }
            let lw = lhs.watchProgressState == .watching ? 1 : 0
            let rw = rhs.watchProgressState == .watching ? 1 : 0
            if lw != rw { return lw > rw }
            let lp = lhs.watchProgressState == .notStarted ? 1 : 0
            let rp = rhs.watchProgressState == .notStarted ? 1 : 0
            if lp != rp { return lp > rp }
            return lhs.trendScore > rhs.trendScore
        }
        return Array(sorted.prefix(3))
    }


    private var tonightsPick: WatchShowItem? {
        filteredShows.first
    }

    /// Grid excludes the hero row so the same title isn't duplicated.
    private var gridShows: [WatchShowItem] {
        guard let pick = tonightsPick else { return filteredShows }
        return filteredShows.filter { $0.id != pick.id }
    }

    /// Tighter vertical rhythm when only one or two "More Picks" cards; more air for long lists.
    private var morePicksHeaderToGridSpacing: CGFloat {
        guard !gridShows.isEmpty else { return WatchDesign.spaceSM }
        return gridShows.count <= 2 ? WatchDesign.spaceXS : WatchDesign.spaceSM
    }

    /// Outer padding for the More Picks / empty-state block: compact when the grid is small.
    private var watchMoreGroupVerticalPadding: CGFloat {
        guard !filteredShows.isEmpty, !gridShows.isEmpty else { return WatchDesign.spaceSM }
        return gridShows.count <= 2 ? WatchDesign.spaceXS : WatchDesign.spaceSM
    }

    /// New episodes from shows the user has interacted with (saved, seen, or thumbs up).
    private var newEpisodesForYou: [WatchShowItem] {
        allShows
            .filter { show in
                guard show.isNewEpisode == true else { return false }
                let saved = show.saved == true
                let seen = show.watchProgressState == .finished
                let liked = (show.userReaction ?? "") == "up"
                return saved || seen || liked
            }
            .sorted { $0.effectiveRankValue > $1.effectiveRankValue }
    }

    private var filteredShows: [WatchShowItem] {
        var base: [WatchShowItem]
        switch filterPrefs.listScope {
        case .all:
            base = allShows
        case .seen:
            base = allShows.filter { $0.watchProgressState == .finished }
        case .myLikes:
            base = allShows.filter { ($0.userReaction ?? "") == "up" }
        }

        let genres = filterPrefs.selectedGenres
        let hasMyList = genres.contains("My List")
        let hasNewEpisodes = genres.contains("New Episodes")
        let contentGenres = genres.subtracting(["My List", "New Episodes"])

        var step = base
        if hasMyList {
            let savedOnly = step.filter { $0.saved ?? false }
            step = applyMyListSort(to: savedOnly)
        }
        if hasNewEpisodes {
            step = step.filter { $0.isNewEpisode == true }
        }
        if !contentGenres.isEmpty {
            step = step.filter { show in
                contentGenres.contains { g in
                    show.genres.contains { ng in normalizedGenre(ng) == normalizedGenre(g) }
                }
            }
        }

        let pSet = filterPrefs.selectedProviders
        let filtered: [WatchShowItem]
        if pSet.isEmpty {
            filtered = step
        } else {
            filtered = step.filter { show in
                if filterPrefs.matchPrimaryProviderOnly {
                    let primary = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return pSet.contains { normalizedProvider($0) == normalizedProvider(primary) }
                }
                return show.providers.contains { p in
                    pSet.contains { sel in normalizedProvider(sel) == normalizedProvider(p) }
                }
            }
        }
        return localUserPreferences.applyWatchRanking(filtered)
    }

    private func applyMyListSort(to list: [WatchShowItem]) -> [WatchShowItem] {
        if filterPrefs.myListSort == "Recently Saved" {
            return list.sorted { lhs, rhs in
                let lStamp = lhs.savedAtUTC ?? ""
                let rStamp = rhs.savedAtUTC ?? ""
                if lStamp == rStamp {
                    return lhs.effectiveRankValue > rhs.effectiveRankValue
                }
                return lStamp > rStamp
            }
        }
        if filterPrefs.myListSort == "Trending" {
            return list.sorted { $0.effectiveRankValue > $1.effectiveRankValue }
        }
        return list.sorted { lhs, rhs in
            let lNew = lhs.isNewEpisode == true ? 1 : 0
            let rNew = rhs.isNewEpisode == true ? 1 : 0
            if lNew == rNew {
                return lhs.effectiveRankValue > rhs.effectiveRankValue
            }
            return lNew > rNew
        }
    }

    private func migrateLegacyGenreIfNeeded() {
        guard !didMigrateSeenGenre else { return }
        didMigrateSeenGenre = true
    }

    /// Provider names for chip UI (excludes "All").
    private var providerChipOptions: [String] {
        providerFilters.filter { $0 != "All Providers" }
    }

    /// Content genres only (special rows are separate chips in the sheet).
    private var genreChipOptions: [String] {
        genreFilters.filter { !["All", "New Episodes", "My List"].contains($0) }
    }

    private var genreFilters: [String] {
        let preferredOrder = ["All", "Drama", "Comedy", "Action", "Crime", "Sci-Fi", "Reality", "Documentary", "Animation"]
        var unique: [String] = []
        var seen: Set<String> = []
        for show in allShows {
            for genre in show.genres {
                let cleaned = genre.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty { continue }
                let key = normalizedGenre(cleaned)
                if seen.insert(key).inserted {
                    unique.append(cleaned)
                }
            }
        }
        let sorted = unique.sorted { lhs, rhs in
            let lIdx = preferredOrder.firstIndex(of: lhs) ?? 999
            let rIdx = preferredOrder.firstIndex(of: rhs) ?? 999
            if lIdx == rIdx {
                return lhs < rhs
            }
            return lIdx < rIdx
        }
        return ["All", "New Episodes", "My List"] + sorted
    }

    private var providerFilters: [String] {
        let preferredOrder = ["All Providers", "Netflix", "Apple TV+", "HBO Max", "Paramount+", "Peacock", "Prime Video", "Hulu", "Disney+"]
        var unique: [String] = []
        var seen: Set<String> = []
        for show in allShows {
            for provider in show.providers {
                let cleaned = provider.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty { continue }
                let key = normalizedProvider(cleaned)
                if seen.insert(key).inserted {
                    unique.append(cleaned)
                }
            }
        }
        let sorted = unique.sorted { lhs, rhs in
            let lIdx = preferredOrder.firstIndex(of: lhs) ?? 999
            let rIdx = preferredOrder.firstIndex(of: rhs) ?? 999
            if lIdx == rIdx {
                return lhs < rhs
            }
            return lIdx < rIdx
        }
        return ["All Providers"] + sorted
    }

    private var myListSortOptions: [String] {
        ["New Episodes", "Recently Saved", "Trending"]
    }

    private func normalizedProvider(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedGenre(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// iPhone: one column. iPad compact width: adaptive tiles. iPad regular width: stable 2-column grid.
    private var watchCardColumns: [GridItem] {
        guard DeviceLayout.isPad else {
            return [GridItem(.flexible(), spacing: WatchDesign.spaceSM, alignment: .top)]
        }
        if DeviceLayout.useRegularWidthTabletLayout(horizontalSizeClass: horizontalSizeClass) {
            return [
                GridItem(.flexible(minimum: 280), spacing: WatchDesign.spaceMD, alignment: .top),
                GridItem(.flexible(minimum: 280), spacing: WatchDesign.spaceMD, alignment: .top)
            ]
        }
        return [GridItem(.adaptive(minimum: 320), spacing: WatchDesign.spaceSM, alignment: .top)]
    }

    // MARK: - Networking

    private func watchFetchHideSeen() -> Bool {
        filterPrefs.listScope == .all ? !filterPrefs.showWatched : false
    }

    /// Instantly restores the last successful API list when query mode matches (so Watch isn't blank while the server churns).
    private func hydrateWatchFromDiskCacheIfNeeded() {
        guard allShows.isEmpty else { return }
        if let items = WatchListLocalCache.load(
            deviceID: deviceID,
            onlySaved: filterPrefs.onlySavedAPI,
            hideSeen: watchFetchHideSeen()
        ) {
            allShows = items
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await APIClient.shared.fetchWatchShows(
                limit: 40,
                minimumCount: 28,
                deviceID: deviceID,
                hideSeen: filterPrefs.listScope == .all ? !filterPrefs.showWatched : false,
                onlySaved: filterPrefs.onlySavedAPI,
                rankDebugRequested: watchRankDebugRequest
            )
            await MainActor.run {
                self.allShows = result.items
                self.lastWatchRankDebugRoot = result.rankDebug
                let validProviders = Set(self.providerChipOptions)
                self.filterPrefs.selectedProviders = self.filterPrefs.selectedProviders.intersection(validProviders)
                let validGenres = Set(self.genreChipOptions + ["New Episodes", "My List"])
                self.filterPrefs.selectedGenres = self.filterPrefs.selectedGenres.intersection(validGenres)
                self.previousMyListAPIFetch = self.filterPrefs.onlySavedAPI
                self.errorMessage = ""
            }
        } catch {
            await MainActor.run {
                if self.allShows.isEmpty {
                    self.errorMessage = "Could not load trending shows right now."
                }
            }
        }
    }

    private func setSaved(showID: String, saved: Bool) async {
        do {
            try await APIClient.shared.setWatchSaved(deviceID: deviceID, showID: showID, saved: saved)
            await MainActor.run {
                AppHaptics.selection()
            }
            await APIClient.shared.trackEvent(
                deviceID: deviceID,
                eventName: "watch_saved",
                eventProps: [
                    "show_id": showID,
                    "saved": saved ? "true" : "false"
                ]
            )
            await MainActor.run {
                if let item = self.allShows.first(where: { $0.id == showID }) {
                    self.rememberLastShow(item)
                }
                if filterPrefs.onlySavedAPI && !saved {
                    self.allShows.removeAll { $0.id == showID }
                } else if let idx = self.allShows.firstIndex(where: { $0.id == showID }) {
                    var current = self.allShows[idx]
                    current = withSaved(current, saved: saved)
                    self.allShows[idx] = current
                }
                if saved {
                    WatchMyListSaveFeedback.shared.presentAddedToList()
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not update your watchlist."
            }
        }
    }

    private func cycleWatchProgress(showID: String) async {
        guard let prior = allShows.first(where: { $0.id == showID }) else { return }
        let nextState = prior.watchProgressState.next
        do {
            try await APIClient.shared.setWatchProgress(deviceID: deviceID, showID: showID, state: nextState)
            await APIClient.shared.trackEvent(
                deviceID: deviceID,
                eventName: "watch_progress",
                eventProps: [
                    "show_id": showID,
                    "watch_state": nextState.rawValue
                ]
            )
            await MainActor.run {
                self.rememberLastShow(prior)
                let hideFinished = nextState == .finished && !self.filterPrefs.showWatched && self.filterPrefs.listScope == .all
                if hideFinished {
                    self.allShows.removeAll { $0.id == showID }
                } else if let idx = self.allShows.firstIndex(where: { $0.id == showID }) {
                    var current = self.allShows[idx]
                    current = self.withWatchProgress(current, state: nextState)
                    self.allShows[idx] = current
                }
                if nextState == .finished, (prior.userReaction ?? "").isEmpty {
                    self.pendingRatingShow = prior
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not update watch progress."
            }
        }
    }


    private func setReaction(showID: String, reaction: String) async {
        do {
            try await APIClient.shared.setWatchReaction(deviceID: deviceID, showID: showID, reaction: reaction)
            await MainActor.run {
                AppHaptics.lightImpact()
                if let idx = self.allShows.firstIndex(where: { $0.id == showID }) {
                    var current = self.allShows[idx]
                    current = withUserReaction(current, reaction: reaction)
                    self.allShows[idx] = current
                    self.rememberLastShow(current)
                }
            }
            await APIClient.shared.trackEvent(
                deviceID: deviceID,
                eventName: "watch_reaction",
                eventProps: [
                    "show_id": showID,
                    "reaction": reaction
                ]
            )
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not save reaction."
            }
        }
    }

    private func markCaughtUp(showID: String, releaseDate: String) async {
        do {
            try await APIClient.shared.setWatchCaughtUp(deviceID: deviceID, showID: showID, releaseDate: releaseDate)
            await MainActor.run {
                AppHaptics.selection()
                if let idx = self.allShows.firstIndex(where: { $0.id == showID }) {
                    var current = self.allShows[idx]
                    current = withCaughtUp(current, releaseDate: releaseDate)
                    self.allShows[idx] = current
                    self.rememberLastShow(current)
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not mark show as caught up."
            }
        }
    }

    private func withWatchProgress(_ item: WatchShowItem, state: WatchProgressState) -> WatchShowItem {
        WatchShowItem(
            id: item.id,
            title: item.title,
            posterURL: item.posterURL,
            posterStatus: item.posterStatus,
            posterTrusted: item.posterTrusted,
            posterMissing: item.posterMissing,
            posterConfidence: item.posterConfidence,
            posterResolution: item.posterResolution,
            posterResolutionSource: item.posterResolutionSource,
            posterMatchDebug: item.posterMatchDebug,
            synopsis: item.synopsis,
            providers: item.providers,
            primaryProvider: item.primaryProvider,
            genres: item.genres,
            primaryGenre: item.primaryGenre,
            releaseDate: item.releaseDate,
            lastEpisodeAirDate: item.lastEpisodeAirDate,
            nextEpisodeAirDate: item.nextEpisodeAirDate,
            releaseBadge: item.releaseBadge,
            releaseBadgeLabel: item.releaseBadgeLabel,
            seasonEpisodeStatus: item.seasonEpisodeStatus,
            trendScore: item.trendScore,
            rankScore: item.rankScore,
            seen: state == .finished,
            watchState: state.rawValue,
            saved: item.saved,
            savedAtUTC: item.savedAtUTC,
            isNewEpisode: item.isNewEpisode,
            isUpcomingRelease: item.isUpcomingRelease,
            caughtUpReleaseDate: item.caughtUpReleaseDate,
            userReaction: item.userReaction,
            rankOrder: item.rankOrder,
            recommendationReason: item.recommendationReason,
            rankDebug: item.rankDebug,
            upvotes: item.upvotes,
            downvotes: item.downvotes,
            homeFeedSection: item.homeFeedSection
        )
    }

    private func withSaved(_ item: WatchShowItem, saved: Bool) -> WatchShowItem {
        WatchShowItem(
            id: item.id,
            title: item.title,
            posterURL: item.posterURL,
            posterStatus: item.posterStatus,
            posterTrusted: item.posterTrusted,
            posterMissing: item.posterMissing,
            posterConfidence: item.posterConfidence,
            posterResolution: item.posterResolution,
            posterResolutionSource: item.posterResolutionSource,
            posterMatchDebug: item.posterMatchDebug,
            synopsis: item.synopsis,
            providers: item.providers,
            primaryProvider: item.primaryProvider,
            genres: item.genres,
            primaryGenre: item.primaryGenre,
            releaseDate: item.releaseDate,
            lastEpisodeAirDate: item.lastEpisodeAirDate,
            nextEpisodeAirDate: item.nextEpisodeAirDate,
            releaseBadge: item.releaseBadge,
            releaseBadgeLabel: item.releaseBadgeLabel,
            seasonEpisodeStatus: item.seasonEpisodeStatus,
            trendScore: item.trendScore,
            rankScore: item.rankScore,
            seen: item.seen,
            watchState: item.watchState,
            saved: saved,
            savedAtUTC: item.savedAtUTC,
            isNewEpisode: item.isNewEpisode,
            isUpcomingRelease: item.isUpcomingRelease,
            caughtUpReleaseDate: item.caughtUpReleaseDate,
            userReaction: item.userReaction,
            rankOrder: item.rankOrder,
            recommendationReason: item.recommendationReason,
            rankDebug: item.rankDebug,
            upvotes: item.upvotes,
            downvotes: item.downvotes,
            homeFeedSection: item.homeFeedSection
        )
    }

    private func withUserReaction(_ item: WatchShowItem, reaction: String) -> WatchShowItem {
        let r = reaction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let newReaction: String?
        switch r {
        case "up": newReaction = "up"
        case "down": newReaction = "down"
        case "none": newReaction = nil
        default: newReaction = item.userReaction
        }
        return WatchShowItem(
            id: item.id,
            title: item.title,
            posterURL: item.posterURL,
            posterStatus: item.posterStatus,
            posterTrusted: item.posterTrusted,
            posterMissing: item.posterMissing,
            posterConfidence: item.posterConfidence,
            posterResolution: item.posterResolution,
            posterResolutionSource: item.posterResolutionSource,
            posterMatchDebug: item.posterMatchDebug,
            synopsis: item.synopsis,
            providers: item.providers,
            primaryProvider: item.primaryProvider,
            genres: item.genres,
            primaryGenre: item.primaryGenre,
            releaseDate: item.releaseDate,
            lastEpisodeAirDate: item.lastEpisodeAirDate,
            nextEpisodeAirDate: item.nextEpisodeAirDate,
            releaseBadge: item.releaseBadge,
            releaseBadgeLabel: item.releaseBadgeLabel,
            seasonEpisodeStatus: item.seasonEpisodeStatus,
            trendScore: item.trendScore,
            rankScore: item.rankScore,
            seen: item.seen,
            watchState: item.watchState,
            saved: item.saved,
            savedAtUTC: item.savedAtUTC,
            isNewEpisode: item.isNewEpisode,
            isUpcomingRelease: item.isUpcomingRelease,
            caughtUpReleaseDate: item.caughtUpReleaseDate,
            userReaction: newReaction,
            rankOrder: item.rankOrder,
            recommendationReason: item.recommendationReason,
            rankDebug: item.rankDebug,
            upvotes: item.upvotes,
            downvotes: item.downvotes,
            homeFeedSection: item.homeFeedSection
        )
    }

    private func withCaughtUp(_ item: WatchShowItem, releaseDate: String) -> WatchShowItem {
        WatchShowItem(
            id: item.id,
            title: item.title,
            posterURL: item.posterURL,
            posterStatus: item.posterStatus,
            posterTrusted: item.posterTrusted,
            posterMissing: item.posterMissing,
            posterConfidence: item.posterConfidence,
            posterResolution: item.posterResolution,
            posterResolutionSource: item.posterResolutionSource,
            posterMatchDebug: item.posterMatchDebug,
            synopsis: item.synopsis,
            providers: item.providers,
            primaryProvider: item.primaryProvider,
            genres: item.genres,
            primaryGenre: item.primaryGenre,
            releaseDate: item.releaseDate,
            lastEpisodeAirDate: item.lastEpisodeAirDate,
            nextEpisodeAirDate: item.nextEpisodeAirDate,
            releaseBadge: item.releaseBadge,
            releaseBadgeLabel: item.releaseBadgeLabel,
            seasonEpisodeStatus: item.seasonEpisodeStatus,
            trendScore: item.trendScore,
            rankScore: item.rankScore,
            seen: item.seen,
            watchState: item.watchState,
            saved: item.saved,
            savedAtUTC: item.savedAtUTC,
            isNewEpisode: false,
            isUpcomingRelease: item.isUpcomingRelease,
            caughtUpReleaseDate: releaseDate,
            userReaction: item.userReaction,
            rankOrder: item.rankOrder,
            recommendationReason: item.recommendationReason,
            rankDebug: item.rankDebug,
            upvotes: item.upvotes,
            downvotes: item.downvotes,
            homeFeedSection: item.homeFeedSection
        )
    }

    private func rememberLastShow(_ show: WatchShowItem) {
        UserDefaults.standard.set("show", forKey: "bdn-last-content-kind-ios")
        UserDefaults.standard.set(show.title, forKey: "bdn-last-content-title-ios")
        UserDefaults.standard.set(show.id, forKey: "bdn-last-content-url-ios")
        UserDefaults.standard.set(show.primaryProvider ?? "", forKey: "bdn-last-content-source-ios")
        UserDefaults.standard.set(Date(), forKey: "bdn-last-content-opened-ios")
    }
}

// MARK: - Toolbar

private struct WatchToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // Actions live in `WatchCompactScreenHeader` (reliable on device). Tab + NavigationStack
            // does not consistently show trailing `ToolbarItem`s on physical iPhones; keep bar minimal.
    }
}
