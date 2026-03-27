import SwiftUI

/// User-facing names for league filter UI (matches backend `league` labels from `/api/sports/now`).
private enum SportsLeagueFilterDisplay {
    static func title(forBackendLabel label: String) -> String {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "NCAAF":
            return "NCAA Football"
        case "NCAAB":
            return "NCAA Basketball"
        default:
            return label
        }
    }
}

// MARK: - THE OCHO (Sports) copy & chrome

private enum OchoCopy {
    /// Entry card — title line (shown next to Sasquatch).
    static let entryTitle = "THE OCHO"
    /// Entry card — body under the title.
    static let entrySubtitle = "Obscure sports, alt feeds, and hand-picked listings—tap to turn it on."
    /// Active strip — main headline when mode is on.
    static let activeHeadline = "THE OCHO is on"
    /// Active strip — supporting line.
    static let activeSubhead = "You’re browsing alternate sports and curated discovery feeds."
    /// Primary exit control (also in toolbar).
    static let exitButtonTitle = "Exit Ocho"
    static let exitAccessibilityHint = "Returns to the standard Live Sports layout and filters."
    /// Curated / Stadium-style listings disclaimer.
    static let curatedDisclaimer =
        "Some listings are hand-curated or use stadium-style schedules. They may not match live TV or streaming availability in your area."
    static let entryAccessibilityHint = "Turns on THE OCHO channel styling and alt-sports discovery."
}

/// Header hero: one rotating line picked when entering Ocho mode.
private enum OchoHeroCopy {
    static let mainTitle = "THE OCHO"
    static let subtitle = "Alt Sports"
    static let supportingLine = "Live, weird, and worth watching"
    static let rotatingTaglines = [
        "Real sports. Just not the ones you expected.",
        "Tonight's lineup is a little unhinged.",
        "Somebody is competing in something right now."
    ]
}

@MainActor
final class SportsViewModel: ObservableObject {
    private enum Storage {
        static let selectedLeaguesKey = "bdn.sports.selectedLeagues.v1"
    }

    @Published var items: [SportsEventItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isOchoMode = false
    @Published var includeAltSports = false
    /// Normalized league names to show. Empty = all leagues (no filter).
    @Published var selectedLeagues: Set<String> = SportsViewModel.loadPersistedSelectedLeagues() {
        didSet { persistSelectedLeagues() }
    }

    @Published var selectedTeam = "All Teams"
    @Published var selectedWindowHours = 4
    @Published var favoriteLeagues: Set<String> = []
    @Published var favoriteTeams: Set<String> = []
    /// Last `/api/sports/now` Ocho status blob (nil when `include_ocho` was false or older API).
    @Published var ochoFeedStatus: OchoFeedStatus?

    let windowOptions = [2, 4, 6, 12]
    private let deviceID = WatchDeviceIdentity.current

    private static func loadPersistedSelectedLeagues() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: Storage.selectedLeaguesKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(arr)
    }

