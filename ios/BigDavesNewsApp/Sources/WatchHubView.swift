import SwiftUI

// MARK: - Continue Watching (mock until server playhead exists)

private struct WatchHubContinueMock: Identifiable {
    let id: String
    let title: String
    let provider: String
    /// 0...1
    let progress: Double
}

// MARK: - My List (habit-focused)

/// Saved shows with a clear next action, urgency rail, full list, and discovery strip.
struct WatchHubView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var showsDismissButton: Bool = false

    @State private var savedShows: [WatchShowItem] = []
    @State private var recommendedShows: [WatchShowItem] = []
    @State private var sortMode: WatchMyListSortMode = .recentlySaved
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let deviceID = WatchDeviceIdentity.current

    private var padH: CGFloat { DeviceLayout.horizontalPadding }
    private var contentMaxWidth: CGFloat { DeviceLayout.contentMaxWidth }

    private static let continueMocks: [WatchHubContinueMock] = [
        WatchHubContinueMock(id: "mock-1", title: "Sample Series", provider: "Streaming", progress: 0.35),
        WatchHubContinueMock(id: "mock-2", title: "Another Show", provider: "Streaming", progress: 0.62),
    ]

    private var myListDisplayed: [WatchShowItem] {
        WatchMyListDisplay.sortedSavedShows(savedShows, mode: sortMode)
    }

    private var upcomingFromList: [WatchShowItem] {
        savedShows.filter { show in
            if show.isUpcomingRelease == true { return true }
            let b = (show.releaseBadge ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return b == "this_week" || b == "upcoming"
        }
    }

    private var recommendedStrip: [WatchShowItem] {
        let savedIds = Set(savedShows.map(\.id))
        return recommendedShows.filter { !savedIds.contains($0.id) }.prefix(12).map { $0 }
    }

    private var startWatchingPick: WatchShowItem? {
        WatchMyListHabit.pickStartWatching(from: savedShows)
    }

    private var fromYourListItems: [WatchShowItem] {
        let skip = Set([startWatchingPick?.id].compactMap { $0 })
        return Array(WatchMyListHabit.urgencySaved(from: savedShows, excludingIds: skip).prefix(12))
    }

    private var mainListRows: [WatchShowItem] {
        guard let pick = startWatchingPick, savedShows.count > 1 else { return myListDisplayed }
        return myListDisplayed.filter { $0.id != pick.id }
    }


    var body: some View {
        Group {
            if isLoading && savedShows.isEmpty && recommendedShows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                        ForEach(0..<6, id: \.self) { _ in WatchCardSkeleton() }
                    }
                    .padding(.horizontal, padH)
                    .padding(.top, 8)
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .redacted(reason: .placeholder)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing + 4) {
                        if let errorMessage, savedShows.isEmpty, recommendedShows.isEmpty {
                            AppContentStateCard(
                                kind: .error,
                                systemImage: "wifi.exclamationmark",
                                title: "Couldn’t load Watch Hub",
                                message: errorMessage,
                                retryTitle: "Try again",
                                onRetry: { Task { await loadAll() } },
                                isRetryDisabled: isLoading,
                                compact: false
                            )
                        }

                        startWatchingSection
                        fromYourListSection
                        myListSection
                        recommendedSection
                        upcomingSection
                    }
                    .padding(.horizontal, padH)
                    .padding(.vertical, 10)
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .refreshable { await loadAll() }
            }
        }
        .background(AppTheme.watchScreenBackground(for: colorScheme))
        .navigationTitle("My List")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if showsDismissButton {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityHint("Closes My List.")
                }
                Menu {
                    Picker("Sort My List", selection: $sortMode) {
                        ForEach(WatchMyListSortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    Label("Sort My List", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort My List")
                .disabled(savedShows.isEmpty)
            }
        }
        .task {
            await loadAll()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var startWatchingSection: some View {
        if let pick = startWatchingPick {
            VStack(alignment: .leading, spacing: 10) {
                WatchSectionHeader(title: "Start Watching", subtitle: "Your next play is ready")
                WatchStartWatchingCard(
                    show: pick,
                    reason: WatchMyListHabit.startWatchingReason(for: pick),
                    onOpenProvider: {
                        Task { _ = await StreamingProviderLauncher.open(for: pick) }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var fromYourListSection: some View {
        if !fromYourListItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                WatchSectionHeader(
                    title: "From Your List",
                    subtitle: "Needs attention soon"
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WatchDesign.spaceSM) {
                        ForEach(Array(fromYourListItems.enumerated()), id: \.element.id) { index, show in
                            WatchHubRecommendationCard(
                                show: show,
                                listIndex: index,
                                batch: fromYourListItems
                            )
                        }
                    }
                }
            }
        }
    }

    private var myListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WatchSectionHeader(
                title: "All saved",
                subtitle: "Everything on your list"
            )

            if savedShows.isEmpty {
                hubMyListEmptyCard
            } else if myListDisplayed.isEmpty {
                AppContentStateCard(
                    kind: .empty,
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: "Nothing matches this sort",
                    message: WatchMyListDisplay.sortEmptyHint(for: sortMode),
                    retryTitle: nil,
                    onRetry: nil,
                    compact: false
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(mainListRows.enumerated()), id: \.element.id) { index, show in
                        WatchMyListShowRow(
                            show: show,
                            badgeBatch: mainListRows,
                            listIndex: index,
                            onRemoveFromSaved: {
                                Task { await removeSaved(show) }
                            }
                        )
                    }
                }
            }
        }
    }

    private var hubMyListEmptyCard: some View {
        BrandCard {
            VStack(alignment: .center, spacing: 16) {
                Image(systemName: "bookmark")
                    .font(.system(size: 36, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.primary.opacity(colorScheme == .dark ? 0.95 : 0.88))
                    .accessibilityHidden(true)

                Text("Nothing here yet")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Save shows to build your watch list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    AppHaptics.selection()
                    dismiss()
                    AppNavigationState.shared.openWatch()
                } label: {
                    Text("Browse Shows")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .accessibilityHint("Switches to the Watch tab.")
            }
            .padding(.vertical, 6)
        }
    }

    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: WatchDesign.spaceSM) {
            WatchSectionHeader(
                title: "Recommended for You",
                subtitle: "Based on what’s trending for you"
            )

            if recommendedStrip.isEmpty {
                Text("Recommendations will appear after Watch loads.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WatchDesign.spaceSM) {
                        ForEach(Array(recommendedStrip.enumerated()), id: \.element.id) { index, show in
                            WatchHubRecommendationCard(
                                show: show,
                                listIndex: index,
                                batch: recommendedStrip
                            )
                        }
                    }
                }
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WatchSectionHeader(
                title: "Upcoming From Your List",
                subtitle: "New or soon on saved shows"
            )

            if upcomingFromList.isEmpty {
                Text("Nothing scheduled from your saved titles right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(upcomingFromList.enumerated()), id: \.element.id) { index, show in
                        WatchMyListShowRow(
                            show: show,
                            badgeBatch: upcomingFromList,
                            listIndex: index,
                            onRemoveFromSaved: {
                                Task { await removeSaved(show) }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: Data

    private func loadAll() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        async let savedTask = APIClient.shared.fetchWatchShows(
            limit: 50,
            minimumCount: 10,
            deviceID: deviceID,
            hideSeen: false,
            onlySaved: true
        )
        async let recTask = APIClient.shared.fetchWatchShows(
            limit: 24,
            minimumCount: 16,
            deviceID: deviceID,
            hideSeen: true,
            onlySaved: false
        )
        do {
            let s = try await savedTask
            let r = try await recTask
            await MainActor.run {
                savedShows = s.items
                recommendedShows = r.items
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                if savedShows.isEmpty { savedShows = [] }
                if recommendedShows.isEmpty { recommendedShows = [] }
            }
        }
    }

    private func removeSaved(_ show: WatchShowItem) async {
        do {
            try await APIClient.shared.setWatchSaved(deviceID: deviceID, showID: show.id, saved: false)
            AppHaptics.selection()
            savedShows.removeAll { $0.id == show.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Recommended strip card

struct WatchHubRecommendationCard: View {
    let show: WatchShowItem
    var listIndex: Int
    var batch: [WatchShowItem]

    var body: some View {
        WatchMiniCard(show: show, listIndex: listIndex, batch: batch)
    }
}
