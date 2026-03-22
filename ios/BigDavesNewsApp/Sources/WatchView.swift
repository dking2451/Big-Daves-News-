import SwiftUI

struct WatchView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var allShows: [WatchShowItem] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showWatched = false
    @State private var selectedGenre = "All"
    @State private var selectedProvider = "All Providers"
    @State private var myListSort = "New Episodes"
    @State private var pendingRatingShow: WatchShowItem?
    @State private var showBadgeGuide = false
    @AppStorage("bdn-watch-guide-seen-ios") private var hasSeenWatchGuide = false
    private let deviceID = WatchDeviceIdentity.current
    private var padH: CGFloat { DeviceLayout.horizontalPadding }
    private var contentMaxWidth: CGFloat { DeviceLayout.contentMaxWidth }
    private var chipFont: Font {
        if DeviceLayout.isLargePad { return .body.weight(.semibold) }
        if DeviceLayout.isPad { return .subheadline.weight(.semibold) }
        return .caption2.weight(.semibold)
    }
    private var filterHeaderFont: Font {
        DeviceLayout.isPad ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }
    private var phoneChipHorizontalPadding: CGFloat {
        DeviceLayout.isPad ? 12 : 9
    }
    private var phoneChipVerticalPadding: CGFloat {
        DeviceLayout.isPad ? 9 : 7
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && allShows.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DeviceLayout.screenIntentToBrandedSpacing) {
                            ScreenIntentHeader(title: "Watch", subtitle: "What to watch tonight")
                                .padding(.horizontal, padH)
                            AppBrandedHeader(
                                sectionTitle: "Watch",
                                sectionSubtitle: "",
                                showSectionHeading: false
                            )
                            .padding(.horizontal, padH)
                        }
                        .padding(.top, 8)
                        LazyVStack(spacing: 14) {
                            ForEach(0..<6, id: \.self) { _ in
                                WatchCardSkeleton()
                            }
                        }
                        .padding(.horizontal, padH)
                        .padding(.vertical, 10)
                        .frame(maxWidth: contentMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .redacted(reason: .placeholder)
                } else if !errorMessage.isEmpty && allShows.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DeviceLayout.screenIntentToBrandedSpacing) {
                            ScreenIntentHeader(title: "Watch", subtitle: "What to watch tonight")
                                .padding(.horizontal, padH)
                            AppBrandedHeader(
                                sectionTitle: "Watch",
                                sectionSubtitle: "",
                                showSectionHeading: false
                            )
                            .padding(.horizontal, padH)
                        }
                        .padding(.top, 8)
                        AppContentStateCard(
                            kind: .error,
                            systemImage: "wifi.exclamationmark",
                            title: "Couldn’t load Watch",
                            message: errorMessage,
                            retryTitle: "Try again",
                            onRetry: { Task { await refresh() } },
                            isRetryDisabled: isLoading,
                            compact: false
                        )
                        .padding(.horizontal, padH)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DeviceLayout.screenIntentToBrandedSpacing) {
                            ScreenIntentHeader(title: "Watch", subtitle: "What to watch tonight")
                                .padding(.horizontal, padH)
                            AppBrandedHeader(
                                sectionTitle: "Watch",
                                sectionSubtitle: "",
                                showSectionHeading: false
                            )
                            .padding(.horizontal, padH)
                        }
                        .padding(.top, 8)

                        HStack(spacing: 8) {
                            Text("Show watched")
                                .font(.subheadline)
                            Toggle("", isOn: $showWatched)
                                .labelsHidden()
                                .fixedSize()
                        }
                        .padding(.horizontal, padH)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: showWatched) { _ in
                            Task { await refresh() }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Filter by genre")
                                    .font(filterHeaderFont)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if shouldShowHorizontalHint(itemCount: genreFilters.count) {
                                    Label("Swipe for more", systemImage: "arrow.left.and.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, padH)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(genreFilters, id: \.self) { genre in
                                        Button {
                                            selectedGenre = genre
                                            Task { await refresh() }
                                        } label: {
                                            Label(genre, systemImage: genreIcon(for: genre))
                                                .font(chipFont)
                                                .padding(.horizontal, phoneChipHorizontalPadding)
                                                .padding(.vertical, phoneChipVerticalPadding)
                                                .frame(minHeight: 44)
                                                .background(
                                                    selectedGenre == genre
                                                        ? selectedGenreChipColor
                                                        : Color(.secondarySystemFill)
                                                )
                                                .foregroundStyle(
                                                    selectedGenre == genre ? Color.white : Color.primary
                                                )
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, padH)
                            }
                            .overlay(alignment: .trailing) {
                                if shouldShowHorizontalHint(itemCount: genreFilters.count) {
                                    scrollEdgeFade
                                }
                            }
                        }
                        .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Filter by provider")
                                    .font(filterHeaderFont)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if shouldShowHorizontalHint(itemCount: providerFilters.count) {
                                    Label("Swipe for more", systemImage: "arrow.left.and.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, padH)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(providerFilters, id: \.self) { provider in
                                        Button {
                                            selectedProvider = provider
                                        } label: {
                                            Label(provider, systemImage: providerIcon(for: provider))
                                                .font(chipFont)
                                                .padding(.horizontal, phoneChipHorizontalPadding)
                                                .padding(.vertical, phoneChipVerticalPadding)
                                                .frame(minHeight: 44)
                                                .background(
                                                    selectedProvider == provider
                                                        ? selectedProviderChipColor
                                                        : Color(.secondarySystemFill)
                                                )
                                                .foregroundStyle(
                                                    selectedProvider == provider ? Color.white : Color.primary
                                                )
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, padH)
                            }
                            .overlay(alignment: .trailing) {
                                if shouldShowHorizontalHint(itemCount: providerFilters.count) {
                                    scrollEdgeFade
                                }
                            }
                        }
                        .padding(.top, 4)

                        if selectedGenre == "My List" {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Sort My List")
                                    .font(filterHeaderFont)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, padH)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(myListSortOptions, id: \.self) { option in
                                            Button {
                                                myListSort = option
                                            } label: {
                                                Label(option, systemImage: myListSortIcon(for: option))
                                                    .font(chipFont)
                                                    .padding(.horizontal, phoneChipHorizontalPadding)
                                                    .padding(.vertical, phoneChipVerticalPadding)
                                                    .frame(minHeight: 44)
                                                    .background(
                                                        myListSort == option
                                                            ? selectedSortChipColor
                                                            : Color(.secondarySystemFill)
                                                    )
                                                    .foregroundStyle(
                                                        myListSort == option ? Color.white : Color.primary
                                                    )
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, padH)
                                }
                            }
                            .padding(.top, 4)
                        }

                        if hasActiveFilters {
                            HStack(spacing: 8) {
                                Label("\(filteredShows.count) results", systemImage: "line.3.horizontal.decrease.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Reset Filters") {
                                    resetFilters()
                                    Task { await refresh() }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                            }
                            .padding(.horizontal, padH)
                            .padding(.top, 2)
                        }

                        Group {
                            if filteredShows.isEmpty {
                                if allShows.isEmpty {
                                    AppContentStateCard(
                                        kind: .empty,
                                        systemImage: "sparkles.tv.fill",
                                        title: "We’re learning what you like",
                                        message: "React to a few shows — thumbs up or down — and saves help us tune your picks. Pull to refresh anytime.",
                                        retryTitle: "Refresh",
                                        onRetry: { Task { await refresh() } },
                                        isRetryDisabled: isLoading,
                                        compact: false
                                    )
                                } else if hasActiveFilters {
                                    AppContentStateCard(
                                        kind: .empty,
                                        systemImage: "line.3.horizontal.decrease.circle",
                                        title: "No shows match these filters",
                                        message: "Try another genre or provider, or reset to see your full list again.",
                                        retryTitle: "Reset filters",
                                        onRetry: {
                                            resetFilters()
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
                                        message: "Try another category above or pull to refresh.",
                                        retryTitle: "Refresh",
                                        onRetry: { Task { await refresh() } },
                                        isRetryDisabled: isLoading,
                                        compact: false
                                    )
                                }
                            } else {
                                LazyVGrid(columns: watchCardColumns, alignment: .leading, spacing: 14) {
                                    ForEach(filteredShows) { show in
                                        WatchShowCard(
                                            show: show,
                                            onToggleSeen: { value in
                                                Task { await setSeen(showID: show.id, seen: value) }
                                            },
                                            onReaction: { reaction in
                                                Task { await setReaction(showID: show.id, reaction: reaction) }
                                            },
                                            onToggleSaved: { value in
                                                Task { await setSaved(showID: show.id, saved: value) }
                                            },
                                            onCaughtUp: {
                                                Task { await markCaughtUp(showID: show.id, releaseDate: show.releaseDate) }
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, padH)
                        .padding(.vertical, 10)
                        .frame(maxWidth: contentMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .refreshable {
                        await refresh()
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AppOverflowMenu()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Refresh watch")
                    Button {
                        hasSeenWatchGuide = true
                        showBadgeGuide = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("How Watch works")
                    AppHelpButton()
                }
            }
            .task {
                if allShows.isEmpty {
                    await refresh()
                }
                if !hasSeenWatchGuide {
                    hasSeenWatchGuide = true
                    showBadgeGuide = true
                }
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
            Button("Thumbs Down") {
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
            NavigationStack {
                List {
                    Section("How recommendations work") {
                        Label("Use thumbs up/down to teach Watch your taste.", systemImage: "hand.thumbsup")
                        Label("Saved shows and reactions help rank your future recommendations.", systemImage: "brain.head.profile")
                    }
                    Section("Show actions") {
                        Label("Bookmark: save a show to My List.", systemImage: "bookmark")
                        Label("Checkmark: mark a show as seen.", systemImage: "checkmark.circle")
                        Label("Thumbs up/down: improve future picks.", systemImage: "hand.thumbsup")
                    }
                    Section("Release badges") {
                        Label("New: recently released episode or season", systemImage: "sparkles")
                        Label("This Week: release is expected this week", systemImage: "calendar")
                        Label("Upcoming: release is still ahead", systemImage: "clock")
                    }
                    Section("Green TV badge") {
                        Label("New episode available now", systemImage: "sparkles.tv.fill")
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
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await APIClient.shared.fetchWatchShows(
                limit: 40,
                minimumCount: 28,
                deviceID: deviceID,
                hideSeen: !showWatched && selectedGenre != "Seen",
                onlySaved: selectedGenre == "My List"
            )
            await MainActor.run {
                self.allShows = list
                let filters = self.genreFilters
                if !filters.contains(self.selectedGenre) {
                    self.selectedGenre = "All"
                }
                let providerList = self.providerFilters
                if !providerList.contains(self.selectedProvider) {
                    self.selectedProvider = "All Providers"
                }
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
                if selectedGenre == "My List" && !saved {
                    self.allShows.removeAll { $0.id == showID }
                } else if let idx = self.allShows.firstIndex(where: { $0.id == showID }) {
                    var current = self.allShows[idx]
                    current = withSaved(current, saved: saved)
                    self.allShows[idx] = current
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not update your watchlist."
            }
        }
    }

    private func setSeen(showID: String, seen: Bool) async {
        do {
            try await APIClient.shared.setWatchSeen(deviceID: deviceID, showID: showID, seen: seen)
            await APIClient.shared.trackEvent(
                deviceID: deviceID,
                eventName: "watch_seen",
                eventProps: [
                    "show_id": showID,
                    "seen": seen ? "true" : "false"
                ]
            )
            await MainActor.run {
                let currentItem = self.allShows.first(where: { $0.id == showID })
                if let currentItem {
                    self.rememberLastShow(currentItem)
                }
                if seen && !showWatched {
                    self.allShows.removeAll { $0.id == showID }
                } else if let idx = self.allShows.firstIndex(where: { $0.id == showID }) {
                    var current = self.allShows[idx]
                    current = withSeen(current, seen: seen)
                    self.allShows[idx] = current
                }
                if seen, let item = currentItem, (item.userReaction ?? "").isEmpty {
                    self.pendingRatingShow = item
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not update watched state."
            }
        }
    }

    private func setReaction(showID: String, reaction: String) async {
        do {
            try await APIClient.shared.setWatchReaction(deviceID: deviceID, showID: showID, reaction: reaction)
            await MainActor.run {
                AppHaptics.lightImpact()
            }
            await APIClient.shared.trackEvent(
                deviceID: deviceID,
                eventName: "watch_reaction",
                eventProps: [
                    "show_id": showID,
                    "reaction": reaction
                ]
            )
            if let item = allShows.first(where: { $0.id == showID }) {
                await MainActor.run {
                    self.rememberLastShow(item)
                }
            }
            await refresh()
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not save reaction."
            }
        }
    }

    private func markCaughtUp(showID: String, releaseDate: String) async {
        do {
            try await APIClient.shared.setWatchCaughtUp(deviceID: deviceID, showID: showID, releaseDate: releaseDate)
            await refresh()
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not mark show as caught up."
            }
        }
    }

    private func withSeen(_ item: WatchShowItem, seen: Bool) -> WatchShowItem {
        WatchShowItem(
            id: item.id,
            title: item.title,
            posterURL: item.posterURL,
            synopsis: item.synopsis,
            providers: item.providers,
            primaryProvider: item.primaryProvider,
            genres: item.genres,
            primaryGenre: item.primaryGenre,
            releaseDate: item.releaseDate,
            releaseBadge: item.releaseBadge,
            releaseBadgeLabel: item.releaseBadgeLabel,
            seasonEpisodeStatus: item.seasonEpisodeStatus,
            trendScore: item.trendScore,
            seen: seen,
            saved: item.saved,
            savedAtUTC: item.savedAtUTC,
            isNewEpisode: item.isNewEpisode,
            isUpcomingRelease: item.isUpcomingRelease,
            caughtUpReleaseDate: item.caughtUpReleaseDate,
            userReaction: item.userReaction,
            upvotes: item.upvotes,
            downvotes: item.downvotes
        )
    }

    private func withSaved(_ item: WatchShowItem, saved: Bool) -> WatchShowItem {
        WatchShowItem(
            id: item.id,
            title: item.title,
            posterURL: item.posterURL,
            synopsis: item.synopsis,
            providers: item.providers,
            primaryProvider: item.primaryProvider,
            genres: item.genres,
            primaryGenre: item.primaryGenre,
            releaseDate: item.releaseDate,
            releaseBadge: item.releaseBadge,
            releaseBadgeLabel: item.releaseBadgeLabel,
            seasonEpisodeStatus: item.seasonEpisodeStatus,
            trendScore: item.trendScore,
            seen: item.seen,
            saved: saved,
            savedAtUTC: item.savedAtUTC,
            isNewEpisode: item.isNewEpisode,
            isUpcomingRelease: item.isUpcomingRelease,
            caughtUpReleaseDate: item.caughtUpReleaseDate,
            userReaction: item.userReaction,
            upvotes: item.upvotes,
            downvotes: item.downvotes
        )
    }

    private var hasActiveFilters: Bool {
        selectedGenre != "All" || selectedProvider != "All Providers" || myListSort != "New Episodes"
    }

    private func resetFilters() {
        selectedGenre = "All"
        selectedProvider = "All Providers"
        myListSort = "New Episodes"
    }

    private var filteredShows: [WatchShowItem] {
        let genreScoped: [WatchShowItem]
        if selectedGenre == "All" {
            genreScoped = allShows
        } else if selectedGenre == "Seen" {
            genreScoped = allShows.filter { $0.seen ?? false }
        } else if selectedGenre == "My List" {
            let list = allShows.filter { $0.saved ?? false }
            if myListSort == "Recently Saved" {
                genreScoped = list.sorted { lhs, rhs in
                    let lStamp = lhs.savedAtUTC ?? ""
                    let rStamp = rhs.savedAtUTC ?? ""
                    if lStamp == rStamp {
                        return lhs.trendScore > rhs.trendScore
                    }
                    return lStamp > rStamp
                }
            } else if myListSort == "Trending" {
                genreScoped = list.sorted { $0.trendScore > $1.trendScore }
            } else {
                genreScoped = list.sorted { lhs, rhs in
                    let lNew = lhs.isNewEpisode == true ? 1 : 0
                    let rNew = rhs.isNewEpisode == true ? 1 : 0
                    if lNew == rNew {
                        return lhs.trendScore > rhs.trendScore
                    }
                    return lNew > rNew
                }
            }
        } else if selectedGenre == "New Episodes" {
            genreScoped = allShows.filter { $0.isNewEpisode == true }
        } else {
            genreScoped = allShows.filter { show in
                show.genres.contains(where: { normalizedGenre($0) == normalizedGenre(selectedGenre) })
            }
        }

        if selectedProvider == "All Providers" {
            return genreScoped
        }
        return genreScoped.filter { show in
            show.providers.contains(where: { normalizedProvider($0) == normalizedProvider(selectedProvider) })
        }
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

    private func normalizedProvider(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func providerIcon(for provider: String) -> String {
        let key = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.contains("all providers") { return "line.3.horizontal.decrease.circle" }
        if key.contains("netflix") { return "play.rectangle.fill" }
        if key.contains("hulu") { return "play.rectangle.fill" }
        if key.contains("prime") || key.contains("amazon") { return "cart.fill" }
        if key.contains("apple tv") { return "applelogo" }
        if key.contains("max") || key.contains("hbo") { return "tv.fill" }
        if key.contains("disney") { return "sparkles.tv.fill" }
        if key.contains("paramount") || key.contains("peacock") { return "tv.fill" }
        return "play.rectangle"
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
        return ["All", "Seen", "My List", "New Episodes"] + sorted
    }

    private var myListSortOptions: [String] {
        ["New Episodes", "Recently Saved", "Trending"]
    }

    private func normalizedGenre(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func genreIcon(for genre: String) -> String {
        let key = normalizedGenre(genre)
        if key == "all" { return "line.3.horizontal.decrease.circle" }
        if key == "seen" { return "checkmark.circle.fill" }
        if key == "my list" { return "bookmark.fill" }
        if key == "new episodes" { return "sparkles.tv.fill" }
        if key.contains("action") { return "bolt.fill" }
        if key.contains("comedy") { return "face.smiling" }
        if key.contains("drama") { return "theatermasks.fill" }
        if key.contains("crime") { return "shield.lefthalf.filled" }
        if key.contains("sci") { return "sparkles" }
        if key.contains("reality") { return "tv.fill" }
        if key.contains("documentary") { return "doc.text.fill" }
        if key.contains("animation") { return "paintpalette.fill" }
        return "tag.fill"
    }

    private func myListSortIcon(for option: String) -> String {
        let key = option.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.contains("new") { return "sparkles.tv.fill" }
        if key.contains("recent") { return "clock.badge.checkmark" }
        return "chart.line.uptrend.xyaxis"
    }

    private func shouldShowHorizontalHint(itemCount: Int) -> Bool {
        if DeviceLayout.isLargePad { return itemCount > 8 }
        if DeviceLayout.isPad { return itemCount > 6 }
        return itemCount > 4
    }

    private var watchCardColumns: [GridItem] {
        if DeviceLayout.isPad {
            return [GridItem(.adaptive(minimum: 430), spacing: 14, alignment: .top)]
        }
        return [GridItem(.flexible(), spacing: 14, alignment: .top)]
    }

    private var scrollEdgeFade: some View {
        LinearGradient(
            colors: [Color.clear, AppTheme.pageBackground.opacity(0.85)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: DeviceLayout.isPad ? 42 : 28)
        .allowsHitTesting(false)
    }

    private var selectedGenreChipColor: Color {
        colorScheme == .dark ? .cyan : .blue
    }

    private var selectedProviderChipColor: Color {
        colorScheme == .dark ? .mint : .teal
    }

    private var selectedSortChipColor: Color {
        colorScheme == .dark ? .purple.opacity(0.92) : .indigo
    }

    private func rememberLastShow(_ show: WatchShowItem) {
        UserDefaults.standard.set("show", forKey: "bdn-last-content-kind-ios")
        UserDefaults.standard.set(show.title, forKey: "bdn-last-content-title-ios")
        UserDefaults.standard.set(show.id, forKey: "bdn-last-content-url-ios")
        UserDefaults.standard.set(show.primaryProvider ?? "", forKey: "bdn-last-content-source-ios")
        UserDefaults.standard.set(Date(), forKey: "bdn-last-content-opened-ios")
    }
}

private struct WatchCardSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme
    private var thumbWidth: CGFloat { DeviceLayout.isLargePad ? 112 : (DeviceLayout.isPad ? 96 : 72) }
    private var thumbHeight: CGFloat { DeviceLayout.isLargePad ? 156 : (DeviceLayout.isPad ? 132 : 104) }
    private var cardPadding: CGFloat { DeviceLayout.isLargePad ? 16 : (DeviceLayout.isPad ? 14 : 10) }
    private var cornerRadius: CGFloat { DeviceLayout.isLargePad ? 20 : (DeviceLayout.isPad ? 18 : 14) }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemFill))
                .frame(width: thumbWidth, height: thumbHeight)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: DeviceLayout.isLargePad ? 220 : 160, height: 12)
            }
        }
        .padding(cardPadding)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: bevelStrokeColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: primaryShadowColor, radius: 12, x: 0, y: 5)
        .shadow(color: secondaryShadowColor, radius: 3, x: 0, y: 1)
    }

    private var bevelStrokeColors: [Color] {
        if colorScheme == .dark {
            return [Color.white.opacity(0.08), Color.black.opacity(0.22)]
        }
        return [Color.white.opacity(0.7), Color.black.opacity(0.10)]
    }

    private var primaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.10)
    }

    private var secondaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.14) : Color.black.opacity(0.05)
    }
}

private struct WatchShowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let show: WatchShowItem
    let onToggleSeen: (Bool) -> Void
    let onReaction: (String) -> Void
    let onToggleSaved: (Bool) -> Void
    let onCaughtUp: () -> Void
    private var isPad: Bool { DeviceLayout.isPad }
    private var thumbWidth: CGFloat { DeviceLayout.isLargePad ? 112 : (isPad ? 96 : 72) }
    private var thumbHeight: CGFloat { DeviceLayout.isLargePad ? 156 : (isPad ? 132 : 104) }
    private var cardPadding: CGFloat { DeviceLayout.isLargePad ? 16 : (isPad ? 14 : 10) }
    private var cornerRadius: CGFloat { DeviceLayout.isLargePad ? 20 : (isPad ? 18 : 14) }
    private var metaFont: Font {
        if DeviceLayout.isLargePad { return .subheadline.weight(.semibold) }
        if isPad { return .caption.weight(.semibold) }
        return .caption2.weight(.semibold)
    }
    private var actionLabelFont: Font {
        if DeviceLayout.isLargePad { return .subheadline }
        if isPad { return .caption }
        return .caption
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: URL(string: show.posterURL)) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemFill))
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemFill))
                        Image(systemName: "tv")
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color(.secondarySystemFill)
                }
            }
            .frame(width: thumbWidth, height: thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(show.title)
                        .font(isPad ? .title3.weight(.semibold) : .headline)
                        .lineLimit(2)
                    Spacer()
                    Text(String(format: "%.0f", show.trendScore))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    if let badge = resolvedReleaseBadge() {
                        Text(badge)
                            .font(metaFont)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                            .help(releaseBadgeHelpText(badge))
                    }
                    Text(show.seasonEpisodeStatus)
                        .font(DeviceLayout.isLargePad ? .subheadline : .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if show.isNewEpisode == true {
                        Image(systemName: "sparkles.tv.fill")
                            .font(metaFont)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.18))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                            .accessibilityLabel("New episode available")
                            .help("New episode available")
                    }
                }

                Text(show.synopsis)
                    .font(DeviceLayout.isLargePad ? .title3 : (isPad ? .body : .subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("Where to stream")
                    .font(metaFont)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(show.providers, id: \.self) { provider in
                            Label(provider, systemImage: providerIcon(for: provider))
                                .font(DeviceLayout.isLargePad ? .subheadline.weight(.medium) : (isPad ? .caption.weight(.medium) : .caption2.weight(.medium)))
                                .padding(.horizontal, isPad ? 10 : 8)
                                .padding(.vertical, isPad ? 5 : 4)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            onToggleSaved(!(show.saved ?? false))
                        } label: {
                            Image(systemName: (show.saved ?? false) ? "bookmark.fill" : "bookmark")
                                .font(DeviceLayout.isLargePad ? .body.weight(.semibold) : .subheadline.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel((show.saved ?? false) ? "Saved" : "Save to watchlist")

                        Button {
                            onToggleSeen(!(show.seen ?? false))
                        } label: {
                            Image(systemName: (show.seen ?? false) ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(DeviceLayout.isLargePad ? .body.weight(.semibold) : .subheadline.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel((show.seen ?? false) ? "Seen" : "Mark as seen")

                        Button {
                            onReaction((show.userReaction == "up") ? "none" : "up")
                        } label: {
                            Label("\(show.upvotes ?? 0)", systemImage: show.userReaction == "up" ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(actionLabelFont)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onReaction((show.userReaction == "down") ? "none" : "down")
                        } label: {
                            Label("\(show.downvotes ?? 0)", systemImage: show.userReaction == "down" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(actionLabelFont)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)

                        if show.saved == true, show.isNewEpisode == true {
                            Button {
                                onCaughtUp()
                            } label: {
                                Label("Caught Up", systemImage: "checkmark.seal")
                                    .font(actionLabelFont)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding(cardPadding)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: bevelStrokeColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: primaryShadowColor, radius: 12, x: 0, y: 5)
        .shadow(color: secondaryShadowColor, radius: 3, x: 0, y: 1)
    }

    private func resolvedReleaseBadge() -> String? {
        if let backendLabel = show.releaseBadgeLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !backendLabel.isEmpty {
            return backendLabel
        }
        return fallbackReleaseBadge(releaseDate: show.releaseDate)
    }

    private func fallbackReleaseBadge(releaseDate: String) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: releaseDate) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let diff = Calendar.current.dateComponents([.day], from: start, to: date).day ?? 0
        if diff < -14 { return nil }
        if diff <= 0 { return "New" }
        if diff <= 7 { return "This Week" }
        return "Upcoming"
    }

    private func providerIcon(for provider: String) -> String {
        let key = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.contains("all providers") { return "line.3.horizontal.decrease.circle" }
        if key.contains("netflix") { return "play.rectangle.fill" }
        if key.contains("hulu") { return "play.rectangle.fill" }
        if key.contains("prime") || key.contains("amazon") { return "cart.fill" }
        if key.contains("apple tv") { return "applelogo" }
        if key.contains("max") || key.contains("hbo") { return "tv.fill" }
        if key.contains("disney") { return "sparkles.tv.fill" }
        if key.contains("paramount") || key.contains("peacock") { return "tv.fill" }
        return "play.rectangle"
    }

    private func releaseBadgeHelpText(_ badge: String) -> String {
        let key = badge.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "new" {
            return "Recently released episode or season."
        }
        if key == "this week" {
            return "Release is expected this week."
        }
        if key == "upcoming" {
            return "Release is still ahead."
        }
        return "Release status."
    }

    private var bevelStrokeColors: [Color] {
        if colorScheme == .dark {
            return [Color.white.opacity(0.08), Color.black.opacity(0.22)]
        }
        return [Color.white.opacity(0.7), Color.black.opacity(0.10)]
    }

    private var primaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.10)
    }

    private var secondaryShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.14) : Color.black.opacity(0.05)
    }
}

