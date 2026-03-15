import SwiftUI

@MainActor
final class SportsViewModel: ObservableObject {
    @Published var items: [SportsEventItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedLeague = "All"
    @Published var selectedTeam = "All Teams"
    @Published var selectedWindowHours = 4
    @Published var favoriteLeagues: Set<String> = []
    @Published var favoriteTeams: Set<String> = []

    let windowOptions = [2, 4, 6, 12]
    private let deviceID = WatchDeviceIdentity.current

    var filteredItems: [SportsEventItem] {
        let leagueScoped: [SportsEventItem]
        if selectedLeague == "All" {
            leagueScoped = items
        } else {
            leagueScoped = items.filter { normalizedLeague($0.league) == normalizedLeague(selectedLeague) }
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
        let unique = Set(items.map { $0.league.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        result.append(contentsOf: unique.sorted())
        return result
    }

    var teamFilters: [String] {
        var result = ["All Teams"]
        var seen: Set<String> = []
        for item in items {
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

    func refresh(providerKey: String, availabilityOnly: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let backendProvider = providerKey == SportsProviderPreferences.allProviderKey ? "" : providerKey
            let fetched = try await APIClient.shared.fetchSportsNow(
                windowHours: selectedWindowHours,
                timezoneName: TimeZone.current.identifier,
                providerKey: backendProvider,
                availabilityOnly: availabilityOnly && !backendProvider.isEmpty,
                deviceID: deviceID
            )
            items = fetched
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
        await syncFavorites()
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
        await syncFavorites()
    }

    func removeLeagueFavorite(_ league: String) async {
        let normalized = normalizedLeague(league)
        guard !normalized.isEmpty else { return }
        guard favoriteLeagues.contains(normalized) else { return }
        favoriteLeagues.remove(normalized)
        AppHaptics.lightImpact()
        await trackFollowToggle(kind: "league", value: normalized, following: false)
        await syncFavorites()
    }

    func removeTeamFavorite(_ team: String) async {
        let normalized = normalizedTeam(team)
        guard !normalized.isEmpty else { return }
        guard favoriteTeams.contains(normalized) else { return }
        favoriteTeams.remove(normalized)
        AppHaptics.lightImpact()
        await trackFollowToggle(kind: "team", value: normalized, following: false)
        await syncFavorites()
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
        await syncFavorites()
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
    @State private var showSportsFilters = false
    @State private var showProviderOptions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                    AppBrandedHeader(
                        sectionTitle: "Live Sports",
                        sectionSubtitle: "Live now and starting in the next few hours"
                    )

                    BrandCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Label("\(vm.liveItems.count) live", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                                Label("\(vm.startingSoonItems.count) starting soon", systemImage: "clock")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            if sportsProviderKey == SportsProviderPreferences.allProviderKey && !tempProviderEnabled {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Set your home TV provider")
                                        .font(.caption.weight(.semibold))
                                    Text("Pick your default provider so Sports can prioritize what you can actually watch.")
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
                                .padding(.top, 2)
                            }
                            if effectiveProviderKey != SportsProviderPreferences.allProviderKey {
                                HStack(spacing: 8) {
                                    Label(
                                        effectiveProviderLabel,
                                        systemImage: "tv"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    if tempProviderEnabled && tempProviderKey != SportsProviderPreferences.allProviderKey {
                                        Text("Temporary")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.18))
                                            .foregroundStyle(.orange)
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    Button {
                                        sportsAvailabilityOnly.toggle()
                                    } label: {
                                        Label(
                                            sportsAvailabilityOnly ? "Showing Available" : "Show Available Only",
                                            systemImage: sportsAvailabilityOnly ? "checkmark.circle.fill" : "line.3.horizontal.decrease.circle"
                                        )
                                        .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            Divider()

                            DisclosureGroup(isExpanded: $showProviderOptions) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle("Use Temporary Provider (Away Mode)", isOn: $tempProviderEnabled)
                                        .font(.subheadline.weight(.semibold))
                                    if tempProviderEnabled {
                                        Picker("Temporary Provider", selection: $tempProviderKey) {
                                            ForEach(SportsProviderPreferences.options, id: \.key) { option in
                                                Text(option.label).tag(option.key)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }
                                    Text("When enabled, Sports uses this provider without changing your default provider in Settings.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 4)
                            } label: {
                                Label("Provider Options", systemImage: "tv")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text("Window")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(vm.windowOptions, id: \.self) { hours in
                                        Button {
                                            vm.selectedWindowHours = hours
                                            Task {
                                                await vm.trackWindowChange()
                                                await vm.refresh(
                                                    providerKey: effectiveProviderKey,
                                                    availabilityOnly: sportsAvailabilityOnly
                                                )
                                            }
                                        } label: {
                                            Label("\(hours)h", systemImage: hours == 2 ? "timer" : "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .frame(minHeight: 44)
                                                .background(
                                                    vm.selectedWindowHours == hours
                                                        ? selectedWindowChipColor
                                                        : Color(.secondarySystemFill)
                                                )
                                                .foregroundStyle(
                                                    vm.selectedWindowHours == hours ? Color.white : Color.primary
                                                )
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(hours) hour window")
                                    }
                                }
                            }
                            if let singleLeague = singleLeagueWindowLabel {
                                HStack(spacing: 8) {
                                    Label("Only \(singleLeague) in next \(vm.selectedWindowHours)h", systemImage: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Try 12h") {
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
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                                }
                            }

                            HStack {
                                Label("\(activeFilterCount) filters", systemImage: "line.3.horizontal.decrease.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Manage Filters") {
                                    showSportsFilters = true
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    if vm.isLoading && vm.items.isEmpty {
                        SkeletonCard()
                        SkeletonCard()
                    }

                    if let error = vm.errorMessage {
                        ErrorStateCard(
                            title: "Sports data issue",
                            message: error,
                            retryTitle: "Refresh Sports",
                            isRetryDisabled: vm.isLoading
                        ) {
                            Task {
                                await vm.refresh(
                                    providerKey: effectiveProviderKey,
                                    availabilityOnly: sportsAvailabilityOnly
                                )
                            }
                        }
                    }

                    BrandCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Live Now")
                                .font(.headline)
                            if vm.liveItems.isEmpty {
                                Text("No live games right now in this filter.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(vm.liveItems) { item in
                                    SportsEventRow(
                                        item: item,
                                        emphasis: .live,
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
                                Text("No games starting soon in this filter.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(vm.startingSoonItems) { item in
                                    SportsEventRow(
                                        item: item,
                                        emphasis: .soon,
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
            .background(AppTheme.pageBackground.ignoresSafeArea())
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
                        Task {
                            await vm.refresh(
                                providerKey: effectiveProviderKey,
                                availabilityOnly: sportsAvailabilityOnly
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .disabled(vm.isLoading)
                    .accessibilityLabel("Refresh sports")
                    Button {
                        showSportsFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Sports filters")
                    AppHelpButton()
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
        }
        .sheet(item: $selectedEvent) { item in
            SportsEventDetailSheet(item: item)
        }
        .sheet(isPresented: $showSportsFilters) {
            SportsFiltersSheet(
                selectedLeague: $vm.selectedLeague,
                selectedTeam: $vm.selectedTeam,
                leagueFilters: vm.leagueFilters,
                teamFilters: vm.teamFilters,
                favoriteLeagueList: vm.favoriteLeagueList,
                favoriteTeamList: vm.favoriteTeamList,
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
                }
            )
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

    private var selectedLeagueChipColor: Color {
        colorScheme == .dark ? .cyan : .blue
    }

    private var selectedWindowChipColor: Color {
        colorScheme == .dark ? .mint : .teal
    }

    private var selectedTeamChipColor: Color {
        colorScheme == .dark ? .orange.opacity(0.92) : .indigo
    }

    private var activeFilterCount: Int {
        var count = 0
        if vm.selectedLeague != "All" { count += 1 }
        if vm.selectedTeam != "All Teams" { count += 1 }
        if !vm.favoriteLeagueList.isEmpty { count += 1 }
        if !vm.favoriteTeamList.isEmpty { count += 1 }
        if sportsAvailabilityOnly { count += 1 }
        if tempProviderEnabled { count += 1 }
        return count
    }

    private var singleLeagueWindowLabel: String? {
        guard vm.selectedLeague == "All", vm.selectedTeam == "All Teams" else { return nil }
        let leagues = Set(vm.items.map { $0.league }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        guard leagues.count == 1, let only = leagues.first else { return nil }
        return only
    }

    private func iconName(for league: String) -> String {
        let key = league.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "all" { return "line.3.horizontal.decrease.circle" }
        if key.contains("nfl") { return "football.fill" }
        if key.contains("nba") { return "basketball.fill" }
        if key.contains("mlb") { return "baseball.fill" }
        if key.contains("nhl") { return "hockey.puck.fill" }
        if key.contains("mls") || key.contains("soccer") { return "soccerball" }
        return "sportscourt"
    }
}

private struct SportsFiltersSheet: View {
    @Binding var selectedLeague: String
    @Binding var selectedTeam: String
    let leagueFilters: [String]
    let teamFilters: [String]
    let favoriteLeagueList: [String]
    let favoriteTeamList: [String]
    let isLeagueFavorite: (String) -> Bool
    let isTeamFavorite: (String) -> Bool
    let onToggleLeagueFavorite: (String) -> Void
    let onToggleTeamFavorite: (String) -> Void
    let onRemoveLeagueFavorite: (String) -> Void
    let onRemoveTeamFavorite: (String) -> Void
    let onClearAllFavorites: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("League Filter") {
                    Picker("League", selection: $selectedLeague) {
                        ForEach(leagueFilters, id: \.self) { league in
                            Text(league).tag(league)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Team Filter") {
                    Picker("Team", selection: $selectedTeam) {
                        ForEach(teamFilters, id: \.self) { team in
                            Text(team).tag(team)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Saved Favorites") {
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
                                        .foregroundStyle(.primary)
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
                                        .foregroundStyle(.primary)
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
                Section("Browse Leagues (Tap to Add/Remove)") {
                    ForEach(leagueFilters.filter { $0 != "All" }, id: \.self) { league in
                        Button {
                            onToggleLeagueFavorite(league)
                        } label: {
                            HStack {
                                Text(league)
                                Spacer()
                                Image(systemName: isLeagueFavorite(league) ? "star.fill" : "star")
                                    .foregroundStyle(isLeagueFavorite(league) ? Color.yellow : .secondary)
                            }
                        }
                    }
                }
                Section("Browse Teams (Tap to Add/Remove)") {
                    ForEach(teamFilters.filter { $0 != "All Teams" }, id: \.self) { team in
                        Button {
                            onToggleTeamFavorite(team)
                        } label: {
                            HStack {
                                Text(team)
                                Spacer()
                                Image(systemName: isTeamFavorite(team) ? "heart.fill" : "heart")
                                    .foregroundStyle(isTeamFavorite(team) ? Color.pink : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sports Filters")
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
                    .background((emphasis == .live ? Color.red : Color.blue).opacity(0.15))
                    .foregroundStyle(emphasis == .live ? .red : .blue)
                    .clipShape(Capsule())
                Button(action: onToggleLeagueFavorite) {
                    Image(systemName: isFavoriteLeague ? "star.fill" : "star")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFavoriteLeague ? Color.yellow : .secondary)
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
                    .foregroundStyle(favoriteAwayTeam ? Color.pink : Color.primary)
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
                    .foregroundStyle(favoriteHomeTeam ? Color.pink : Color.primary)
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
                if showProviderAvailability {
                    let available = item.isAvailableOnProvider ?? false
                    ZStack {
                        Circle()
                            .fill(available ? Color.green.opacity(0.92) : Color.gray.opacity(0.24))
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
                        .background(Color.blue.opacity(0.14))
                        .foregroundStyle(.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open game details")
                .help("Open game details")
                Spacer()
                Text(startDisplayText())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    private func statusLineText() -> String {
        if emphasis == .live {
            let trimmed = item.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
            return "Live"
        }
        // Normalize pregame status to local device time instead of feed timezone strings (e.g., EDT).
        let local = startDisplayText()
        if local.isEmpty {
            return relativeStartText(item.startsInMinutes)
        }
        return "Starts \(local) • \(relativeStartText(item.startsInMinutes))"
    }

    private func formattedLocalTime(_ rawISO: String) -> String {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: rawISO) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        }
        return ""
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
