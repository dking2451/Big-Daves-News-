import SwiftUI
import Combine

private enum SportsFavoritesCatalog {
    static let leagueToTeams: [String: [String]] = [
        "NFL": ["Dallas Cowboys", "Philadelphia Eagles", "San Francisco 49ers", "Kansas City Chiefs", "Buffalo Bills", "Green Bay Packers"],
        "NBA": ["Los Angeles Lakers", "Boston Celtics", "Golden State Warriors", "Dallas Mavericks", "Miami Heat", "Milwaukee Bucks"],
        "WNBA": ["Las Vegas Aces", "New York Liberty", "Dallas Wings", "Seattle Storm", "Phoenix Mercury", "Chicago Sky"],
        "MLB": ["New York Yankees", "Boston Red Sox", "Los Angeles Dodgers", "Houston Astros", "Texas Rangers", "Atlanta Braves"],
        "NHL": ["Dallas Stars", "New York Rangers", "Boston Bruins", "Colorado Avalanche", "Vegas Golden Knights", "Toronto Maple Leafs"],
        "MLS": ["Inter Miami", "LA Galaxy", "Seattle Sounders", "FC Dallas", "Atlanta United", "LAFC"],
        "NCAAF": ["Alabama", "Georgia", "Texas", "Michigan", "Ohio State", "Oregon"],
        "NCAAB": ["Duke", "North Carolina", "Kansas", "Kentucky", "UConn", "Baylor"],
        "UFC": ["Lightweight", "Welterweight", "Middleweight", "Women's Strawweight", "Featherweight", "Heavyweight"],
        "PGA": ["Scottie Scheffler", "Rory McIlroy", "Xander Schauffele", "Brooks Koepka", "Jordan Spieth", "Collin Morikawa"],
        "ATP": ["Novak Djokovic", "Carlos Alcaraz", "Jannik Sinner", "Daniil Medvedev", "Alexander Zverev", "Taylor Fritz"],
        "WTA": ["Iga Swiatek", "Coco Gauff", "Aryna Sabalenka", "Elena Rybakina", "Jessica Pegula", "Ons Jabeur"]
    ]

    static var leagues: [String] {
        leagueToTeams.keys.sorted()
    }

