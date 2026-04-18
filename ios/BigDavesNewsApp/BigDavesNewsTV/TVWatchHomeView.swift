import SwiftUI

@MainActor
final class TVWatchHomeViewModel: ObservableObject {
    @Published var allItems: [TVWatchShowItem] = []
    @Published var myListItems: [TVWatchShowItem] = []
    @Published var isLoading = true
    @Published var myListLoading = false
    @Published var loadError: String?
    @Published var myListLoadError: String?
    /// Snapshot from `ProfileSyncCoordinator` after each load (drives rails with synced state).
    @Published private(set) var composedProfile: ComposedUserProfile?

    /// Syncs from the coordinator; hits the network **only** when no profile is cached yet (cold start / cleared cache).
    func ensureProfileLoaded() async {
        syncComposedProfileWithCoordinator()
        guard ProfileSyncCoordinator.shared.profile == nil else { return }
        await ProfileSyncCoordinator.shared.refreshFromServer()
        syncComposedProfileWithCoordinator()
    }

    func load() async {
        isLoading = true
        loadError = nil
        await ensureProfileLoaded()
        do {
            let items = try await TVAPIClient.shared.fetchWatchShows(
                userId: SyncedUserIdentity.apiUserKey,
                limit: 45,
                minimumCount: 30
            )
            allItems = items
        } catch {
            loadError = TVShellErrorCopy.title
            if allItems.isEmpty { allItems = [] }
        }
        isLoading = false
    }

    func loadMyList() async {
        myListLoading = true
        myListLoadError = nil
        await ensureProfileLoaded()
        do {
            myListItems = try await TVAPIClient.shared.fetchWatchShowsMyList(
                userId: SyncedUserIdentity.apiUserKey,
                limit: 50,
                minimumCount: 24
            )
        } catch {
            myListLoadError = TVShellErrorCopy.title
            if myListItems.isEmpty { myListItems = [] }
        }
        myListLoading = false
    }

    func reloadAfterDetailChange() async {
        syncComposedProfileWithCoordinator()
        do {
            async let home = TVAPIClient.shared.fetchWatchShows(
                userId: SyncedUserIdentity.apiUserKey,
                limit: 45,
                minimumCount: 30
            )
            async let mine = TVAPIClient.shared.fetchWatchShowsMyList(
                userId: SyncedUserIdentity.apiUserKey,
                limit: 50,
                minimumCount: 24
            )
            let (h, m) = try await (home, mine)
            allItems = h
            myListItems = m
        } catch {
            loadError = TVShellErrorCopy.title
        }
    }

    /// After a successful PATCH, coordinator already has fresh profile; re-fetch watch feeds.
    func refreshAfterProfileMutation() async {
        composedProfile = ProfileSyncCoordinator.shared.profile
        do {
            async let home = TVAPIClient.shared.fetchWatchShows(
                userId: SyncedUserIdentity.apiUserKey,
                limit: 45,
                minimumCount: 30
            )
            async let mine = TVAPIClient.shared.fetchWatchShowsMyList(
                userId: SyncedUserIdentity.apiUserKey,
                limit: 50,
                minimumCount: 24
            )
            let (h, m) = try await (home, mine)
            allItems = h
            myListItems = m
        } catch {
            loadError = TVShellErrorCopy.title
        }
    }

    /// Keeps published profile snapshot aligned with `ProfileSyncCoordinator` after an optimistic merge.
    func syncComposedProfileWithCoordinator() {
        composedProfile = ProfileSyncCoordinator.shared.profile
    }

    // MARK: - Profile-derived sets (source of truth from composed profile)

    private var profile: ComposedUserProfile? { composedProfile }

    /// When the API sends `home_feed_section`, rails are **non-overlapping** server buckets (deduped).
    private var usesServerHomeSections: Bool {
        allItems.contains { !($0.homeFeedSection ?? "").isEmpty }
    }

    private func sortedByRankOrder(_ rows: [TVWatchShowItem]) -> [TVWatchShowItem] {
        rows.sorted {
            let a = $0.rankOrder ?? Int.max
            let b = $1.rankOrder ?? Int.max
            if a != b { return a < b }
            return $0.id < $1.id
        }
    }

