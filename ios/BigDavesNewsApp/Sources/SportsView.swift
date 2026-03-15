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

    let windowOptions = [2, 4, 6]
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
        await trackFollowToggle(kind: "team", value: normalized, following: !currentlyFavorite)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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

                            Toggle("Use Temporary Provider (Away Mode)", isOn: $tempProviderEnabled)
                                .font(.subheadline.weight(.semibold))

                            if tempProviderEnabled {
                                Picker("Temporary Provider", selection: $tempProviderKey) {
                                    ForEach(SportsProviderPreferences.options, id: \.key) { option in
                                        Text(option.label).tag(option.key)
                                    }
                                }
                                .pickerStyle(.menu)
                                Text("When enabled, Sports uses this provider without changing your default provider in Settings.")
                                    .font(.caption)
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
                        }
                    }

                    BrandCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("League")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(vm.leagueFilters, id: \.self) { league in
                                        Button {
                                            vm.selectedLeague = league
                                        } label: {
                                            Label(league, systemImage: iconName(for: league))
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .frame(minHeight: 44)
                                                .background(
                                                    vm.selectedLeague == league
                                                        ? selectedLeagueChipColor
                                                        : Color(.secondarySystemFill)
                                                )
                                                .foregroundStyle(
                                                    vm.selectedLeague == league ? Color.white : Color.primary
                                                )
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(league)
                                    }
                                }
                            }

                            Divider()

                            Text("Favorite Leagues")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(vm.leagueFilters.filter { $0 != "All" }, id: \.self) { league in
                                        Button {
                                            Task {
                                                await vm.toggleLeagueFavorite(league)
                                                await vm.refresh(
                                                    providerKey: effectiveProviderKey,
                                                    availabilityOnly: sportsAvailabilityOnly
                                                )
                                            }
                                        } label: {
                                            Label(
                                                league,
                                                systemImage: vm.isLeagueFavorite(league) ? "star.fill" : "star"
                                            )
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .frame(minHeight: 44)
                                            .background(
                                                vm.isLeagueFavorite(league)
                                                    ? Color.yellow.opacity(0.22)
                                                    : Color(.secondarySystemFill)
                                            )
                                            .foregroundStyle(
                                                vm.isLeagueFavorite(league) ? Color.yellow : Color.primary
                                            )
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            Text("Team Filter")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(vm.teamFilters, id: \.self) { team in
                                        Button {
                                            vm.selectedTeam = team
                                        } label: {
                                            Text(team)
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .frame(minHeight: 44)
                                                .background(
                                                    vm.selectedTeam == team
                                                        ? selectedTeamChipColor
                                                        : Color(.secondarySystemFill)
                                                )
                                                .foregroundStyle(
                                                    vm.selectedTeam == team ? Color.white : Color.primary
                                                )
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            Text("Favorite Teams")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(vm.teamFilters.filter { $0 != "All Teams" }, id: \.self) { team in
                                        Button {
                                            Task {
                                                await vm.toggleTeamFavorite(team)
                                                await vm.refresh(
                                                    providerKey: effectiveProviderKey,
                                                    availabilityOnly: sportsAvailabilityOnly
                                                )
                                            }
                                        } label: {
                                            Label(
                                                team,
                                                systemImage: vm.isTeamFavorite(team) ? "heart.fill" : "heart"
                                            )
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .frame(minHeight: 44)
                                            .background(
                                                vm.isTeamFavorite(team)
                                                    ? Color.pink.opacity(0.22)
                                                    : Color(.secondarySystemFill)
                                            )
                                            .foregroundStyle(
                                                vm.isTeamFavorite(team) ? Color.pink : Color.primary
                                            )
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
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
                    Text(available ? "Available" : "Unavailable")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((available ? Color.green : Color.gray).opacity(0.18))
                        .foregroundStyle(available ? Color.green : .secondary)
                        .clipShape(Capsule())
                }
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