    static func teams(for league: String) -> [String] {
        leagueToTeams[league] ?? []
    }

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func displayLeague(forNormalized normalized: String) -> String {
        if let match = leagues.first(where: { Self.normalized($0) == normalized }) {
            return match
        }
        return normalized
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                if lower.count <= 4 { return lower.uppercased() }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}

@MainActor
final class SportsViewModel: ObservableObject {
    @Published var items: [SportsEventItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isOchoMode = false
    @Published var includeAltSports = false
    @Published var selectedLeague = "All"
    @Published var selectedTeam = "All Teams"
    @Published var selectedWindowHours = 4
    @Published var favoriteLeagues: Set<String> = []
    @Published var favoriteTeams: Set<String> = []

    let windowOptions = [2, 4, 6, 12]
    private let deviceID = WatchDeviceIdentity.current

    var displayItems: [SportsEventItem] {
        if !isOchoMode {
            return items
        }
        return items.filter(isOchoEvent)
    }

    var filteredItems: [SportsEventItem] {
        let leagueScoped: [SportsEventItem]
        if selectedLeague == "All" {
            leagueScoped = displayItems
        } else {
            leagueScoped = displayItems.filter { normalizedLeague($0.league) == normalizedLeague(selectedLeague) }
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
        filteredItems.filter { $0.isLive }
    }

    var startingSoonItems: [SportsEventItem] {
        filteredItems
            .filter { !$0.isLive && !$0.isFinal }
            .sorted { $0.startsInMinutes < $1.startsInMinutes }
    }

    var leagueFilters: [String] {
        var result = ["All"]
        let unique = Set(displayItems.map { $0.league.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        result.append(contentsOf: unique.sorted())
        return result
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
            let fetched = try await APIClient.shared.fetchSportsNow(
                windowHours: selectedWindowHours,
                timezoneName: TimeZone.current.identifier,
                providerKey: backendProvider,
                availabilityOnly: effectiveAvailabilityOnly,
                deviceID: deviceID,
                includeOcho: shouldIncludeOcho
            )
            items = fetched
            await SportsAlertsManager.shared.ingestLatestSports(items: fetched)
            if !leagueFilters.contains(selectedLeague) {
                selectedLeague = "All"
            }
            if !teamFilters.contains(selectedTeam) {
                selectedTeam = "All Teams"
            }
            errorMessage = nil
            SportsLiveStatus.shared.apply(items: fetched)
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
        let league = normalizedLeague(item.league)
        let sport = normalizedLeague(item.sport)
        if league.contains("the ocho") || league.contains("ocho") {
            return true
        }
        if league.contains("ufc") || sport.contains("mma") || sport.contains("combat") {
            return true
        }
        if league.contains("australian rules") || league.contains("afl") {
            return true
        }
        if sport.contains("wrestling") {
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
    @State private var ochoTaglineIndex = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                    VStack(alignment: .leading, spacing: DeviceLayout.screenIntentToBrandedSpacing) {
                        ScreenIntentHeader(title: "Live Sports", subtitle: "What's live and what's next")
                        sportsHeroHeader
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
                .frame(maxWidth: DeviceLayout.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, DeviceLayout.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(
                Group {
                    if ochoModeEnabled {
                        OchoArenaBackground()
                            .ignoresSafeArea()
                    } else {
                        AppTheme.pageBackground.ignoresSafeArea()
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
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ochoModeEnabled ? ochoAccentColor : .primary)
                    }
                    .accessibilityLabel("Customize sports")
                    .accessibilityHint("Opens filters, TV provider, favorites, and time window")
                    Button {
                        if !ochoModeEnabled {
                            rotateOchoTagline()
                        }
                        ochoModeEnabled.toggle()
                    } label: {
                        Image(systemName: ochoModeEnabled ? "8.circle.fill" : "8.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ochoModeEnabled ? ochoAccentColor : .primary)
                    }
                    .accessibilityLabel(ochoModeEnabled ? "Disable The Ocho mode" : "Enable The Ocho mode")
                    Menu {
                        Button {
                            Task {
                                await vm.refresh(
                                    providerKey: effectiveProviderKey,
                                    availabilityOnly: sportsAvailabilityOnly
                                )
                            }
                        } label: {
                            Label("Refresh sports", systemImage: "arrow.clockwise")
                        }
                        Button {
                            showSportsGuide = true
                        } label: {
                            Label("How Sports works", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ochoModeEnabled ? ochoAccentColor : .primary)
                    }
                    .accessibilityLabel("Sports actions")
                    AppOverflowMenu()
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
                vm.selectedLeague = "All"
                vm.selectedTeam = "All Teams"
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
            .onReceive(vm.$items.dropFirst()) { _ in
                guard ochoModeEnabled else { return }
                rotateOchoTagline()
            }
        }
        .sheet(item: $selectedEvent) { item in
            SportsEventDetailSheet(item: item)
        }
        .sheet(isPresented: $showCustomizeSheet) {
            SportsCustomizeSheet(
                selectedLeague: $vm.selectedLeague,
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
                        Label("Tap Customize to set league and team filters, TV provider, favorites, and time window.", systemImage: "slider.horizontal.3")
                        Label("Use team and league favorites to personalize Live Now and Starting Soon.", systemImage: "heart")
                        Label("Use Try 12h when one league dominates short windows.", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                    Section("The Ocho targets") {
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

        if ochoModeEnabled {
            Text(currentOchoTagline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .padding(.horizontal, 4)
        }
    }

    private var ochoHeroCard: some View {
        ZStack {
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
                colors: [Color.black.opacity(0.36), Color.black.opacity(0.08), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("BDN")
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.22))
                            .foregroundStyle(Color.white)
                            .clipShape(Capsule())
                        Text("Big Daves News")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.95))
                    }
                    Text("Live Sports")
                        .font(DeviceLayout.isPad ? .largeTitle.weight(.bold) : .title.weight(.bold))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.28), radius: 2, x: 0, y: 1)
                    Text("THE OCHO channel: random, rowdy, and all-alt sports")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image("SasquatchOcho")
                    .resizable()
                    .scaledToFill()
                    .frame(width: DeviceLayout.isPad ? 108 : 98, height: DeviceLayout.isPad ? 108 : 98)
                    .clipped()
                    .padding(3)
                    .background(Color.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.86), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.28), radius: 4, x: 0, y: 2)
                    .accessibilityLabel("The Ocho mode enabled")
            }
            .padding(DeviceLayout.headerPadding)
        }
        .frame(maxWidth: .infinity, minHeight: DeviceLayout.isPad ? 124 : 112, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                .stroke(ochoAccentColor.opacity(0.92), lineWidth: 2)
        )
        .shadow(color: ochoAccentColor.opacity(0.2), radius: 8, x: 0, y: 0)
    }

    private var sportsSummaryStrip: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Label("\(vm.liveItems.count) live", systemImage: "dot.radiowaves.left.and.right")
                                .foregroundStyle(ochoModeEnabled ? ochoAccentColor : .red)
                            Label("\(vm.startingSoonItems.count) starting soon", systemImage: "clock")
                                .foregroundStyle(ochoModeEnabled ? ochoAccentColor : .secondary)
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
                    Spacer(minLength: 8)
                    Button {
                        showCustomizeSheet = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.body.weight(.semibold))
                            Text("Customize")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                        .frame(minWidth: 72)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Customize sports")
                    .accessibilityHint("Filters, TV provider, favorites, and time window")
                }
                if ochoModeEnabled {
                    Label("The Ocho is on", systemImage: "8.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ochoAccentColor)
                }
            }
        }
    }

    private var filterSummaryLine: String {
        var parts: [String] = []
        if vm.selectedLeague != "All" { parts.append(vm.selectedLeague) }
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

    private var ochoTaglines: [String] {
        [
            "Tonight on THE OCHO: sports your friends forgot existed.",
            "If it looks unusual, it probably belongs on THE OCHO.",
            "World-class competition, questionable life choices.",
            "Somewhere, somehow, a championship is happening right now."
        ]
    }

    private var currentOchoTagline: String {
        guard !ochoTaglines.isEmpty else { return "" }
        let safeIndex = max(0, min(ochoTaglineIndex, ochoTaglines.count - 1))
        return ochoTaglines[safeIndex]
    }

    private func rotateOchoTagline() {
        guard !ochoTaglines.isEmpty else { return }
        ochoTaglineIndex = (ochoTaglineIndex + 1) % ochoTaglines.count
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
        if vm.selectedLeague != "All" { count += 1 }
        if vm.selectedTeam != "All Teams" { count += 1 }
        if !vm.favoriteLeagueList.isEmpty { count += 1 }
        if !vm.favoriteTeamList.isEmpty { count += 1 }
        if sportsAvailabilityOnly { count += 1 }
        if tempProviderEnabled { count += 1 }
        if includeAltSports { count += 1 }
        return count
    }

    private var singleLeagueWindowLabel: String? {
        guard vm.selectedLeague == "All", vm.selectedTeam == "All Teams" else { return nil }
        let leagues = Set(vm.displayItems.map { $0.league }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        guard leagues.count == 1, let only = leagues.first else { return nil }
        return only
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
    @Binding var selectedLeague: String
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Adjust how games are listed. Stars and hearts on each game still work from the main screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("League", selection: $selectedLeague) {
                        ForEach(leagueFilters, id: \.self) { league in
                            Text(league).tag(league)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Team", selection: $selectedTeam) {
                        ForEach(teamFilters, id: \.self) { team in
                            Text(team).tag(team)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Filter this list")
                } footer: {
                    Text("Choose All to see every league in your time window.")
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
                                    Text(league).tag(league)
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
                                    Label(displayLabel(for: league), systemImage: "star.fill")
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
                                Text(league)
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

private struct SportsEventRow: View {
    enum Emphasis {
        case live
        case soon
    }

    let item: SportsEventItem
    let emphasis: Emphasis
    let isOchoMode: Bool
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
                Text(item.league)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(leagueAccentColor.opacity(0.2))
                    .foregroundStyle(leagueAccentColor)
                    .clipShape(Capsule())
                Button(action: onToggleLeagueFavorite) {
                    Image(systemName: isFavoriteLeague ? "star.fill" : "star")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFavoriteLeague ? (isOchoMode ? ochoRowAccentColor : Color.yellow) : .secondary)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.plain)

                let statusText = statusLineText()
                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            HStack(spacing: 10) {
                Button(action: onToggleAwayTeamFavorite) {
                    Label(
                        item.awayTeam.isEmpty ? "Away" : item.awayTeam,
                        systemImage: favoriteAwayTeam ? "heart.fill" : "heart"
                    )
                    .lineLimit(1)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(favoriteAwayTeam ? (isOchoMode ? ochoRowAccentColor : Color.pink) : Color.primary)
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
                    .foregroundStyle(favoriteHomeTeam ? (isOchoMode ? ochoRowAccentColor : Color.pink) : Color.primary)
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
                                    ? (available ? ochoRowAccentColor.opacity(0.92) : ochoRowAccentColor.opacity(0.24))
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
                        .background((isOchoMode ? ochoRowAccentColor : Color.blue).opacity(0.2))
                        .foregroundStyle(isOchoMode ? ochoRowAccentColor : .blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open game details")
                .help("Open game details")
                Text(startDisplayText())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
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
        if isOchoMode { return ochoRowAccentColor }
        return emphasis == .live ? .red : .blue
    }

    private var ochoRowAccentColor: Color {
        Color(red: 0.72, green: 0.20, blue: 0.55)
    }

    private func statusLineText() -> String {
        if emphasis == .live {
            // Normalize live status to local-device time instead of feed timezone labels (ET/EDT).
            let local = startDisplayText()
            if !local.isEmpty {
                return "Live • \(local)"
            }
            let trimmed = item.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Live" : "Live • \(trimmed)"
        }
        // Normalize pregame status to local device time instead of feed timezone strings (e.g., EDT).
        let local = startDisplayText()
        if local.isEmpty {
            return relativeStartText(item.startsInMinutes)
        }
        return "Starts \(local) • \(relativeStartText(item.startsInMinutes))"
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