    /// Synced saved ids (profile ∪ API flags on loaded rows).
    private var savedIds: Set<String> {
        let fromProf = Set(profile?.watchBlock.savedShowIds ?? [])
        let fromHome = Set(allItems.filter { $0.saved == true }.map(\.id))
        let fromMyList = Set(myListItems.map(\.id))
        return fromProf.union(fromHome).union(fromMyList)
    }

    /// True when the composed profile reports no saved shows (source of truth for empty My List).
    var myListIsEmptyPerProfile: Bool {
        let ids = profile?.watchBlock.savedShowIds ?? []
        return ids.isEmpty
    }

    /// When false, Home hides New Episodes / Continue / From Your List so **More Picks** carries the screen.
    var homeShowsPersonalizedRails: Bool {
        !savedIds.isEmpty || allItems.contains { effectiveProgress(for: $0) == .watching }
    }

    /// Lower index = more recent surface in `behavior.recently_surfaced`.
    private func interactionRecencyRank(showId: String) -> Int {
        let surf = profile?.behaviorBlock.recentlySurfaced ?? []
        for (i, e) in surf.enumerated() {
            if e.showId == showId { return i }
        }
        return 9_999
    }

    private var passedIds: Set<String> {
        Set(profile?.watchBlock.passedShowIds ?? [])
    }

    func effectiveProgress(for item: TVWatchShowItem) -> WatchProgressTV {
        if let m = profile?.watchBlock.watchStateByShow, let raw = m[item.id]?.lowercased() {
            if raw == "watching" { return .watching }
            if raw == "finished" { return .finished }
            if raw == "not_started" { return .notStarted }
        }
        return item.watchProgressState
    }

