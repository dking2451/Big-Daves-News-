import SwiftUI

@MainActor
final class TVSportsViewModel: ObservableObject {
    @Published var events: [TVSportsEventItem] = []
    @Published private(set) var profile: ComposedUserProfile?
    @Published var isLoading = true
    @Published var loadError: String?

    func load(prefetchedProfile: ComposedUserProfile?) async {
        isLoading = true
        loadError = nil
        profile = prefetchedProfile ?? ProfileSyncCoordinator.shared.profile
        do {
            events = try await TVAPIClient.shared.fetchSportsNow(
                deviceId: SyncedUserIdentity.apiUserKey,
                windowHours: 12,
                timezoneName: TimeZone.current.identifier,
                includeOcho: false
            )
        } catch {
            loadError = TVShellErrorCopy.title
            if events.isEmpty { events = [] }
        }
        isLoading = false
    }

    private func normalizedToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Extra boost when synced profile lists teams/leagues not yet reflected on the server row.
    private func profileFavoriteBoost(_ event: TVSportsEventItem) -> Int {
        guard let profile else { return 0 }
        let leaguePrefs = Set((profile.prefs.favoriteLeagues ?? []).map(normalizedToken).filter { !$0.isEmpty })
        let teamPrefs = Set((profile.prefs.favoriteTeams ?? []).map(normalizedToken).filter { !$0.isEmpty })
        var score = 0
        let league = normalizedToken(event.league)
        if !league.isEmpty, leaguePrefs.contains(league) { score += 4 }
        let h = normalizedToken(event.homeTeam)
        let a = normalizedToken(event.awayTeam)
        if !h.isEmpty, teamPrefs.contains(h) { score += 5 }
        if !a.isEmpty, teamPrefs.contains(a) { score += 5 }
        return score
    }

    private func apiFavoriteWeight(_ event: TVSportsEventItem) -> Int {
        var w = 0
        if event.isFavoriteLeague == true { w += 4 }
        w += min(6, (event.favoriteTeamCount ?? 0) * 3)
        if let r = event.rankingScore { w += Int(min(5, max(0, r))) }
        return w
    }

    private func prioritySort(_ lhs: TVSportsEventItem, _ rhs: TVSportsEventItem) -> Bool {
        let lp = apiFavoriteWeight(lhs) + profileFavoriteBoost(lhs)
        let rp = apiFavoriteWeight(rhs) + profileFavoriteBoost(rhs)
        if lp != rp { return lp > rp }
        if lhs.isLive != rhs.isLive { return lhs.isLive && !rhs.isLive }
        return lhs.startsInMinutes < rhs.startsInMinutes
    }

    private func activeEvents(_ list: [TVSportsEventItem]) -> [TVSportsEventItem] {
        list.filter { !$0.isFinal }
    }

    func isFavoriteMatch(_ event: TVSportsEventItem) -> Bool {
        if event.isFavoriteLeague == true { return true }
        if let c = event.favoriteTeamCount, c > 0 { return true }
        return profileFavoriteBoost(event) > 0
    }

    var liveNowRail: [TVSportsEventItem] {
        let rows = activeEvents(events).filter { $0.isLive || $0.resolvedTimingLabel() == "live_now" }
        return rows.sorted(by: prioritySort)
    }

    var startingSoonRail: [TVSportsEventItem] {
        let rows = activeEvents(events).filter {
            !$0.isLive && $0.resolvedTimingLabel() == "starting_soon"
        }
        return rows.sorted(by: prioritySort)
    }

    var tonightRail: [TVSportsEventItem] {
        let rows = activeEvents(events).filter {
            !$0.isLive && $0.resolvedTimingLabel() == "tonight"
        }
        return rows.sorted(by: prioritySort)
    }

    var favoritesRail: [TVSportsEventItem] {
        let rows = activeEvents(events).filter { isFavoriteMatch($0) }
        return rows.sorted(by: prioritySort)
    }

    var hasAnyRails: Bool {
        !liveNowRail.isEmpty
            || !startingSoonRail.isEmpty
            || !tonightRail.isEmpty
            || !favoritesRail.isEmpty
    }
}

struct TVSportsView: View {
    @EnvironmentObject private var homeModel: TVWatchHomeViewModel
    @StateObject private var sportsModel = TVSportsViewModel()
    var onSelectEvent: (TVSportsEventItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVLayout.sectionGap) {
                if sportsModel.isLoading && sportsModel.events.isEmpty {
                    ProgressView("Loading sports…")
                        .padding(.top, TVLayout.Spacing.s24 * 5)
                        .frame(maxWidth: .infinity)
                } else if !sportsModel.hasAnyRails {
                    if sportsModel.loadError != nil {
                        TVEmptyStateMessage(
                            title: TVShellErrorCopy.title,
                            subtitle: TVShellErrorCopy.subtitle,
                            retryTitle: "Try again",
                            retryAction: {
                                Task {
                                    await homeModel.ensureProfileLoaded()
                                    await sportsModel.load(prefetchedProfile: homeModel.composedProfile)
                                }
                            }
                        )
                    } else {
                        emptyStateNoGames
                    }
                } else {
                    if !sportsModel.liveNowRail.isEmpty {
                        TVContentRail(title: "Live Now", subtitle: TVSportsRailCopy.liveSubtitle) {
                            ForEach(sportsModel.liveNowRail) { event in
                                TVSportsEventCard(event: event) {
                                    onSelectEvent(event)
                                }
                            }
                        }
                    }
                    if !sportsModel.startingSoonRail.isEmpty {
                        TVContentRail(title: "Starting Soon", subtitle: TVSportsRailCopy.startingSoonSubtitle) {
                            ForEach(sportsModel.startingSoonRail) { event in
                                TVSportsEventCard(event: event) {
                                    onSelectEvent(event)
                                }
                            }
                        }
                    }
                    if !sportsModel.tonightRail.isEmpty {
                        TVContentRail(title: "Tonight", subtitle: TVSportsRailCopy.tonightSubtitle) {
                            ForEach(sportsModel.tonightRail) { event in
                                TVSportsEventCard(event: event) {
                                    onSelectEvent(event)
                                }
                            }
                        }
                    }
                    if !sportsModel.favoritesRail.isEmpty {
                        TVContentRail(title: "Favorites", subtitle: "Your leagues & teams") {
                            ForEach(sportsModel.favoritesRail) { event in
                                TVSportsEventCard(event: event) {
                                    onSelectEvent(event)
                                }
                            }
                        }
                    }
                }

                if let err = sportsModel.loadError, sportsModel.hasAnyRails {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVLayout.contentGutter)
                }
            }
            .padding(.top, TVLayout.screenTopInset)
        }
        .background(TVLayout.appBackground)
        .task {
            await homeModel.ensureProfileLoaded()
            await sportsModel.load(prefetchedProfile: homeModel.composedProfile)
        }
        .onAppear {
            if sportsModel.events.isEmpty, !sportsModel.isLoading {
                Task {
                    await homeModel.ensureProfileLoaded()
                    await sportsModel.load(prefetchedProfile: homeModel.composedProfile)
                }
            }
        }
    }

    private var emptyStateNoGames: some View {
        TVEmptyStateMessage(
            title: "No games right now",
            subtitle: "Check back later for live events."
        )
    }
}
