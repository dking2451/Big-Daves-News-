import SwiftUI

struct WatchView: View {
    @State private var allShows: [WatchShowItem] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showWatched = false
    @State private var selectedGenre = "All"
    @State private var selectedProvider = "All Providers"
    @State private var myListSort = "New Episodes"
    @State private var pendingRatingShow: WatchShowItem?
    private let deviceID = WatchDeviceIdentity.current

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && allShows.isEmpty {
                    ScrollView {
                        AppBrandedHeader(
                            sectionTitle: "Watch",
                            sectionSubtitle: "Trending shows, your list, and personalized picks"
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        LazyVStack(spacing: 14) {
                            ForEach(0..<6, id: \.self) { _ in
                                WatchCardSkeleton()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .redacted(reason: .placeholder)
                } else if !errorMessage.isEmpty && allShows.isEmpty {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    ScrollView {
                        AppBrandedHeader(
                            sectionTitle: "Watch",
                            sectionSubtitle: "Trending shows, your list, and personalized picks"
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        Toggle("Show watched", isOn: $showWatched)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .onChange(of: showWatched) { _ in
                                Task { await refresh() }
                            }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(genreFilters, id: \.self) { genre in
                                    Button {
                                        selectedGenre = genre
                                        Task { await refresh() }
                                    } label: {
                                        Label(genre, systemImage: genreIcon(for: genre))
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(
                                                selectedGenre == genre
                                                    ? Color.blue
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
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(providerFilters, id: \.self) { provider in
                                    Button {
                                        selectedProvider = provider
                                    } label: {
                                        Label(provider, systemImage: providerIcon(for: provider))
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(
                                                selectedProvider == provider
                                                    ? Color.teal
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
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                        }

                        if selectedGenre == "My List" {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(myListSortOptions, id: \.self) { option in
                                        Button {
                                            myListSort = option
                                        } label: {
                                            Label(option, systemImage: myListSortIcon(for: option))
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 8)
                                                .background(
                                                    myListSort == option
                                                        ? Color.indigo
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
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                            }
                        }

                        LazyVStack(spacing: 14) {
                            if filteredShows.isEmpty {
                                VStack(spacing: 10) {
                                    Text("No shows match these filters.")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Try a different provider, genre, or reset your filters.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                    if hasActiveFilters {
                                        Button("Reset Filters") {
                                            resetFilters()
                                            Task { await refresh() }
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                            } else {
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .refreshable { await refresh() }
                }
            }
            .navigationTitle("")
            .task {
                if allShows.isEmpty {
                    await refresh()
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
                onlySaved: selectedGenre == "My List" || selectedGenre == "New Episodes"
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
            await MainActor.run {
                let currentItem = self.allShows.first(where: { $0.id == showID })
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
}

private struct WatchCardSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemFill))
                .frame(width: 72, height: 104)
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
                    .frame(width: 160, height: 12)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct WatchShowCard: View {
    let show: WatchShowItem
    let onToggleSeen: (Bool) -> Void
    let onReaction: (String) -> Void
    let onToggleSaved: (Bool) -> Void
    let onCaughtUp: () -> Void

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
            .frame(width: 72, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(show.title)
                        .font(.headline)
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
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    Text(show.seasonEpisodeStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if show.saved == true, show.isNewEpisode == true {
                        Image(systemName: "sparkles.tv.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.18))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                            .accessibilityLabel("New episode available")
                    }
                }

                Text(show.synopsis)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("Where to stream")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(show.providers, id: \.self) { provider in
                            Label(provider, systemImage: providerIcon(for: provider))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
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
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel((show.saved ?? false) ? "Saved" : "Save to watchlist")

                        Button {
                            onToggleSeen(!(show.seen ?? false))
                        } label: {
                            Image(systemName: (show.seen ?? false) ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel((show.seen ?? false) ? "Seen" : "Mark as seen")

                        Button {
                            onReaction((show.userReaction == "up") ? "none" : "up")
                        } label: {
                            Label("\(show.upvotes ?? 0)", systemImage: show.userReaction == "up" ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.caption)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onReaction((show.userReaction == "down") ? "none" : "down")
                        } label: {
                            Label("\(show.downvotes ?? 0)", systemImage: show.userReaction == "down" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.caption)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.bordered)

                        if show.saved == true, show.isNewEpisode == true {
                            Button {
                                onCaughtUp()
                            } label: {
                                Label("Caught Up", systemImage: "checkmark.seal")
                                    .font(.caption)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
}