    private var preferredProviders: Set<String> {
        Set(
            (profile?.prefs.preferredProviders ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    func providerMatches(_ show: TVWatchShowItem) -> Bool {
        let pref = preferredProviders
        guard !pref.isEmpty else { return true }
        let prim = show.primaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if pref.contains(where: { prim.contains($0) || $0.contains(prim) }) { return true }
        return show.providers.map { $0.lowercased() }.contains { pv in
            pref.contains { pv.contains($0) || $0.contains(pv) }
        }
    }

    /// Tonight’s hero: prefer server `tonight_pick`; else legacy heuristics.
    var tonightsHero: TVWatchShowItem? {
        if usesServerHomeSections,
           let h = allItems.first(where: { $0.homeFeedSection == "tonight_pick" })
        {
            return h
        }
        let passed = passedIds
        let pool = allItems.filter { !passed.contains($0.id) }
        let filtered = pool.filter { show in
            let st = effectiveProgress(for: show)
            if st == .finished && show.isNewEpisode != true { return false }
            return providerMatches(show)
        }
        let use = filtered.isEmpty ? pool.filter { !passed.contains($0.id) } : filtered
        return use.first ?? allItems.first
    }

    var newEpisodesRail: [TVWatchShowItem] {
        if usesServerHomeSections {
            return sortedByRankOrder(allItems.filter { $0.homeFeedSection == "new_episodes" })
        }
        let saved = savedIds
        let items = allItems.filter { item in
            let urgent =
                item.isNewEpisode == true
                || (item.releaseBadge?.lowercased() == "new")
                || (item.releaseBadge?.lowercased() == "this_week")
                || item.isUpcomingRelease == true
            guard urgent else { return false }
            return saved.contains(item.id) || effectiveProgress(for: item) == .watching
        }
        return Array(items.prefix(5))
    }

    var continueRail: [TVWatchShowItem] {
        if usesServerHomeSections {
            return sortedByRankOrder(allItems.filter { $0.homeFeedSection == "continue_watching" })
        }
        let items = allItems.filter { effectiveProgress(for: $0) == .watching && !passedIds.contains($0.id) }
        return Array(items.prefix(10))
    }

    var fromYourListRail: [TVWatchShowItem] {
        if usesServerHomeSections {
            return sortedByRankOrder(allItems.filter { $0.homeFeedSection == "from_your_list" })
        }
        let passed = passedIds
        let rows = allItems.filter { savedIds.contains($0.id) && !passed.contains($0.id) }
        let sorted = rows.sorted { lhs, rhs in
            let lw = effectiveProgress(for: lhs) == .watching ? 1 : 0
            let rw = effectiveProgress(for: rhs) == .watching ? 1 : 0
            if lw != rw { return lw > rw }
            let ln = lhs.isNewEpisode == true ? 1 : 0
            let rn = rhs.isNewEpisode == true ? 1 : 0
            if ln != rn { return ln > rn }
            return (lhs.savedAtUTC ?? "") > (rhs.savedAtUTC ?? "")
        }
        return Array(sorted.prefix(12))
    }

    var morePicksRail: [TVWatchShowItem] {
        if usesServerHomeSections {
            return sortedByRankOrder(allItems.filter { $0.homeFeedSection == "more_picks" })
        }
        var used = Set<String>()
        if let h = tonightsHero { used.insert(h.id) }
        if homeShowsPersonalizedRails {
            newEpisodesRail.forEach { used.insert($0.id) }
            continueRail.forEach { used.insert($0.id) }
            fromYourListRail.forEach { used.insert($0.id) }
        }
        var out = allItems.filter { !used.contains($0.id) && !passedIds.contains($0.id) }
        if out.count < 6 {
            out = allItems.filter { !used.contains($0.id) }
        }
        return Array(out.prefix(18))
    }

    // MARK: - My List rails (same components as Home; profile + `myListItems`)

    private func myListNewEpisodeSignal(_ item: TVWatchShowItem) -> Bool {
        item.isNewEpisode == true
            || (item.releaseBadge?.lowercased() == "new")
            || (item.releaseBadge?.lowercased() == "this_week")
            || item.isUpcomingRelease == true
    }

    private func startWatchingPriorityScore(_ item: TVWatchShowItem) -> (Int, String) {
        let st = effectiveProgress(for: item)
        let ne = myListNewEpisodeSignal(item)
        let tier: Int
        if st == .watching, ne {
            tier = 4
        } else if st == .watching {
            tier = 3
        } else if st != .watching, ne {
            // Saved + new episode (non-watching rows only; finished already excluded upstream).
            tier = 2
        } else {
            tier = 1
        }
        return (tier, item.savedAtUTC ?? "")
    }

    var myListStartWatchingRail: [TVWatchShowItem] {
        let passed = passedIds
        let rows = myListItems.filter { savedIds.contains($0.id) && !passed.contains($0.id) && effectiveProgress(for: $0) != .finished }
        let sorted = rows.sorted { lhs, rhs in
            let lt = startWatchingPriorityScore(lhs)
            let rt = startWatchingPriorityScore(rhs)
            if lt.0 != rt.0 { return lt.0 > rt.0 }
            return lt.1 > rt.1
        }
        return Array(sorted.prefix(3))
    }

    var myListContinueWatchingRail: [TVWatchShowItem] {
        let rows = myListItems.filter { effectiveProgress(for: $0) == .watching && !passedIds.contains($0.id) }
        return rows.sorted { lhs, rhs in
            let li = interactionRecencyRank(showId: lhs.id)
            let ri = interactionRecencyRank(showId: rhs.id)
            if li != ri { return li < ri }
            return (lhs.savedAtUTC ?? "") > (rhs.savedAtUTC ?? "")
        }
    }

    var myListFromYourListRail: [TVWatchShowItem] {
        let passed = passedIds
        let rows = myListItems.filter { savedIds.contains($0.id) && !passed.contains($0.id) }
        return rows.sorted { lhs, rhs in
            let lw = effectiveProgress(for: lhs) == .watching ? 1 : 0
            let rw = effectiveProgress(for: rhs) == .watching ? 1 : 0
            if lw != rw { return lw > rw }
            let ln = myListNewEpisodeSignal(lhs) ? 1 : 0
            let rn = myListNewEpisodeSignal(rhs) ? 1 : 0
            if ln != rn { return ln > rn }
            let ls = lhs.savedAtUTC ?? ""
            let rs = rhs.savedAtUTC ?? ""
            if ls != rs { return ls > rs }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var myListFinishedRail: [TVWatchShowItem] {
        let rows = myListItems.filter { effectiveProgress(for: $0) == .finished && !passedIds.contains($0.id) }
        let sorted = rows.sorted { lhs, rhs in
            let li = interactionRecencyRank(showId: lhs.id)
            let ri = interactionRecencyRank(showId: rhs.id)
            if li != ri { return li < ri }
            return (lhs.savedAtUTC ?? "") > (rhs.savedAtUTC ?? "")
        }
        return Array(sorted.prefix(15))
    }

    var primaryOpenTitle: String {
        guard let show = tonightsHero else { return "Open to watch" }
        return TVProviderCatalog.definition(primary: show.primaryProvider, providers: show.providers)?
            .primaryActionTitle ?? "Open to watch"
    }
}

struct TVWatchHomeView: View {
    @EnvironmentObject private var viewModel: TVWatchHomeViewModel
    var onSelectShow: (TVWatchShowItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVLayout.sectionGap) {
                if viewModel.isLoading && viewModel.allItems.isEmpty {
                    ProgressView("Loading your Watch picks…")
                        .padding(.top, TVLayout.Spacing.s24 * 5)
                        .frame(maxWidth: .infinity)
                } else if let hero = viewModel.tonightsHero {
                    TVHeroShowcaseView(
                        show: hero,
                        reason: hero.recommendationReason,
                        primaryTitle: viewModel.primaryOpenTitle,
                        onPrimary: {
                            Task { await TVProviderCatalog.open(hero) }
                        },
                        onDetails: { onSelectShow(hero) }
                    )
                    .focusSection()

                    if viewModel.homeShowsPersonalizedRails {
                        if !viewModel.newEpisodesRail.isEmpty {
                            TVContentRail(
                                title: "New Episodes for You",
                                subtitle: "From your saved and in-progress shows"
                            ) {
                                ForEach(viewModel.newEpisodesRail) { show in
                                    TVPosterCard(show: show, footnote: show.primaryProvider) {
                                        onSelectShow(show)
                                    }
                                }
                            }
                        }

                        if !viewModel.continueRail.isEmpty {
                            TVContentRail(title: "Continue Watching", subtitle: "Pick up where you left off") {
                                ForEach(viewModel.continueRail) { show in
                                    TVPosterCard(show: show, footnote: show.primaryProvider) {
                                        onSelectShow(show)
                                    }
                                }
                            }
                        }

                        if !viewModel.fromYourListRail.isEmpty {
                            TVContentRail(title: "From Your List", subtitle: "Saved and ready when you are") {
                                ForEach(viewModel.fromYourListRail) { show in
                                    TVPosterCard(show: show, footnote: show.primaryProvider) {
                                        onSelectShow(show)
                                    }
                                }
                            }
                        }
                    }

                    if !viewModel.morePicksRail.isEmpty {
                        TVContentRail(title: "More Picks", subtitle: "Personalized discovery") {
                            ForEach(viewModel.morePicksRail) { show in
                                TVPosterCard(
                                    show: show,
                                    footnote: show.recommendationReason ?? show.primaryProvider
                                ) {
                                    onSelectShow(show)
                                }
                            }
                        }
                    }
                } else {
                    homeEmptyState
                }

                if let err = viewModel.loadError,
                   viewModel.tonightsHero != nil || !viewModel.allItems.isEmpty
                {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVLayout.contentGutter)
                }
            }
            .padding(.top, TVLayout.screenTopInset)
        }
        .background(TVLayout.appBackground)
        .task { await viewModel.load() }
        .onAppear {
            if viewModel.allItems.isEmpty, !viewModel.isLoading {
                Task { await viewModel.load() }
            }
        }
    }

    @ViewBuilder
    private var homeEmptyState: some View {
        if viewModel.loadError != nil {
            TVEmptyStateMessage(
                title: TVShellErrorCopy.title,
                subtitle: TVShellErrorCopy.subtitle,
                retryTitle: "Try again",
                retryAction: { Task { await viewModel.load() } }
            )
        } else {
            TVEmptyStateMessage(
                title: "Nothing to watch yet",
                subtitle: "New picks will show up here when they’re ready.",
                retryTitle: "Try again",
                retryAction: { Task { await viewModel.load() } }
            )
        }
    }
}
