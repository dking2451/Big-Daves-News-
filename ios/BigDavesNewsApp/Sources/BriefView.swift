import SwiftUI

@MainActor
final class BriefViewModel: ObservableObject {
    @Published var headlines: [Claim] = []
    @Published var weather: WeatherSnapshot?
    @Published var watchPicks: [WatchShowItem] = []
    @Published var sportsTeamPicks: [SportsEventItem] = []
    @Published var savedArticles: [SavedArticleItem] = []
    @Published var savedShows: [WatchShowItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastOpenedText = "First open"
    @Published var streakCount = 0
    @Published var resumeTitle = ""
    @Published var resumeURL = ""
    @Published var resumeKind = ""

    let lastOpenedKey = "bdn-brief-last-opened-ios"
    private let watchDeviceID = WatchDeviceIdentity.current
    private let streakCountKey = "bdn-brief-streak-count-ios"
    private let streakDateKey = "bdn-brief-streak-date-ios"

    init() {
        refreshLastOpenedText()
        refreshStreak()
        refreshResumeState()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let zip = normalizedZipOrDefault(UserDefaults.standard.string(forKey: "bdn-weather-zip-ios") ?? "75201")

        async let factsResult: Result<[Claim], Error> = {
            do {
                return .success(try await APIClient.shared.fetchFacts())
            } catch {
                return .failure(error)
            }
        }()

        async let weatherResult: Result<WeatherSnapshot, Error> = {
            do {
                return .success(try await APIClient.shared.fetchWeather(zipCode: zip))
            } catch {
                return .failure(error)
            }
        }()

        async let watchResult: Result<[WatchShowItem], Error> = {
            do {
                return .success(
                    try await APIClient.shared.fetchWatchShows(
                        limit: 12,
                        minimumCount: 12,
                        deviceID: watchDeviceID,
                        hideSeen: true,
                        onlySaved: false
                    )
                )
            } catch {
                return .failure(error)
            }
        }()
        async let sportsResult: Result<[SportsEventItem], Error> = {
            do {
                let effectiveProvider = SportsProviderPreferences.backendEffectiveProviderKeyFromDefaults
                let availabilityOnly = UserDefaults.standard.bool(
                    forKey: SportsProviderPreferences.availabilityOnlyStorageKey
                ) && !effectiveProvider.isEmpty
                return .success(
                    try await APIClient.shared.fetchSportsNow(
                        windowHours: 16,
                        timezoneName: TimeZone.current.identifier,
                        providerKey: effectiveProvider,
                        availabilityOnly: availabilityOnly,
                        deviceID: watchDeviceID
                    )
                )
            } catch {
                return .failure(error)
            }
        }()
        async let savedArticlesResult: Result<[SavedArticleItem], Error> = {
            do {
                return .success(try await APIClient.shared.fetchSavedArticles(deviceID: watchDeviceID))
            } catch {
                return .failure(error)
            }
        }()
        async let savedShowsResult: Result<[WatchShowItem], Error> = {
            do {
                return .success(
                    try await APIClient.shared.fetchWatchShows(
                        limit: 30,
                        minimumCount: 10,
                        deviceID: watchDeviceID,
                        hideSeen: false,
                        onlySaved: true
                    )
                )
            } catch {
                return .failure(error)
            }
        }()

        var nextError: String?

        switch await factsResult {
        case .success(let items):
            headlines = Array(items.prefix(5))
        case .failure:
            headlines = []
            nextError = "Could not refresh one or more brief sections."
        }

        switch await weatherResult {
        case .success(let snapshot):
            weather = snapshot
        case .failure:
            weather = nil
            nextError = "Could not refresh one or more brief sections."
        }

        switch await watchResult {
        case .success(let items):
            watchPicks = Array(items.prefix(3))
        case .failure:
            watchPicks = []
            nextError = "Could not refresh one or more brief sections."
        }
        switch await sportsResult {
        case .success(let items):
            sportsTeamPicks = Array(
                items
                    .filter { ($0.favoriteTeamCount ?? 0) > 0 }
                    .prefix(4)
            )
        case .failure:
            sportsTeamPicks = []
        }
        switch await savedArticlesResult {
        case .success(let items):
            savedArticles = items
        case .failure:
            savedArticles = []
        }
        switch await savedShowsResult {
        case .success(let items):
            savedShows = items
        case .failure:
            savedShows = []
        }

        errorMessage = nextError
    }

    func markOpenedNow() {
        let now = Date()
        UserDefaults.standard.set(now, forKey: lastOpenedKey)
        refreshLastOpenedText()
        updateStreak(for: now)
    }

    func trackBriefOpened() async {
        await APIClient.shared.trackEvent(
            deviceID: watchDeviceID,
            eventName: "brief_open",
            eventProps: [
                "streak_count": String(streakCount)
            ]
        )
    }

    func refreshLastOpenedText() {
        guard let last = UserDefaults.standard.object(forKey: lastOpenedKey) as? Date else {
            lastOpenedText = "First open"
            return
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        lastOpenedText = formatter.localizedString(for: last, relativeTo: Date())
    }

    func refreshResumeState() {
        resumeKind = UserDefaults.standard.string(forKey: "bdn-last-content-kind-ios") ?? ""
        resumeTitle = UserDefaults.standard.string(forKey: "bdn-last-content-title-ios") ?? ""
        resumeURL = UserDefaults.standard.string(forKey: "bdn-last-content-url-ios") ?? ""
    }

    private func refreshStreak() {
        streakCount = UserDefaults.standard.integer(forKey: streakCountKey)
    }

    private func updateStreak(for date: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let lastDate = UserDefaults.standard.object(forKey: streakDateKey) as? Date
        let lastDay = lastDate.map { calendar.startOfDay(for: $0) }
        let currentCount = UserDefaults.standard.integer(forKey: streakCountKey)
        if let lastDay {
            if calendar.isDate(lastDay, inSameDayAs: today) {
                streakCount = max(1, currentCount)
                return
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               calendar.isDate(lastDay, inSameDayAs: yesterday)
            {
                streakCount = max(1, currentCount) + 1
            } else {
                streakCount = 1
            }
        } else {
            streakCount = 1
        }
        UserDefaults.standard.set(streakCount, forKey: streakCountKey)
        UserDefaults.standard.set(today, forKey: streakDateKey)
    }

    var isEveningWindow: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 17
    }

    var eveningWrapItems: [Claim] {
        if headlines.count <= 2 { return headlines }
        return Array(headlines.dropFirst(2).prefix(3))
    }

    func openSportsFromBrief() {
        AppNavigationState.shared.selectedTab = .sports
    }

    private func normalizedZipOrDefault(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count >= 5 {
            return String(digits.prefix(5))
        }
        return "75201"
    }
}

struct BriefView: View {
    @StateObject private var vm = BriefViewModel()
    @State private var selectedArticle: BriefArticleDestination?
    @State private var showSaved = false
    @State private var showWeather = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AppBrandedHeader(
                        sectionTitle: "Brief",
                        sectionSubtitle: "Your morning snapshot in under a minute"
                    )

                    BrandCard {
                        HStack(spacing: 8) {
                            Label("Last opened \(vm.lastOpenedText)", systemImage: "clock.arrow.circlepath")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if vm.streakCount > 0 {
                                Text("Streak \(vm.streakCount)d")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Text("Daily reminder in Settings")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !vm.resumeKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        BrandCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(vm.resumeKind == "show" ? "Continue in Watch" : "Continue Reading")
                                    .font(.headline)
                                Button {
                                    if vm.resumeKind == "show" {
                                        AppNavigationState.shared.selectedTab = .watch
                                        Task {
                                            await APIClient.shared.trackEvent(
                                                deviceID: WatchDeviceIdentity.current,
                                                eventName: "resume_open",
                                                eventProps: ["kind": vm.resumeKind]
                                            )
                                        }
                                    } else if let url = URL(string: vm.resumeURL) {
                                        selectedArticle = BriefArticleDestination(url: url)
                                        Task {
                                            await APIClient.shared.trackEvent(
                                                deviceID: WatchDeviceIdentity.current,
                                                eventName: "resume_open",
                                                eventProps: ["kind": vm.resumeKind]
                                            )
                                        }
                                    }
                                } label: {
                                    Text(vm.resumeTitle.isEmpty ? "Resume" : vm.resumeTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if vm.isLoading && vm.headlines.isEmpty && vm.weather == nil && vm.watchPicks.isEmpty {
                        SkeletonCard()
                        SkeletonCard()
                        SkeletonCard()
                    }

                    if let error = vm.errorMessage {
                        ErrorStateCard(
                            title: "Brief partially unavailable",
                            message: error,
                            retryTitle: "Refresh Brief",
                            isRetryDisabled: vm.isLoading
                        ) {
                            Task { await vm.refresh() }
                        }
                    }

                    if let weather = vm.weather {
                        BrandCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Weather")
                                    .font(.headline)
                                Text("\(weather.weatherIcon) \(weather.weatherText)")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(Int(weather.temperatureF.rounded()))°F • Wind \(Int(weather.windMPH.rounded())) mph")
                                    .font(.subheadline)
                                if let topAlert = weather.alerts.first {
                                    Text("Alert: \(topAlert.event) (\(topAlert.severity))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .lineLimit(2)
                                } else {
                                    Text("No active weather alerts.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    showWeather = true
                                } label: {
                                    Label("Open full weather", systemImage: "cloud.sun")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    if !vm.sportsTeamPicks.isEmpty {
                        BrandCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Your Teams Today")
                                        .font(.headline)
                                    Spacer()
                                    Button("Open Sports") {
                                        vm.openSportsFromBrief()
                                    }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                                }
                                ForEach(vm.sportsTeamPicks) { item in
                                    Button {
                                        vm.openSportsFromBrief()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(2)
                                                .foregroundStyle(.primary)
                                            Text(item.statusText.isEmpty ? "Game update available" : item.statusText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    BrandCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Top Headlines")
                                .font(.headline)
                            if vm.headlines.isEmpty {
                                Text("No headlines available right now.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(vm.headlines) { claim in
                                    briefHeadlineRow(for: claim)
                                }
                            }
                        }
                    }

                    BrandCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Watch Picks")
                                .font(.headline)
                            if vm.watchPicks.isEmpty {
                                Text("No watch picks available right now.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(vm.watchPicks) { show in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(show.title)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                        Text("\(show.primaryProvider ?? "Streaming") • Score \(Int(show.trendScore.rounded()))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                        }
                    }

                    if vm.isEveningWindow {
                        BrandCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Evening Wrap")
                                    .font(.headline)
                                if vm.eveningWrapItems.isEmpty {
                                    Text("No major updates since morning yet.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(vm.eveningWrapItems) { claim in
                                        briefHeadlineRow(for: claim)
                                    }
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
                await vm.refresh()
                vm.markOpenedNow()
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await vm.refresh()
                            vm.markOpenedNow()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .disabled(vm.isLoading)
                    .accessibilityLabel("Refresh brief")
                    Button {
                        showSaved = true
                    } label: {
                        Image(systemName: "bookmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Open saved")
                    AppHelpButton()
                    AppOverflowMenu()
                }
            }
        }
        .sheet(item: $selectedArticle) { destination in
            ArticleWebView(url: destination.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showSaved) {
            SavedQueueView(
                savedArticles: vm.savedArticles,
                savedShows: vm.savedShows
            )
        }
        .sheet(isPresented: $showWeather) {
            WeatherView()
        }
        .task {
            vm.markOpenedNow()
            vm.refreshResumeState()
            await vm.trackBriefOpened()
            await vm.refresh()
        }
    }

    @ViewBuilder
    private func briefHeadlineRow(for claim: Claim) -> some View {
        if let raw = claim.evidence.first?.articleURL, let url = URL(string: raw) {
            Button {
                selectedArticle = BriefArticleDestination(url: url)
                UserDefaults.standard.set("article", forKey: "bdn-last-content-kind-ios")
                UserDefaults.standard.set(compactHeadline(from: claim.text), forKey: "bdn-last-content-title-ios")
                UserDefaults.standard.set(raw, forKey: "bdn-last-content-url-ios")
                UserDefaults.standard.set(claim.evidence.first?.sourceName ?? "", forKey: "bdn-last-content-source-ios")
                UserDefaults.standard.set(Date(), forKey: "bdn-last-content-opened-ios")
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(compactHeadline(from: claim.text))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(claim.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(compactHeadline(from: claim.text))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(claim.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func compactHeadline(from raw: String) -> String {
        let flattened = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = flattened.split(separator: " ")
        if words.count > 14 {
            return words.prefix(14).joined(separator: " ") + "..."
        }
        return flattened
    }
}

private struct BriefArticleDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SavedQueueView: View {
    @Environment(\.dismiss) private var dismiss
    let savedArticles: [SavedArticleItem]
    let savedShows: [WatchShowItem]
    @State private var selectedSegment = 0

    var body: some View {
        NavigationStack {
            List {
                Picker("Saved Type", selection: $selectedSegment) {
                    Text("Articles").tag(0)
                    Text("Shows").tag(1)
                }
                .pickerStyle(.segmented)

                if selectedSegment == 0 {
                    if savedArticles.isEmpty {
                        Text("No saved articles yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(savedArticles) { item in
                            Link(destination: URL(string: item.url) ?? URL(string: "https://example.com")!) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                    Text(item.sourceName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    if savedShows.isEmpty {
                        Text("No saved shows yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(savedShows) { show in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(show.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(show.primaryProvider ?? "Streaming")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