    private func persistSelectedLeagues() {
        let arr = Array(selectedLeagues).sorted()
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: Storage.selectedLeaguesKey)
        }
    }

    var displayItems: [SportsEventItem] {
        if !isOchoMode {
            return items
        }
        return items.filter(isOchoEvent)
    }

    var filteredItems: [SportsEventItem] {
        let leagueScoped: [SportsEventItem]
        if selectedLeagues.isEmpty {
            leagueScoped = displayItems
        } else {
            leagueScoped = displayItems.filter { selectedLeagues.contains(normalizedLeague($0.league)) }
        }
        if selectedTeam == "All Teams" {
            return leagueScoped
        }
        let normalized = normalizedTeam(selectedTeam)
        return leagueScoped.filter { item in
            normalizedTeam(item.homeTeam) == normalized || normalizedTeam(item.awayTeam) == normalized
        }
    }

    var liveItems: [SportsEventItem] {
        orderEventsByFavoriteTeams(filteredItems.filter { $0.isLive })
    }

    var startingSoonItems: [SportsEventItem] {
        let base = filteredItems
            .filter { !$0.isLive && !$0.isFinal }
            .sorted { $0.startsInMinutes < $1.startsInMinutes }
        return orderEventsByFavoriteTeams(base)
    }

    /// Ocho-only partitions: live (cap 3), starting within 2h, later tonight, then everything else (curated / fallback).
    struct OchoFeedSections: Equatable {
        let live: [SportsEventItem]
        let startingSoon: [SportsEventItem]
        let tonight: [SportsEventItem]
        let worthALook: [SportsEventItem]

        static let empty = OchoFeedSections(live: [], startingSoon: [], tonight: [], worthALook: [])

        static func == (lhs: OchoFeedSections, rhs: OchoFeedSections) -> Bool {
            lhs.live.map(\.id) == rhs.live.map(\.id)
                && lhs.startingSoon.map(\.id) == rhs.startingSoon.map(\.id)
                && lhs.tonight.map(\.id) == rhs.tonight.map(\.id)
                && lhs.worthALook.map(\.id) == rhs.worthALook.map(\.id)
        }
    }

    var ochoFeedSections: OchoFeedSections {
        guard isOchoMode else { return .empty }
        let base = orderEventsByFavoriteTeams(filteredItems.filter { !$0.isFinal })
        var used = Set<String>()

        let live = Array(base.filter(\.isLive).prefix(3))
        live.forEach { used.insert($0.id) }

        let startingSoon = base.filter { item in
            !item.isLive && !used.contains(item.id) && item.startsInMinutes >= 0 && item.startsInMinutes <= 120
        }
        .sorted { $0.startsInMinutes < $1.startsInMinutes }
        startingSoon.forEach { used.insert($0.id) }

        let tonight = base.filter { item in
            guard !item.isLive, !used.contains(item.id) else { return false }
            let timing = (item.timingLabel ?? "").lowercased()
            if timing == "tonight" { return true }
            if item.startsInMinutes > 120 && Self._isStartLocalToday(item) { return true }
            return false
        }
        .sorted { $0.startsInMinutes < $1.startsInMinutes }
        tonight.forEach { used.insert($0.id) }

        let worthALook = base.filter { item in !item.isLive && !used.contains(item.id) }
            .sorted { $0.startsInMinutes < $1.startsInMinutes }

        return OchoFeedSections(
            live: live,
            startingSoon: startingSoon,
            tonight: tonight,
            worthALook: worthALook
        )
    }

    private static func _isStartLocalToday(_ item: SportsEventItem) -> Bool {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        guard let date = isoFrac.date(from: item.startTimeLocal) ?? isoPlain.date(from: item.startTimeLocal) else {
            return false
        }
        return Calendar.current.isDateInToday(date)
    }

    /// Merges synced favorites with **local** picks (Settings / onboarding) for ordering only.
    private func mergedFavoriteTeamsIncludingLocal() -> Set<String> {
        favoriteTeams.union(LocalUserPreferences.shared.favoriteTeamsNormalized)
    }

    private func mergedFavoriteLeaguesIncludingLocal() -> Set<String> {
        LocalUserPreferences.shared.favoriteLeaguesNormalized
    }

    private func eventTouchesFavorite(_ item: SportsEventItem, teamFavs: Set<String>, leagueFavs: Set<String>) -> Bool {
        if teamFavs.contains(normalizedTeam(item.homeTeam)) || teamFavs.contains(normalizedTeam(item.awayTeam)) {
            return true
        }
        return leagueFavs.contains(normalizedLeague(item.league))
    }

    private func orderEventsByFavoriteTeams(_ items: [SportsEventItem]) -> [SportsEventItem] {
        let teams = mergedFavoriteTeamsIncludingLocal()
        let leagues = mergedFavoriteLeaguesIncludingLocal()
        guard !teams.isEmpty || !leagues.isEmpty else { return items }
        return items.sorted { lhs, rhs in
            let l = eventTouchesFavorite(lhs, teamFavs: teams, leagueFavs: leagues)
            let r = eventTouchesFavorite(rhs, teamFavs: teams, leagueFavs: leagues)
            if l != r { return l && !r }
            if lhs.startsInMinutes != rhs.startsInMinutes {
                return lhs.startsInMinutes < rhs.startsInMinutes
            }
            return lhs.eventID < rhs.eventID
        }
    }

    /// Matches backend `app/sports.py` `CORE_LEAGUE_CONFIGS` labels so NCAA (and other core leagues) always appear in Customize even when no games fall in the current window.
    private static let coreLeagueLabelsAlwaysInFilter: [String] = [
        "NFL", "NCAAF", "NBA", "NCAAB", "MLB", "NHL", "MLS"
    ]

    var leagueFilters: [String] {
        var result = ["All"]
        let fromFeed = Set(displayItems.map { $0.league.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let merged = fromFeed.union(Set(Self.coreLeagueLabelsAlwaysInFilter))
        result.append(contentsOf: merged.sorted())
        return result
    }

    /// Display names for leagues currently included in the filter (sorted).
    var selectedLeagueFilterSummary: String {
        guard !selectedLeagues.isEmpty else { return "" }
        let names = leagueFilters.filter { $0 != "All" && selectedLeagues.contains(normalizedLeague($0)) }
        return names.map { SportsLeagueFilterDisplay.title(forBackendLabel: $0) }.sorted().joined(separator: ", ")
    }

    var teamFilters: [String] {
        var result = ["All Teams"]
        var seen: Set<String> = []
        for item in displayItems {
            for team in [item.homeTeam, item.awayTeam] {
                let normalized = normalizedTeam(team)
                if normalized.isEmpty || seen.contains(normalized) {
                    continue
                }
                seen.insert(normalized)
                result.append(team.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return result
    }

    var favoriteLeagueList: [String] {
        favoriteLeagues.sorted()
    }

    var favoriteTeamList: [String] {
        favoriteTeams.sorted()
    }

    func refreshPreferences() async {
        do {
            let payload = try await APIClient.shared.fetchSportsPreferences(deviceID: deviceID)
            favoriteLeagues = Set(payload.favoriteLeagues.map { normalizedLeague($0) }.filter { !$0.isEmpty })
            favoriteTeams = Set(payload.favoriteTeams.map { normalizedTeam($0) }.filter { !$0.isEmpty })
        } catch {
            // Keep current values if sync fails.
        }
    }

    func refresh(providerKey: String, availabilityOnly: Bool, includeOcho: Bool? = nil) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let shouldIncludeOcho = includeOcho ?? (isOchoMode || includeAltSports)
            let backendProvider = providerKey == SportsProviderPreferences.allProviderKey ? "" : providerKey
            // Ocho discovery mode ignores provider-only filtering to avoid hiding niche events.
            let effectiveAvailabilityOnly = isOchoMode ? false : (availabilityOnly && !backendProvider.isEmpty)
            let result = try await APIClient.shared.fetchSportsNow(
                windowHours: selectedWindowHours,
                timezoneName: TimeZone.current.identifier,
                providerKey: backendProvider,
                availabilityOnly: effectiveAvailabilityOnly,
                deviceID: deviceID,
                includeOcho: shouldIncludeOcho
            )
            items = result.items
            ochoFeedStatus = shouldIncludeOcho ? result.ochoFeedStatus : nil
            await SportsAlertsManager.shared.ingestLatestSports(items: result.items)
            let validNorms = Set(leagueFilters.filter { $0 != "All" }.map { normalizedLeague($0) })
            selectedLeagues = selectedLeagues.intersection(validNorms)
            if !teamFilters.contains(selectedTeam) {
                selectedTeam = "All Teams"
            }
            errorMessage = nil
            SportsLiveStatus.shared.apply(items: result.items)
        } catch {
            if items.isEmpty {
                errorMessage = "Live sports are temporarily unavailable."
            } else {
                errorMessage = "Could not refresh sports. Showing latest available."
            }
        }
    }

    func trackOpen() async {
        await APIClient.shared.trackEvent(
            deviceID: deviceID,
            eventName: "sports_open",
            eventProps: ["window_hours": String(selectedWindowHours)]
        )
    }

    func trackProviderFilter(providerKey: String, availabilityOnly: Bool) async {
        await APIClient.shared.trackEvent(
            deviceID: deviceID,
            eventName: "sports_filter_provider",
            eventProps: [
                "provider_key": providerKey,
                "availability_only": availabilityOnly ? "true" : "false"
            ]
        )
    }

    func trackWindowChange() async {
        await APIClient.shared.trackEvent(
            deviceID: deviceID,
            eventName: "sports_window_change",
            eventProps: ["window_hours": String(selectedWindowHours)]
        )
    }

    func trackFollowToggle(kind: String, value: String, following: Bool) async {
        await APIClient.shared.trackEvent(
            deviceID: deviceID,
            eventName: "sports_follow_toggle",
            eventProps: [
                "kind": kind,
                "value": value,
                "following": following ? "true" : "false"
            ]
        )
    }

    func trackCardOpen(_ item: SportsEventItem) async {
        await APIClient.shared.trackEvent(
            deviceID: deviceID,
            eventName: "sports_card_open",
            eventProps: [
                "event_id": item.eventID,
                "league": item.league,
                "is_live": (item.isLive ? "true" : "false"),
                "provider_available": ((item.isAvailableOnProvider ?? false) ? "true" : "false")
            ]
        )
    }

    func trackTemporaryProvider(enabled: Bool, providerKey: String) async {
        await APIClient.shared.trackEvent(
            deviceID: deviceID,
            eventName: enabled ? "sports_temp_provider_on" : "sports_temp_provider_off",
            eventProps: [
                "provider_key": providerKey
            ]
        )
    }

    private func normalizedLeague(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedTeam(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isOchoEvent(_ item: SportsEventItem) -> Bool {
        if item.isAltSport == true || item.ochoPromotedFromCore == true {
            return true
        }
        let league = normalizedLeague(item.league)
        let sport = normalizedLeague(item.sport)
        if league.contains("the ocho") || league.contains("ocho") {
            return true
        }
        if league.contains("ufc") || league.contains("pfl") || league.contains("bellator") {
            return true
        }
        if sport.contains("mma") || sport.contains("combat") {
            return true
        }
        if league.contains("australian rules") || league.contains("afl") {
            return true
        }
        if league.contains("nrl") || league.contains("rugby") {
            return true
        }
        if sport.contains("wrestling") {
            return true
        }
        if item.sourceType?.lowercased() == "curated" {
            return true
        }
        return false
    }

    func isLeagueFavorite(_ league: String) -> Bool {
        favoriteLeagues.contains(normalizedLeague(league))
    }

    func isTeamFavorite(_ team: String) -> Bool {
        favoriteTeams.contains(normalizedTeam(team))
    }

    func toggleLeagueFavorite(_ league: String) async {
        let normalized = normalizedLeague(league)
        guard !normalized.isEmpty else { return }
        let currentlyFavorite = favoriteLeagues.contains(normalized)
        if currentlyFavorite {
            favoriteLeagues.remove(normalized)
        } else {
            favoriteLeagues.insert(normalized)
        }
        AppHaptics.selection()
        await trackFollowToggle(kind: "league", value: normalized, following: !currentlyFavorite)
        await self.syncFavorites()
    }

    func toggleTeamFavorite(_ team: String) async {
        let normalized = normalizedTeam(team)
        guard !normalized.isEmpty else { return }
        let currentlyFavorite = favoriteTeams.contains(normalized)
        if currentlyFavorite {
            favoriteTeams.remove(normalized)
        } else {
            favoriteTeams.insert(normalized)
        }
        AppHaptics.selection()
        await trackFollowToggle(kind: "team", value: normalized, following: !currentlyFavorite)
        await self.syncFavorites()
    }

    func addTeamFavorite(_ team: String) async {
        let normalized = normalizedTeam(team)
        guard !normalized.isEmpty, !favoriteTeams.contains(normalized) else { return }
        favoriteTeams.insert(normalized)
        AppHaptics.selection()
        await trackFollowToggle(kind: "team", value: normalized, following: true)
        await self.syncFavorites()
    }

    func removeLeagueFavorite(_ league: String) async {
        let normalized = normalizedLeague(league)
        guard !normalized.isEmpty else { return }
        guard favoriteLeagues.contains(normalized) else { return }
        favoriteLeagues.remove(normalized)
        AppHaptics.lightImpact()
        await trackFollowToggle(kind: "league", value: normalized, following: false)
        await self.syncFavorites()
    }

    func removeTeamFavorite(_ team: String) async {
        let normalized = normalizedTeam(team)
        guard !normalized.isEmpty else { return }
        guard favoriteTeams.contains(normalized) else { return }
        favoriteTeams.remove(normalized)
        AppHaptics.lightImpact()
        await trackFollowToggle(kind: "team", value: normalized, following: false)
        await self.syncFavorites()
    }

    func clearAllFavorites() async {
        let leagues = favoriteLeagues
        let teams = favoriteTeams
        favoriteLeagues.removeAll()
        favoriteTeams.removeAll()
        AppHaptics.lightImpact()
        for league in leagues {
            await trackFollowToggle(kind: "league", value: league, following: false)
        }
        for team in teams {
            await trackFollowToggle(kind: "team", value: team, following: false)
        }
        await self.syncFavorites()
    }

    private func syncFavorites() async {
        do {
            try await APIClient.shared.setSportsPreferences(
                deviceID: deviceID,
                favoriteLeagues: favoriteLeagueList,
                favoriteTeams: favoriteTeamList
            )
        } catch {
            // Keep optimistic state on transient failures.
        }
    }
}

struct SportsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tonightModeActive) private var tonightModeActive
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var localUserPreferences = LocalUserPreferences.shared
    @StateObject private var vm = SportsViewModel()
    @AppStorage(SportsProviderPreferences.providerKeyStorageKey) private var sportsProviderKey = SportsProviderPreferences.allProviderKey
    @AppStorage(SportsProviderPreferences.availabilityOnlyStorageKey) private var sportsAvailabilityOnly = false
    @AppStorage(SportsProviderPreferences.temporaryProviderEnabledStorageKey) private var tempProviderEnabled = false
    @AppStorage(SportsProviderPreferences.temporaryProviderKeyStorageKey) private var tempProviderKey = SportsProviderPreferences.allProviderKey
    @State private var selectedEvent: SportsEventItem?
    @State private var showCustomizeSheet = false
    @State private var showSportsGuide = false
    @State private var ochoModeEnabled = false
    @AppStorage("bdn-sports-include-alt-ios") private var includeAltSports = false
    @State private var favoriteLeaguePicker = "NFL"
    @State private var favoriteTeamPicker = ""
    /// Index into `OchoHeroCopy.rotatingTaglines`; randomized when entering Ocho.
    @State private var ochoHeroTaglineIndex = 0
    @State private var ochoSurprisePick: SportsEventItem?

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                    VStack(alignment: .leading, spacing: DeviceLayout.screenIntentToBrandedSpacing) {
                        ScreenIntentHeader(
                            title: ochoModeEnabled ? "The Ocho" : "Live Sports",
                            subtitle: ochoModeEnabled ? "Alt sports discovery" : "What's live and what's next"
                        )
                        sportsHeroHeader
                    }

                    if ochoModeEnabled {
                        ochoActiveModeChrome
                    } else {
                        ochoEntryInvitationCard
                    }

                    sportsSummaryStrip

                    if vm.isLoading && vm.items.isEmpty {
                        SkeletonCard()
                        SkeletonCard()
                    }

                    if let error = vm.errorMessage {
                        AppContentStateCard(
                            kind: .error,
                            systemImage: "sportscourt.fill",
                            title: "Sports feed hit a snag",
                            message: error,
                            retryTitle: "Try again",
                            onRetry: {
                                Task {
                                    await vm.refresh(
                                        providerKey: effectiveProviderKey,
                                        availabilityOnly: sportsAvailabilityOnly
                                    )
                                }
                            },
                            isRetryDisabled: vm.isLoading,
                            compact: false
                        )
                    }

                    if ochoModeEnabled {
                        ochoSurpriseSection
                        ochoSectionedFeed(scrollProxy: scrollProxy)
                    } else if DeviceLayout.useRegularWidthTabletLayout(horizontalSizeClass: horizontalSizeClass) {
                        HStack(alignment: .top, spacing: 16) {
                            sportsLiveNowCard
                                .frame(maxWidth: .infinity, alignment: .leading)
                            sportsStartingSoonCard
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        sportsLiveNowCard
                        sportsStartingSoonCard
                    }
                }
                .frame(maxWidth: DeviceLayout.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, DeviceLayout.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            }
            .background(
                Group {
                    if ochoModeEnabled {
                        OchoArenaBackground()
                            .ignoresSafeArea()
                    } else {
                        ZStack {
                            AppTheme.pageBackground
                            if tonightModeActive {
                                AppTheme.tonightBackgroundOverlay(for: colorScheme)
                            }
                        }
                        .ignoresSafeArea()
                    }
                }
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await vm.refresh(
                    providerKey: sportsProviderKey,
                    availabilityOnly: sportsAvailabilityOnly
                )
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showCustomizeSheet = true
                    } label: {
                        AppToolbarIcon(systemName: "line.3.horizontal.decrease.circle", role: .neutral)
                            .foregroundStyle(ochoModeEnabled ? ochoAccentColor : AppTheme.secondaryText)
                    }
                    .accessibilityLabel("Customize sports")
                    .accessibilityHint("Opens filters, TV provider, favorites, and time window")
                    Button {
                        if ochoModeEnabled {
                            exitOchoMode()
                        } else {
                            enterOchoMode()
                        }
                    } label: {
                        AppToolbarIcon(systemName: ochoModeEnabled ? "8.circle.fill" : "8.circle", role: .neutral)
                            .foregroundStyle(ochoModeEnabled ? ochoAccentColor : AppTheme.secondaryText)
                    }
                    .accessibilityLabel(ochoModeEnabled ? OchoCopy.exitButtonTitle : OchoCopy.entryTitle)
                    .accessibilityHint(ochoModeEnabled ? OchoCopy.exitAccessibilityHint : OchoCopy.entryAccessibilityHint)
                    Button {
                        Task {
                            await vm.refresh(
                                providerKey: effectiveProviderKey,
                                availabilityOnly: sportsAvailabilityOnly
                            )
                        }
                    } label: {
                        AppToolbarIcon(systemName: "arrow.triangle.2.circlepath", role: .refresh)
                            .foregroundStyle(ochoModeEnabled ? ochoAccentColor : AppTheme.primary)
                    }
                    .accessibilityLabel("Refresh sports")
                    AppOverflowMenu(onHowSportsWorks: { showSportsGuide = true })
                }
            }
            .task {
                sportsProviderKey = SportsProviderPreferences.normalizedProviderKey(sportsProviderKey)
                if sportsProviderKey == SportsProviderPreferences.allProviderKey {
                    sportsAvailabilityOnly = false
                }
                await vm.trackOpen()
                await vm.refreshPreferences()
                vm.isOchoMode = ochoModeEnabled
                vm.includeAltSports = includeAltSports
                if let firstLeague = favoriteLeaguePickerOptions.first {
                    favoriteLeaguePicker = firstLeague
                    favoriteTeamPicker = SportsFavoritesCatalog.teams(for: firstLeague).first ?? ""
                }
                tempProviderKey = SportsProviderPreferences.normalizedProviderKey(tempProviderKey)
                if tempProviderEnabled && tempProviderKey == SportsProviderPreferences.allProviderKey {
                    tempProviderKey = sportsProviderKey == SportsProviderPreferences.allProviderKey
                        ? SportsProviderPreferences.defaultTemporaryProviderKey
                        : sportsProviderKey
                }
                await vm.refresh(providerKey: effectiveProviderKey, availabilityOnly: sportsAvailabilityOnly)
            }
            .onChange(of: sportsProviderKey) { newValue in
                let normalized = SportsProviderPreferences.normalizedProviderKey(newValue)
                if sportsProviderKey != normalized {
                    sportsProviderKey = normalized
                }
                if normalized == SportsProviderPreferences.allProviderKey {
                    sportsAvailabilityOnly = false
                }
                Task {
                    await vm.trackProviderFilter(providerKey: effectiveProviderKey, availabilityOnly: sportsAvailabilityOnly)
                    await vm.refresh(providerKey: effectiveProviderKey, availabilityOnly: sportsAvailabilityOnly)
                }
            }
            .onChange(of: ochoModeEnabled) { isEnabled in
                vm.isOchoMode = isEnabled
                vm.selectedLeagues = []
                vm.selectedTeam = "All Teams"
                if isEnabled {
                    if !OchoHeroCopy.rotatingTaglines.isEmpty {
                        ochoHeroTaglineIndex = Int.random(in: 0..<OchoHeroCopy.rotatingTaglines.count)
                    }
                } else {
                    ochoSurprisePick = nil
                }
                if isEnabled && sportsAvailabilityOnly {
                    sportsAvailabilityOnly = false
                }
                Task {
                    await vm.refresh(
                        providerKey: effectiveProviderKey,
                        availabilityOnly: sportsAvailabilityOnly
                    )
                }
            }
            .onChange(of: includeAltSports) { isEnabled in
                vm.includeAltSports = isEnabled
                Task {
                    await vm.refresh(
                        providerKey: effectiveProviderKey,
                        availabilityOnly: sportsAvailabilityOnly
                    )
                }
            }
            .onChange(of: sportsAvailabilityOnly) { _ in
                Task {
                    await vm.trackProviderFilter(providerKey: effectiveProviderKey, availabilityOnly: sportsAvailabilityOnly)
                    await vm.refresh(providerKey: effectiveProviderKey, availabilityOnly: sportsAvailabilityOnly)
                }
            }
            .onChange(of: tempProviderEnabled) { isEnabled in
                if isEnabled && tempProviderKey == SportsProviderPreferences.allProviderKey {
                    tempProviderKey = sportsProviderKey == SportsProviderPreferences.allProviderKey
                        ? SportsProviderPreferences.defaultTemporaryProviderKey
                        : sportsProviderKey
                }
                Task {
                    await vm.trackTemporaryProvider(enabled: isEnabled, providerKey: effectiveProviderKey)
                    await vm.trackProviderFilter(providerKey: effectiveProviderKey, availabilityOnly: sportsAvailabilityOnly)
                    await vm.refresh(providerKey: effectiveProviderKey, availabilityOnly: sportsAvailabilityOnly)
                }
            }
            .onChange(of: tempProviderKey) { newValue in
                let normalized = SportsProviderPreferences.normalizedProviderKey(newValue)
                if tempProviderKey != normalized {
                    tempProviderKey = normalized
                }
                guard tempProviderEnabled else { return }
                if normalized == SportsProviderPreferences.allProviderKey {
                    tempProviderKey = SportsProviderPreferences.defaultTemporaryProviderKey
                }
                Task {
                    await vm.trackProviderFilter(providerKey: effectiveProviderKey, availabilityOnly: sportsAvailabilityOnly)
                    await vm.refresh(providerKey: effectiveProviderKey, availabilityOnly: sportsAvailabilityOnly)
                }
            }
            .onChange(of: vm.favoriteLeagueList) { _ in
                let options = favoriteLeaguePickerOptions
                if options.isEmpty {
                    favoriteLeaguePicker = "NFL"
                    favoriteTeamPicker = ""
                    return
                }
                if !options.contains(favoriteLeaguePicker) {
                    favoriteLeaguePicker = options[0]
                }
                if !favoriteTeamPickerOptions.contains(favoriteTeamPicker) {
                    favoriteTeamPicker = favoriteTeamPickerOptions.first ?? ""
                }
            }
            .onChange(of: favoriteLeaguePicker) { newValue in
                let teams = SportsFavoritesCatalog.teams(for: newValue)
                if !teams.contains(favoriteTeamPicker) {
                    favoriteTeamPicker = teams.first ?? ""
                }
            }
        }
        .sheet(item: $selectedEvent) { item in
            SportsEventDetailSheet(item: item)
        }
        .sheet(isPresented: $showCustomizeSheet) {
            SportsCustomizeSheet(
                selectedLeagues: $vm.selectedLeagues,
                selectedTeam: $vm.selectedTeam,
                favoriteLeaguePicker: $favoriteLeaguePicker,
                favoriteTeamPicker: $favoriteTeamPicker,
                sportsProviderKey: $sportsProviderKey,
                sportsAvailabilityOnly: $sportsAvailabilityOnly,
                tempProviderEnabled: $tempProviderEnabled,
                tempProviderKey: $tempProviderKey,
                includeAltSports: $includeAltSports,
                selectedWindowHours: $vm.selectedWindowHours,
                isOchoMode: ochoModeEnabled,
                leagueFilters: vm.leagueFilters,
                teamFilters: vm.teamFilters,
                favoriteLeagueList: vm.favoriteLeagueList,
                favoriteTeamList: vm.favoriteTeamList,
                favoriteLeaguePickerOptions: favoriteLeaguePickerOptions,
                favoriteTeamPickerOptions: favoriteTeamPickerOptions,
                effectiveProviderKey: effectiveProviderKey,
                effectiveProviderLabel: effectiveProviderLabel,
                singleLeagueWindowLabel: singleLeagueWindowLabel,
                windowOptions: vm.windowOptions,
                isLeagueFavorite: vm.isLeagueFavorite,
                isTeamFavorite: vm.isTeamFavorite,
                onToggleLeagueFavorite: { league in
                    Task {
                        await vm.toggleLeagueFavorite(league)
                        await vm.refresh(
                            providerKey: effectiveProviderKey,
                            availabilityOnly: sportsAvailabilityOnly
                        )
                    }
                },
                onToggleTeamFavorite: { team in
                    Task {
                        await vm.toggleTeamFavorite(team)
                        await vm.refresh(
                            providerKey: effectiveProviderKey,
                            availabilityOnly: sportsAvailabilityOnly
                        )
                    }
                },
                onRemoveLeagueFavorite: { league in
                    Task {
                        await vm.removeLeagueFavorite(league)
                        await vm.refresh(
                            providerKey: effectiveProviderKey,
                            availabilityOnly: sportsAvailabilityOnly
                        )
                    }
                },
                onRemoveTeamFavorite: { team in
                    Task {
                        await vm.removeTeamFavorite(team)
                        await vm.refresh(
                            providerKey: effectiveProviderKey,
                            availabilityOnly: sportsAvailabilityOnly
                        )
                    }
                },
                onClearAllFavorites: {
                    Task {
                        await vm.clearAllFavorites()
                        await vm.refresh(
                            providerKey: effectiveProviderKey,
                            availabilityOnly: sportsAvailabilityOnly
                        )
                    }
                },
                onAddTeamFavorite: {
                    guard !favoriteTeamPicker.isEmpty else { return }
                    Task {
                        await vm.addTeamFavorite(favoriteTeamPicker)
                        await vm.refresh(
                            providerKey: effectiveProviderKey,
                            availabilityOnly: sportsAvailabilityOnly
                        )
                    }
                },
                onWindowChange: {
                    Task {
                        await vm.trackWindowChange()
                        await vm.refresh(
                            providerKey: effectiveProviderKey,
                            availabilityOnly: sportsAvailabilityOnly
                        )
                    }
                },
                onTry12h: {
                    guard vm.selectedWindowHours != 12 else { return }
                    vm.selectedWindowHours = 12
                    Task {
                        await vm.trackWindowChange()
                        await vm.refresh(
                            providerKey: effectiveProviderKey,
                            availabilityOnly: sportsAvailabilityOnly
                        )
                    }
                }
            )
        }
        .sheet(isPresented: $showSportsGuide) {
            NavigationStack {
                List {
                    Section("How Sports rankings work") {
                        Label("Live and provider-available games are prioritized first.", systemImage: "dot.radiowaves.left.and.right")
                        Label("Favorite leagues and teams get an additional boost.", systemImage: "star")
                        Label("Window size changes what leagues and games are visible.", systemImage: "clock")
                    }
                    Section("Provider behavior") {
                        Label("Set your home provider in Settings for better availability ranking.", systemImage: "house")
                        Label("Use Temporary Provider for away-from-home viewing without changing your default.", systemImage: "tv")
                        Label("Availability-only hides games not carried by your selected provider.", systemImage: "checkmark.circle")
                    }
                    Section("Filter tools") {
                        Label("Tap Customize to choose one or more leagues for Live and Starting Soon, plus team filter, TV provider, favorites, and time window.", systemImage: "slider.horizontal.3")
                        Label("Use team and league favorites to personalize Live Now and Starting Soon.", systemImage: "heart")
                        Label("Use Try 12h when one league dominates short windows.", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                    Section("The Ocho") {
                        Label(OchoCopy.curatedDisclaimer, systemImage: "info.circle")
                        Label("Bare knuckle boxing and triangle bareknuckle bouts in the Mighty Trygon.", systemImage: "flame")
                        Label("Slap fighting and MMA cards.", systemImage: "figure.boxing")
                        Label("American sumo wrestling and Australian rules football.", systemImage: "figure.wrestling")
                    }
                    Section("Card actions") {
                        Label("Star and heart buttons follow leagues and teams.", systemImage: "star")
                        Label("Availability icon shows if the game is on your selected provider.", systemImage: "checkmark")
                        Label("Info opens matchup details and Apple Sports companion link.", systemImage: "info.circle")
                    }
                }
                .navigationTitle("How Sports Works")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showSportsGuide = false
                        }
                    }
                }
            }
        }
    }

    private var effectiveProviderKey: String {
        let defaultProvider = SportsProviderPreferences.normalizedProviderKey(sportsProviderKey)
        let temporaryProvider = SportsProviderPreferences.normalizedProviderKey(tempProviderKey)
        if tempProviderEnabled && temporaryProvider != SportsProviderPreferences.allProviderKey {
            return temporaryProvider
        }
        return defaultProvider
    }

    private var effectiveProviderLabel: String {
        SportsProviderPreferences.label(for: effectiveProviderKey)
    }

    private func pickOchoSurprise() {
        let pool = vm.filteredItems.filter { !$0.isFinal }
        guard let pick = pool.randomElement() else { return }
        ochoSurprisePick = pick
        AppHaptics.lightImpact()
    }

    private func ochoScrollToFirstUpcoming(_ proxy: ScrollViewProxy) {
        let s = vm.ochoFeedSections
        withAnimation(.easeInOut(duration: 0.35)) {
            if !s.startingSoon.isEmpty {
                proxy.scrollTo("ocho-starting-soon", anchor: .top)
            } else if !s.tonight.isEmpty {
                proxy.scrollTo("ocho-tonight", anchor: .top)
            } else if !s.worthALook.isEmpty {
                proxy.scrollTo("ocho-worth", anchor: .top)
            }
        }
    }

    private var ochoSurpriseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    pickOchoSurprise()
                } label: {
                    Label("Surprise Me", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .tint(ochoAccentColor)
                .labelStyle(.titleAndIcon)
            }
            if let surprise = ochoSurprisePick {
                OchoSectionShell(
                    colorScheme: colorScheme,
                    sectionTitle: "SURPRISE PICK",
                    titleAccent: ochoAccentColor,
                    leadingAccessory: { EmptyView() }
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(surprise.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            Text(SportsLeagueFilterDisplay.title(forBackendLabel: surprise.league))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if !surprise.network.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Label(surprise.network, systemImage: "tv")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        HStack(spacing: 10) {
                            Button("Open details") {
                                selectedEvent = surprise
                                Task { await vm.trackCardOpen(surprise) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ochoAccentColor)
                            Button("Dismiss") {
                                ochoSurprisePick = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ochoSectionedFeed(scrollProxy: ScrollViewProxy) -> some View {
        let s = vm.ochoFeedSections
        ochoLiveNowSection(items: s.live, scrollProxy: scrollProxy)
        if !s.startingSoon.isEmpty {
            ochoGenericSection(
                id: "ocho-starting-soon",
                title: "STARTING SOON",
                subtitle: "In the next hour or two",
                titleAccent: Color(red: 0.92, green: 0.65, blue: 0.12),
                rows: s.startingSoon,
                rowSection: .startingSoon
            )
        }
        if !s.tonight.isEmpty {
            ochoGenericSection(
                id: "ocho-tonight",
                title: "TONIGHT",
                subtitle: "Later today",
                titleAccent: Color.primary.opacity(0.65),
                rows: s.tonight,
                rowSection: .tonight
            )
        }
        if !s.worthALook.isEmpty {
            ochoGenericSection(
                id: "ocho-worth",
                title: "WORTH A LOOK",
                subtitle: "Curated picks and other discoveries",
                titleAccent: ochoAccentColor,
                rows: s.worthALook,
                rowSection: .worthALook
            )
        }
    }

    private func ochoLiveNowSection(items: [SportsEventItem], scrollProxy: ScrollViewProxy) -> some View {
        OchoSectionShell(
            colorScheme: colorScheme,
            sectionTitle: "LIVE NOW",
            titleAccent: Color.red,
            leadingAccessory: {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel("Live")
            }
        ) {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if vm.ochoFeedStatus?.hasLiveAlt == false,
                       let msg = vm.ochoFeedStatus?.noLiveAltMessage,
                       !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(msg)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("Nothing live right now")
                        .font(.headline)
                    Text("But something's always coming up")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("View upcoming") {
                            ochoScrollToFirstUpcoming(scrollProxy)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.92, green: 0.65, blue: 0.12))
                        Button("Show all sports") {
                            exitOchoMode()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        SportsEventRow(
                            item: item,
                            emphasis: .live,
                            isOchoMode: true,
                            ochoSection: .live,
                            showProviderAvailability: effectiveProviderKey != SportsProviderPreferences.allProviderKey,
                            isFavoriteLeague: vm.isLeagueFavorite(item.league),
                            favoriteAwayTeam: vm.isTeamFavorite(item.awayTeam),
                            favoriteHomeTeam: vm.isTeamFavorite(item.homeTeam),
                            onToggleLeagueFavorite: {
                                Task {
                                    await vm.toggleLeagueFavorite(item.league)
                                    await vm.refresh(
                                        providerKey: effectiveProviderKey,
                                        availabilityOnly: sportsAvailabilityOnly
                                    )
                                }
                            },
                            onToggleAwayTeamFavorite: {
                                Task {
                                    await vm.toggleTeamFavorite(item.awayTeam)
                                    await vm.refresh(
                                        providerKey: effectiveProviderKey,
                                        availabilityOnly: sportsAvailabilityOnly
                                    )
                                }
                            },
                            onToggleHomeTeamFavorite: {
                                Task {
                                    await vm.toggleTeamFavorite(item.homeTeam)
                                    await vm.refresh(
                                        providerKey: effectiveProviderKey,
                                        availabilityOnly: sportsAvailabilityOnly
                                    )
                                }
                            },
                            onOpenDetails: {
                                selectedEvent = item
                                Task { await vm.trackCardOpen(item) }
                            }
                        )
                        if idx < items.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
        .id("ocho-live")
    }

    private func ochoGenericSection(
        id: String,
        title: String,
        subtitle: String,
        titleAccent: Color,
        rows: [SportsEventItem],
        rowSection: OchoEventSection
    ) -> some View {
        OchoSectionShell(
            colorScheme: colorScheme,
            sectionTitle: title,
            titleAccent: titleAccent,
            leadingAccessory: { EmptyView() }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, item in
                    SportsEventRow(
                        item: item,
                        emphasis: .soon,
                        isOchoMode: true,
                        ochoSection: rowSection,
                        showProviderAvailability: effectiveProviderKey != SportsProviderPreferences.allProviderKey,
                        isFavoriteLeague: vm.isLeagueFavorite(item.league),
                        favoriteAwayTeam: vm.isTeamFavorite(item.awayTeam),
                        favoriteHomeTeam: vm.isTeamFavorite(item.homeTeam),
                        onToggleLeagueFavorite: {
                            Task {
                                await vm.toggleLeagueFavorite(item.league)
                                await vm.refresh(
                                    providerKey: effectiveProviderKey,
                                    availabilityOnly: sportsAvailabilityOnly
                                )
                            }
                        },
                        onToggleAwayTeamFavorite: {
                            Task {
                                await vm.toggleTeamFavorite(item.awayTeam)
                                await vm.refresh(
                                    providerKey: effectiveProviderKey,
                                    availabilityOnly: sportsAvailabilityOnly
                                )
                            }
                        },
                        onToggleHomeTeamFavorite: {
                            Task {
                                await vm.toggleTeamFavorite(item.homeTeam)
                                await vm.refresh(
                                    providerKey: effectiveProviderKey,
                                    availabilityOnly: sportsAvailabilityOnly
                                )
                            }
                        },
                        onOpenDetails: {
                            selectedEvent = item
                            Task { await vm.trackCardOpen(item) }
                        }
                    )
                    if idx < rows.count - 1 {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
        .id(id)
    }

    private var sportsLiveNowCard: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Live Now")
                    .font(.headline)
                if vm.liveItems.isEmpty {
                    AppContentStateCard(
                        kind: .empty,
                        systemImage: "dot.radiowaves.left.and.right",
                        title: "No live games right now",
                        message: "We’ll surface live matchups here when they start. Adjust filters in Customize or pull to refresh.",
                        retryTitle: "Refresh",
                        onRetry: {
                            Task {
                                await vm.refresh(
                                    providerKey: effectiveProviderKey,
                                    availabilityOnly: sportsAvailabilityOnly
                                )
                            }
                        },
                        isRetryDisabled: vm.isLoading,
                        compact: true,
                        embedInBrandCard: false
                    )
                } else {
                    ForEach(vm.liveItems) { item in
                        SportsEventRow(
                            item: item,
                            emphasis: .live,
                            isOchoMode: ochoModeEnabled,
                            ochoSection: nil,
                            showProviderAvailability: effectiveProviderKey != SportsProviderPreferences.allProviderKey,
                            isFavoriteLeague: vm.isLeagueFavorite(item.league),
                            favoriteAwayTeam: vm.isTeamFavorite(item.awayTeam),
                            favoriteHomeTeam: vm.isTeamFavorite(item.homeTeam),
                            onToggleLeagueFavorite: {
                                Task {
                                    await vm.toggleLeagueFavorite(item.league)
                                    await vm.refresh(
                                        providerKey: effectiveProviderKey,
                                        availabilityOnly: sportsAvailabilityOnly
                                    )
                                }
                            },
                            onToggleAwayTeamFavorite: {
                                Task {
                                    await vm.toggleTeamFavorite(item.awayTeam)
                                    await vm.refresh(
                                        providerKey: effectiveProviderKey,
                                        availabilityOnly: sportsAvailabilityOnly
                                    )
                                }
                            },
                            onToggleHomeTeamFavorite: {
                                Task {
                                    await vm.toggleTeamFavorite(item.homeTeam)
                                    await vm.refresh(
                                        providerKey: effectiveProviderKey,
                                        availabilityOnly: sportsAvailabilityOnly
                                    )
                                }
                            },
                            onOpenDetails: {
                                selectedEvent = item
                                Task { await vm.trackCardOpen(item) }
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sportsStartingSoonCard: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Starting Soon")
                    .font(.headline)
                if vm.startingSoonItems.isEmpty {
                    AppContentStateCard(
                        kind: .empty,
                        systemImage: "clock",
                        title: "No upcoming games in this view",
                        message: "When something’s about to start in your time window, it’ll show up here.",
                        retryTitle: "Refresh",
                        onRetry: {
                            Task {
                                await vm.refresh(
                                    providerKey: effectiveProviderKey,
                                    availabilityOnly: sportsAvailabilityOnly
                                )
                            }
                        },
                        isRetryDisabled: vm.isLoading,
                        compact: true,
                        embedInBrandCard: false
                    )
                } else {
                    ForEach(vm.startingSoonItems) { item in
                        SportsEventRow(
                            item: item,
                            emphasis: .soon,
                            isOchoMode: ochoModeEnabled,
                            ochoSection: nil,
                            showProviderAvailability: effectiveProviderKey != SportsProviderPreferences.allProviderKey,
                            isFavoriteLeague: vm.isLeagueFavorite(item.league),
                            favoriteAwayTeam: vm.isTeamFavorite(item.awayTeam),
                            favoriteHomeTeam: vm.isTeamFavorite(item.homeTeam),
                            onToggleLeagueFavorite: {
                                Task {
                                    await vm.toggleLeagueFavorite(item.league)
                                    await vm.refresh(
                                        providerKey: effectiveProviderKey,
                                        availabilityOnly: sportsAvailabilityOnly
                                    )
                                }
                            },
                            onToggleAwayTeamFavorite: {
                                Task {
                                    await vm.toggleTeamFavorite(item.awayTeam)
                                    await vm.refresh(
                                        providerKey: effectiveProviderKey,
                                        availabilityOnly: sportsAvailabilityOnly
                                    )
                                }
                            },
                            onToggleHomeTeamFavorite: {
                                Task {
                                    await vm.toggleTeamFavorite(item.homeTeam)
                                    await vm.refresh(
                                        providerKey: effectiveProviderKey,
                                        availabilityOnly: sportsAvailabilityOnly
                                    )
                                }
                            },
                            onOpenDetails: {
                                selectedEvent = item
                                Task { await vm.trackCardOpen(item) }
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sportsHeroHeader: some View {
        if ochoModeEnabled {
            ochoHeroCard
        } else {
            AppBrandedHeader(
                sectionTitle: "Live Sports",
                sectionSubtitle: "Live now and starting in the next few hours"
            )
            .overlay(
                RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                    .stroke(Color.clear, lineWidth: 2)
            )
            .shadow(color: Color.clear, radius: 8, x: 0, y: 0)
        }
    }

    private var ochoHeroCard: some View {
        let tagIdx = min(max(ochoHeroTaglineIndex, 0), max(OchoHeroCopy.rotatingTaglines.count - 1, 0))
        let rotating = OchoHeroCopy.rotatingTaglines.isEmpty
            ? ""
            : OchoHeroCopy.rotatingTaglines[tagIdx]

        return ZStack {
            RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.03, green: 0.27, blue: 0.74),
                            Color(red: 0.06, green: 0.34, blue: 0.82),
                            Color(red: 0.16, green: 0.12, blue: 0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            OchoHairbandHeaderTexture()
                .clipShape(RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous))
                .allowsHitTesting(false)

            LinearGradient(
                colors: [Color.black.opacity(0.22), Color.black.opacity(0.05), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous))
            .allowsHitTesting(false)

            // Bottom fade so title block and Sasquatch read clearly on the art.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("BDN")
                        .font(.caption2.weight(.black))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .foregroundStyle(Color.white)
                        .clipShape(Capsule())
                    Text("Big Daves News")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, DeviceLayout.headerPadding)
                .padding(.top, 12)

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(OchoHeroCopy.mainTitle)
                            .font(DeviceLayout.isPad ? .largeTitle.weight(.heavy) : .title.weight(.heavy))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
                        Text(OchoHeroCopy.subtitle)
                            .font(DeviceLayout.isPad ? .title2.weight(.semibold) : .title3.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.94))
                        Text(OchoHeroCopy.supportingLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                        if !rotating.isEmpty {
                            Text(rotating)
                                .font(.caption.italic())
                            .foregroundStyle(Color.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image("SasquatchOcho")
                        .resizable()
                        .scaledToFill()
                        .frame(width: DeviceLayout.isPad ? 118 : 102, height: DeviceLayout.isPad ? 118 : 102)
                        .clipped()
                        .padding(3)
                        .background(Color.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.86), lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
                        .accessibilityLabel("The Ocho: Sasquatch mascot")
                }
                .padding(.horizontal, DeviceLayout.headerPadding)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DeviceLayout.isPad ? 148 : 132, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                .stroke(ochoAccentColor.opacity(0.92), lineWidth: 2)
        )
        .shadow(color: ochoAccentColor.opacity(0.2), radius: 8, x: 0, y: 0)
    }

    private var sportsSummaryStrip: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            LivePulseDot(color: ochoModeEnabled ? ochoAccentColor : AppTheme.liveRed)
                            Text("\(vm.liveItems.count) live")
                        }
                        .foregroundStyle(ochoModeEnabled ? ochoAccentColor : AppTheme.liveRed)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(ochoModeEnabled ? ochoAccentColor : AppTheme.soonYellow)
                                .frame(width: 8, height: 8)
                            Text("\(vm.startingSoonItems.count) starting soon")
                        }
                        .foregroundStyle(ochoModeEnabled ? ochoAccentColor : AppTheme.soonYellow)
                    }
                    .font(.caption.weight(.semibold))
                    if activeFilterCount > 0 {
                        Text(filterSummaryLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .accessibilityLabel("Active customizations: \(filterSummaryLine)")
                    } else {
                        Text("All leagues · \(vm.selectedWindowHours) hour window")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var filterSummaryLine: String {
        var parts: [String] = []
        if !vm.selectedLeagues.isEmpty {
            let summary = vm.selectedLeagueFilterSummary
            if !summary.isEmpty { parts.append(summary) }
        }
        if vm.selectedTeam != "All Teams" { parts.append(vm.selectedTeam) }
        if sportsAvailabilityOnly { parts.append("Available only") }
        if tempProviderEnabled { parts.append("Away provider") }
        if includeAltSports { parts.append("Alt sports") }
        if !vm.favoriteLeagueList.isEmpty { parts.append("\(vm.favoriteLeagueList.count) league saves") }
        if !vm.favoriteTeamList.isEmpty { parts.append("\(vm.favoriteTeamList.count) team saves") }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    private var ochoAccentColor: Color {
        if colorScheme == .dark {
            return Color(red: 0.89, green: 0.38, blue: 0.69)
        }
        return Color(red: 0.72, green: 0.20, blue: 0.55)
    }

    private var favoriteLeaguePickerOptions: [String] {
        let favorites = vm.favoriteLeagueList.map { SportsFavoritesCatalog.displayLeague(forNormalized: $0) }
        return favorites.sorted()
    }

    private var favoriteTeamPickerOptions: [String] {
        SportsFavoritesCatalog.teams(for: favoriteLeaguePicker)
    }

    private var activeFilterCount: Int {
        var count = 0
        if !vm.selectedLeagues.isEmpty { count += 1 }
        if vm.selectedTeam != "All Teams" { count += 1 }
        if !vm.favoriteLeagueList.isEmpty { count += 1 }
        if !vm.favoriteTeamList.isEmpty { count += 1 }
        if sportsAvailabilityOnly { count += 1 }
        if tempProviderEnabled { count += 1 }
        if includeAltSports { count += 1 }
        return count
    }

    private var singleLeagueWindowLabel: String? {
        guard vm.selectedLeagues.isEmpty, vm.selectedTeam == "All Teams" else { return nil }
        let leagues = Set(vm.displayItems.map { $0.league }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        guard leagues.count == 1, let only = leagues.first else { return nil }
        return only
    }

    // MARK: Ocho entry & active chrome

    private func enterOchoMode() {
        if !OchoHeroCopy.rotatingTaglines.isEmpty {
            ochoHeroTaglineIndex = Int.random(in: 0..<OchoHeroCopy.rotatingTaglines.count)
        }
        ochoSurprisePick = nil
        ochoModeEnabled = true
        AppHaptics.lightImpact()
        // `vm` sync + refresh run in `.onChange(of: ochoModeEnabled)`.
    }

    private func exitOchoMode() {
        ochoModeEnabled = false
        ochoSurprisePick = nil
        AppHaptics.selection()
        // `vm` sync + refresh run in `.onChange(of: ochoModeEnabled)`.
    }

    /// Prominent entry when standard Sports is showing; keeps default users one tap away from Ocho.
    private var ochoEntryInvitationCard: some View {
        Button(action: enterOchoMode) {
            HStack(alignment: .center, spacing: 14) {
                Image("SasquatchOcho")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipped()
                    .background(Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(ochoAccentColor.opacity(colorScheme == .dark ? 0.45 : 0.35), lineWidth: 1)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(OchoCopy.entryTitle)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(ochoAccentColor)
                    Text(OchoCopy.entrySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ochoAccentColor.opacity(0.85))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                    .stroke(ochoAccentColor.opacity(colorScheme == .dark ? 0.45 : 0.38), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(OchoCopy.entryTitle). \(OchoCopy.entrySubtitle)")
        .accessibilityHint(OchoCopy.entryAccessibilityHint)
    }

    /// Clear active state, exit, and curated disclaimer while Ocho is on.
    private var ochoActiveModeChrome: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "8.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ochoAccentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(OchoCopy.activeHeadline)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(OchoCopy.activeSubhead)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(OchoCopy.exitButtonTitle, action: exitOchoMode)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(ochoAccentColor)
                    .accessibilityHint(OchoCopy.exitAccessibilityHint)
            }

            Text(OchoCopy.curatedDisclaimer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(OchoCopy.curatedDisclaimer)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(colorScheme == .dark ? 0.55 : 0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                .stroke(ochoAccentColor.opacity(0.55), lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
    }

}

private struct OchoHairbandHeaderTexture: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.02, blue: 0.12).opacity(0.55),
                        Color(red: 0.20, green: 0.02, blue: 0.30).opacity(0.35),
                        Color(red: 0.02, green: 0.10, blue: 0.28).opacity(0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.2, blue: 0.62).opacity(0.30), Color.clear],
                    center: .topTrailing,
                    startRadius: 12,
                    endRadius: max(140, geo.size.width * 0.45)
                )
                RadialGradient(
                    colors: [Color(red: 0.32, green: 1.0, blue: 0.88).opacity(0.25), Color.clear],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: max(130, geo.size.width * 0.42)
                )
                ForEach(0..<16, id: \.self) { idx in
                    Rectangle()
                        .fill(idx.isMultiple(of: 2) ? Color.white.opacity(0.09) : Color.black.opacity(0.09))
                        .frame(width: 14, height: max(220, geo.size.height * 1.8))
                        .rotationEffect(.degrees(-30))
                        .offset(x: CGFloat(idx * 28 - 140), y: 0)
                }
                ForEach(0..<5, id: \.self) { idx in
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 140, height: 2)
                        .rotationEffect(.degrees(-24))
                        .offset(
                            x: CGFloat(idx * 70 - 120),
                            y: CGFloat(idx.isMultiple(of: 2) ? -8 : 14)
                        )
                }
            }
        }
    }
}

private struct OchoArenaBackground: View {
    var body: some View {
        ZStack {
            AppTheme.pageBackground
            RadialGradient(
                colors: [Color.black.opacity(0.08), Color.clear],
                center: .top,
                startRadius: 120,
                endRadius: 520
            )
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.05), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct OchoLeopardSpot: View {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotation: Angle

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.92))
                .frame(width: width, height: height)
                .rotationEffect(rotation)
            Ellipse()
                .fill(Color.white.opacity(0.95))
                .frame(width: width * 0.46, height: height * 0.44)
                .offset(x: width * 0.08, y: -height * 0.06)
                .rotationEffect(rotation)
        }
        .position(x: x, y: y)
    }
}

private struct OchoZebraBorder: View {
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let borderRect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                let borderPath = Path(
                    roundedRect: borderRect,
                    cornerRadius: cornerRadius,
                    style: .continuous
                )

                context.stroke(
                    borderPath,
                    with: .color(Color.black.opacity(0.95)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )

                for index in stride(from: -Int(size.height), through: Int(size.width) + Int(size.height), by: 14) {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: CGFloat(index), y: size.height + 6))
                    stripe.addLine(to: CGPoint(x: CGFloat(index) + size.height + 14, y: -6))
                    context.stroke(
                        stripe,
                        with: .color(Color.white.opacity(0.95)),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                    )
                }
            }
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(lineWidth: 4)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 4, x: 0, y: 2)
        }
        .allowsHitTesting(false)
    }
}

private struct SportsCustomizeSheet: View {
    @Binding var selectedLeagues: Set<String>
    @Binding var selectedTeam: String
    @Binding var favoriteLeaguePicker: String
    @Binding var favoriteTeamPicker: String
    @Binding var sportsProviderKey: String
    @Binding var sportsAvailabilityOnly: Bool
    @Binding var tempProviderEnabled: Bool
    @Binding var tempProviderKey: String
    @Binding var includeAltSports: Bool
    @Binding var selectedWindowHours: Int
    let isOchoMode: Bool
    let leagueFilters: [String]
    let teamFilters: [String]
    let favoriteLeagueList: [String]
    let favoriteTeamList: [String]
    let favoriteLeaguePickerOptions: [String]
    let favoriteTeamPickerOptions: [String]
    let effectiveProviderKey: String
    let effectiveProviderLabel: String
    let singleLeagueWindowLabel: String?
    let windowOptions: [Int]
    let isLeagueFavorite: (String) -> Bool
    let isTeamFavorite: (String) -> Bool
    let onToggleLeagueFavorite: (String) -> Void
    let onToggleTeamFavorite: (String) -> Void
    let onRemoveLeagueFavorite: (String) -> Void
    let onRemoveTeamFavorite: (String) -> Void
    let onClearAllFavorites: () -> Void
    let onAddTeamFavorite: () -> Void
    let onWindowChange: () -> Void
    let onTry12h: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTemporaryProviderSection = false

    private var ochoAccentColor: Color {
        Color(red: 0.72, green: 0.20, blue: 0.55)
    }

    private var windowChipSelectedColor: Color {
        if isOchoMode { return ochoAccentColor }
        return colorScheme == .dark ? Color.mint : Color.teal
    }

    private func normalizedFilterLeague(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Empty `selectedLeagues` means show all leagues.
    private func isLeagueIncludedInFilter(_ league: String) -> Bool {
        let norm = normalizedFilterLeague(league)
        if selectedLeagues.isEmpty { return true }
        return selectedLeagues.contains(norm)
    }

    private func setLeagueIncludedInFilter(_ league: String, included: Bool) {
        let norm = normalizedFilterLeague(league)
        let allNorms = Set(leagueFilters.filter { $0 != "All" }.map { normalizedFilterLeague($0) })
        var next = selectedLeagues
        if next.isEmpty {
            if !included {
                next = allNorms.subtracting([norm])
            }
        } else {
            if included {
                next.insert(norm)
            } else {
                next.remove(norm)
            }
            if next == allNorms {
                next = []
            }
        }
        selectedLeagues = next
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Adjust how games are listed. Stars and hearts on each game still work from the main screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if leagueFilters.filter({ $0 != "All" }).isEmpty {
                        Text("No leagues in your time window yet. Pull to refresh after games load.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if !selectedLeagues.isEmpty {
                            Button("Show all leagues") {
                                selectedLeagues = []
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        ForEach(leagueFilters.filter { $0 != "All" }, id: \.self) { league in
                            Toggle(
                                isOn: Binding(
                                    get: { isLeagueIncludedInFilter(league) },
                                    set: { setLeagueIncludedInFilter(league, included: $0) }
                                )
                            ) {
                                Text(SportsLeagueFilterDisplay.title(forBackendLabel: league))
                            }
                        }
                    }
                    Picker("Team", selection: $selectedTeam) {
                        ForEach(teamFilters, id: \.self) { team in
                            Text(team).tag(team)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Filter this list")
                } footer: {
                    Text("Turn off leagues you want to hide from Live and Starting Soon. Leave all on (or tap Show all leagues) to see every league in your time window.")
                        .font(.caption)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(windowOptions, id: \.self) { hours in
                                Button {
                                    selectedWindowHours = hours
                                    onWindowChange()
                                } label: {
                                    Label("\(hours)h", systemImage: hours == 2 ? "timer" : "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .frame(minHeight: 44)
                                        .background(
                                            selectedWindowHours == hours
                                                ? windowChipSelectedColor
                                                : Color(.secondarySystemFill)
                                        )
                                        .foregroundStyle(selectedWindowHours == hours ? Color.white : Color.primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    if let singleLeague = singleLeagueWindowLabel {
                        HStack(spacing: 8) {
                            Label("Only \(singleLeague) in next \(selectedWindowHours)h", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Try 12h", action: onTry12h)
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Time window")
                } footer: {
                    Text("Larger windows show more upcoming games.")
                        .font(.caption)
                }

                Section {
                    if sportsProviderKey == SportsProviderPreferences.allProviderKey && !tempProviderEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Home TV provider")
                                .font(.subheadline.weight(.semibold))
                            Text("Used to estimate which games you can watch.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Home Provider", selection: $sportsProviderKey) {
                                ForEach(
                                    SportsProviderPreferences.options.filter { $0.key != SportsProviderPreferences.allProviderKey },
                                    id: \.key
                                ) { option in
                                    Text(option.label).tag(option.key)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    if effectiveProviderKey != SportsProviderPreferences.allProviderKey {
                        HStack {
                            Label(effectiveProviderLabel, systemImage: "tv")
                                .font(.subheadline)
                            Spacer()
                            if tempProviderEnabled && tempProviderKey != SportsProviderPreferences.allProviderKey {
                                Text("Temporary")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                        Toggle("Show only games on my provider", isOn: $sportsAvailabilityOnly)
                            .font(.subheadline)
                    }
                    DisclosureGroup(isExpanded: $showTemporaryProviderSection) {
                        Toggle("Use temporary provider (away mode)", isOn: $tempProviderEnabled)
                        if tempProviderEnabled {
                            Picker("Temporary provider", selection: $tempProviderKey) {
                                ForEach(SportsProviderPreferences.options, id: \.key) { option in
                                    Text(option.label).tag(option.key)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        Text("Does not change your default in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("More provider options", systemImage: "tv")
                            .font(.subheadline.weight(.semibold))
                    }
                } header: {
                    Text("TV & availability")
                }

                Section {
                    Toggle(isOn: $includeAltSports) {
                        Label("Include alt sports in main feed", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Adds MMA and other alt feeds without turning on The Ocho look.")
                        .font(.caption)
                }

                if !favoriteLeaguePickerOptions.isEmpty {
                    Section {
                        HStack(spacing: 8) {
                            Picker("Favorite league", selection: $favoriteLeaguePicker) {
                                ForEach(favoriteLeaguePickerOptions, id: \.self) { league in
                                    Text(SportsLeagueFilterDisplay.title(forBackendLabel: league)).tag(league)
                                }
                            }
                            .pickerStyle(.menu)
                            Picker("Team", selection: $favoriteTeamPicker) {
                                ForEach(favoriteTeamPickerOptions, id: \.self) { team in
                                    Text(team).tag(team)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(favoriteTeamPickerOptions.isEmpty)
                            Button(action: onAddTeamFavorite) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add favorite team")
                        }
                    } header: {
                        Text("Quick-add a favorite team")
                    } footer: {
                        Text("Save leagues below first, or browse games and tap the star or heart.")
                            .font(.caption)
                    }
                } else {
                    Section {
                        Text("Add favorite leagues in the list below to unlock quick team picks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Saved favorites") {
                    if favoriteLeagueList.isEmpty && favoriteTeamList.isEmpty {
                        Text("No saved favorites yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if !favoriteLeagueList.isEmpty {
                            Text("Leagues")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(favoriteLeagueList, id: \.self) { league in
                                HStack {
                                    Label(
                                        SportsLeagueFilterDisplay.title(
                                            forBackendLabel: SportsFavoritesCatalog.displayLeague(forNormalized: league)
                                        ),
                                        systemImage: "star.fill"
                                    )
                                        .foregroundStyle(isOchoMode ? ochoAccentColor : .primary)
                                    Spacer()
                                    Button(role: .destructive) {
                                        onRemoveLeagueFavorite(league)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                }
                            }
                        }
                        if !favoriteTeamList.isEmpty {
                            Text("Teams")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(favoriteTeamList, id: \.self) { team in
                                HStack {
                                    Label(displayLabel(for: team), systemImage: "heart.fill")
                                        .foregroundStyle(isOchoMode ? ochoAccentColor : .primary)
                                    Spacer()
                                    Button(role: .destructive) {
                                        onRemoveTeamFavorite(team)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                }
                            }
                        }
                        Button(role: .destructive) {
                            onClearAllFavorites()
                        } label: {
                            Label("Clear all favorites", systemImage: "trash")
                        }
                    }
                }

                Section("Browse leagues") {
                    ForEach(leagueFilters.filter { $0 != "All" }, id: \.self) { league in
                        Button {
                            onToggleLeagueFavorite(league)
                        } label: {
                            HStack {
                                Text(SportsLeagueFilterDisplay.title(forBackendLabel: league))
                                Spacer()
                                Image(systemName: isLeagueFavorite(league) ? "star.fill" : "star")
                                    .foregroundStyle(isLeagueFavorite(league) ? (isOchoMode ? ochoAccentColor : Color.yellow) : .secondary)
                            }
                        }
                    }
                }

                Section("Browse teams") {
                    ForEach(teamFilters.filter { $0 != "All Teams" }, id: \.self) { team in
                        Button {
                            onToggleTeamFavorite(team)
                        } label: {
                            HStack {
                                Text(team)
                                Spacer()
                                Image(systemName: isTeamFavorite(team) ? "heart.fill" : "heart")
                                    .foregroundStyle(isTeamFavorite(team) ? (isOchoMode ? ochoAccentColor : Color.pink) : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func displayLabel(for raw: String) -> String {
        raw
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                if lower.count <= 3 { return lower.uppercased() }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}

/// Row styling buckets for Ocho sectioned feed (colors + microcopy).
private enum OchoEventSection {
    case live
    case startingSoon
    case tonight
    case worthALook
}

private struct OchoSectionShell<Leading: View, Content: View>: View {
    let colorScheme: ColorScheme
    let sectionTitle: String
    let titleAccent: Color
    @ViewBuilder let leadingAccessory: () -> Leading
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                leadingAccessory()
                Text(sectionTitle)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(titleAccent)
                    .tracking(0.5)
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.24 : 0.14), lineWidth: 1)
        )
    }
}

private struct SportsEventRow: View {
    enum Emphasis {
        case live
        case soon
    }

    let item: SportsEventItem
    let emphasis: Emphasis
    let isOchoMode: Bool
    let ochoSection: OchoEventSection?
    let showProviderAvailability: Bool
    let isFavoriteLeague: Bool
    let favoriteAwayTeam: Bool
    let favoriteHomeTeam: Bool
    let onToggleLeagueFavorite: () -> Void
    let onToggleAwayTeamFavorite: () -> Void
    let onToggleHomeTeamFavorite: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(SportsLeagueFilterDisplay.title(forBackendLabel: item.league))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(leagueAccentColor.opacity(0.2))
                    .foregroundStyle(leagueAccentColor)
                    .clipShape(Capsule())
                Button(action: onToggleLeagueFavorite) {
                    Image(systemName: isFavoriteLeague ? "star.fill" : "star")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFavoriteLeague ? (isOchoMode ? ochoBrandAccent : Color.yellow) : .secondary)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.plain)
                if isOchoMode, ochoSection == nil, let timing = Self.legacyOchoTimingBadgeText(item.timingLabel) {
                    Text(timing)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(ochoBrandAccent.opacity(0.18))
                        .foregroundStyle(ochoBrandAccent)
                        .clipShape(Capsule())
                }
                if isOchoMode, let section = ochoSection, let ribbon = Self.sectionRibbonText(section) {
                    Text(ribbon)
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Self.sectionRibbonBackground(section).opacity(0.22))
                        .foregroundStyle(Self.sectionRibbonForeground(section))
                        .clipShape(Capsule())
                }

                let statusText = statusLineText()
                if !statusText.isEmpty {
                    HStack(spacing: 5) {
                        if emphasis == .live {
                            LivePulseDot(color: isOchoMode ? ochoRowAccentColor : AppTheme.liveRed)
                        } else {
                            Circle()
                                .fill(isOchoMode ? ochoRowAccentColor : AppTheme.soonYellow)
                                .frame(width: 8, height: 8)
                        }
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }

            Text(item.title)
                .font(ochoSection != nil ? .body.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(2)

            HStack(spacing: 10) {
                Button(action: onToggleAwayTeamFavorite) {
                    Label(
                        item.awayTeam.isEmpty ? "Away" : item.awayTeam,
                        systemImage: favoriteAwayTeam ? "heart.fill" : "heart"
                    )
                    .lineLimit(1)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(favoriteAwayTeam ? (isOchoMode ? ochoBrandAccent : Color.pink) : Color.primary)
                }
                .buttonStyle(.plain)
                Text(item.awayScore.isEmpty ? "-" : item.awayScore)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text("@")
                    .foregroundStyle(.secondary)
                Button(action: onToggleHomeTeamFavorite) {
                    Label(
                        item.homeTeam.isEmpty ? "Home" : item.homeTeam,
                        systemImage: favoriteHomeTeam ? "heart.fill" : "heart"
                    )
                    .lineLimit(1)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(favoriteHomeTeam ? (isOchoMode ? ochoBrandAccent : Color.pink) : Color.primary)
                }
                .buttonStyle(.plain)
                Text(item.homeScore.isEmpty ? "-" : item.homeScore)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Spacer()
            }
            .font(.caption)

            HStack(spacing: 8) {
                if !item.network.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(item.network, systemImage: "tv")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let sourceLabel = ContentSourceMapping.sportsCardLabel(for: item.sourceType) {
                    ContentSourceChip(label: sourceLabel)
                }
                if showProviderAvailability {
                    let available = item.isAvailableOnProvider ?? false
                    ZStack {
                        Circle()
                            .fill(
                                isOchoMode
                                    ? (available ? ochoBrandAccent.opacity(0.92) : ochoBrandAccent.opacity(0.24))
                                    : (available ? Color.green.opacity(0.92) : Color.gray.opacity(0.24))
                            )
                        Image(systemName: available ? "checkmark" : "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(available ? Color.white : Color.secondary)
                    }
                    .frame(width: 30, height: 30)
                        .accessibilityLabel(available ? "Available on selected provider" : "Unavailable on selected provider")
                        .help(available ? "Available on selected provider" : "Unavailable on selected provider")
                }
                Button(action: onOpenDetails) {
                    Image(systemName: "info.circle")
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background((isOchoMode ? ochoBrandAccent : Color.blue).opacity(0.2))
                        .foregroundStyle(isOchoMode ? ochoBrandAccent : .blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open game details")
                .help("Open game details")
                Text(startDisplayText())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ochoSection == nil ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    private func startDisplayText() -> String {
        let formatted = formattedLocalTime(item.startTimeLocal)
        if formatted.isEmpty {
            return ""
        }
        if emphasis == .live {
            return "Started \(formatted)"
        }
        return formatted
    }

    private var leagueAccentColor: Color {
        if isOchoMode, let s = ochoSection {
            return Self.sectionLeagueAccent(s)
        }
        if isOchoMode { return ochoBrandAccent }
        return emphasis == .live ? .red : .blue
    }

    /// Purple / magenta brand accent for Ocho (buttons, favorites)—not used as the LIVE color.
    private var ochoBrandAccent: Color {
        Color(red: 0.72, green: 0.20, blue: 0.55)
    }

    private static func legacyOchoTimingBadgeText(_ raw: String?) -> String? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "live_now": return "Live Now"
        case "starting_soon": return "Starting Soon"
        case "tonight": return "Tonight"
        default: return nil
        }
    }

    private static func sectionRibbonText(_ section: OchoEventSection) -> String? {
        switch section {
        case .live: return "LIVE"
        case .startingSoon: return "STARTING SOON"
        case .tonight: return "TONIGHT"
        case .worthALook: return "WORTH A LOOK"
        }
    }

    private static func sectionLeagueAccent(_ section: OchoEventSection) -> Color {
        switch section {
        case .live: return .red
        case .startingSoon: return Color(red: 0.92, green: 0.65, blue: 0.12)
        case .tonight: return Color.primary.opacity(0.55)
        case .worthALook: return Color(red: 0.62, green: 0.28, blue: 0.62)
        }
    }

    private static func sectionRibbonBackground(_ section: OchoEventSection) -> Color {
        sectionLeagueAccent(section)
    }

    private static func sectionRibbonForeground(_ section: OchoEventSection) -> Color {
        switch section {
        case .tonight: return Color.primary.opacity(0.85)
        default: return sectionLeagueAccent(section)
        }
    }

    private func statusLineText() -> String {
        if let section = ochoSection {
            switch section {
            case .live:
                let local = startDisplayText()
                if !local.isEmpty { return "Happening now · \(local)" }
                return "Happening now"
            case .startingSoon:
                return startingSoonMicrocopy()
            case .tonight:
                let local = startDisplayText()
                if local.isEmpty { return relativeStartText(item.startsInMinutes) }
                return "Tonight · starts \(local)"
            case .worthALook:
                let trimmed = item.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
                return relativeStartText(item.startsInMinutes)
            }
        }
        if emphasis == .live {
            let local = startDisplayText()
            if !local.isEmpty {
                return "Live • \(local)"
            }
            let trimmed = item.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Live" : "Live • \(trimmed)"
        }
        let local = startDisplayText()
        if local.isEmpty {
            return relativeStartText(item.startsInMinutes)
        }
        return "Starts \(local) · \(relativeStartText(item.startsInMinutes))"
    }

    private func startingSoonMicrocopy() -> String {
        let m = item.startsInMinutes
        let local = startDisplayText()
        if m <= 1 {
            return local.isEmpty ? "Starting soon · right now" : "Starting soon · \(local)"
        }
        if m < 60 {
            return "Starting soon · in \(m)m"
        }
        let h = m / 60
        let r = m % 60
        if r == 0 { return "Starting soon · in \(h)h" }
        return "Starting soon · in \(h)h \(r)m"
    }

    private func formattedLocalTime(_ rawISO: String) -> String {
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        let parsed = isoWithFractional.date(from: rawISO) ?? isoPlain.date(from: rawISO)
        guard let date = parsed else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func relativeStartText(_ minutes: Int) -> String {
        if minutes <= 0 { return "Starting now" }
        if minutes < 60 { return "Starts in \(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "Starts in \(hours)h"
        }
        return "Starts in \(hours)h \(remainder)m"
    }

}

private struct LivePulseDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.28))
                .frame(width: 12, height: 12)
                .scaleEffect(pulse ? 1.3 : 0.9)
                .opacity(pulse ? 0.2 : 0.7)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct SportsEventDetailSheet: View {
    let item: SportsEventItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section("Matchup") {
                    Text(item.title)
                        .font(.headline)
                    HStack {
                        Text(item.awayTeam.isEmpty ? "Away" : item.awayTeam)
                        Spacer()
                        Text(item.awayScore.isEmpty ? "-" : item.awayScore)
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                    HStack {
                        Text(item.homeTeam.isEmpty ? "Home" : item.homeTeam)
                        Spacer()
                        Text(item.homeScore.isEmpty ? "-" : item.homeScore)
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                }
                Section("Status") {
                    Text(item.statusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Status unavailable" : item.statusText)
                    Text("Starts: \(formattedLocalStart(item.startTimeLocal))")
                }
                Section("Broadcast") {
                    if let networks = item.networks, !networks.isEmpty {
                        ForEach(networks, id: \.self) { network in
                            Text(network)
                        }
                    } else if !item.network.isEmpty {
                        Text(item.network)
                    } else {
                        Text("Network unavailable")
                    }
                }
                Section("Data source") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 10) {
                            if let chip = ContentSourceMapping.sportsCardLabel(for: item.sourceType) {
                                ContentSourceChip(label: chip)
                            }
                            Text(ContentSourceMapping.sportsDetailTitle(for: item.sourceType))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        Text(ContentSourceMapping.sportsDetailFootnote(for: item.sourceType))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("Companion") {
                    Button {
                        openAppleSportsCompanion()
                    } label: {
                        Label("Open in Apple Sports", systemImage: "sportscourt")
                    }
                }
                if let reason = item.rankingReason, !reason.isEmpty {
                    Section("Why ranked") {
                        Text(reason.replacingOccurrences(of: ",", with: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Game Details")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formattedLocalStart(_ rawISO: String) -> String {
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: rawISO) else { return rawISO }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func openAppleSportsCompanion() {
        let query = "\(item.awayTeam) \(item.homeTeam) \(item.league)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let searchURL = URL(string: "https://sports.apple.com/us/search?query=\(encoded)"), !encoded.isEmpty {
            openURL(searchURL)
            return
        }
        if let baseURL = URL(string: "https://sports.apple.com/") {
            openURL(baseURL)
        }
    }
}
