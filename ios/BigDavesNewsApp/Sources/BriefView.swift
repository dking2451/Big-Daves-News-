import SwiftUI

@MainActor
final class BriefViewModel: ObservableObject {
    @Published var headlines: [Claim] = []
    @Published var localNews: [LocalNewsItem] = []
    @Published var localNewsLocationLabel = ""
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

        async let localNewsResult: Result<LocalNewsResponse, Error> = {
            do {
                return .success(try await APIClient.shared.fetchLocalNews(zipCode: zip, limit: 3))
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
                let r = try await APIClient.shared.fetchWatchShows(
                    limit: 12,
                    minimumCount: 12,
                    deviceID: watchDeviceID,
                    hideSeen: true,
                    onlySaved: false
                )
                return .success(r.items)
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
                    ).items
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
                let r = try await APIClient.shared.fetchWatchShows(
                    limit: 30,
                    minimumCount: 10,
                    deviceID: watchDeviceID,
                    hideSeen: false,
                    onlySaved: true
                )
                return .success(r.items)
            } catch {
                return .failure(error)
            }
        }()

        var nextError: String?

        switch await factsResult {
        case .success(let items):
            headlines = BriefViewModel.diverseHeadlines(from: items, total: 5)
        case .failure:
            headlines = []
            nextError = "Could not refresh one or more brief sections."
        }

        switch await localNewsResult {
        case .success(let response):
            localNews = Array(response.items.filter { !$0.isPaywalled }.prefix(3))
            localNewsLocationLabel = response.locationLabel
        case .failure:
            if localNews.isEmpty {
                localNews = []
                localNewsLocationLabel = ""
            }
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
            watchPicks = Array(LocalUserPreferences.shared.applyWatchRanking(items).prefix(3))
        case .failure:
            watchPicks = []
            nextError = "Could not refresh one or more brief sections."
        }
        switch await sportsResult {
        case .success(let items):
            let favorited = items.filter { ($0.favoriteTeamCount ?? 0) > 0 }
            let pool = favorited.isEmpty ? items : favorited
            sportsTeamPicks = Array(LocalUserPreferences.shared.applyBriefSportsRanking(pool).prefix(4))
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

    /// Priority rank for a claim category in Brief.
    /// Lower = higher priority. Matches user's requested order:
    /// World → Politics/Government → Business → Health/Tech → Sports → everything else.
    private static func briefCategoryPriority(_ category: String) -> Int {
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.contains("world") || key.contains("global") || key.contains("international") { return 0 }
        if key.contains("politic") || key.contains("election") || key.contains("government") { return 1 }
        if key.contains("business") || key.contains("econom") || key.contains("financ") || key.contains("market") { return 2 }
        if key.contains("health") || key.contains("tech") || key.contains("science") || key.contains("climate") { return 3 }
        if key.contains("sport") { return 5 }
        return 4 // everything else (interesting) above sports
    }

    /// Selects up to `total` claims with category priority enforced.
    /// Claims are grouped by priority bucket (world first, sports last).
    /// Within each bucket the original API rank order is preserved.
    /// A second pass fills remaining slots while still capping sports at 1.
    static func diverseHeadlines(from items: [Claim], total: Int) -> [Claim] {
        // Sort into priority buckets, preserving order within each bucket.
        let sorted = items.sorted { briefCategoryPriority($0.category) < briefCategoryPriority($1.category) }

        var result: [Claim] = []
        var categoryCounts: [String: Int] = [:]

        // First pass: at most 1 per category, in priority order
        for item in sorted {
            guard result.count < total else { break }
            let cat = item.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if (categoryCounts[cat] ?? 0) < 1 {
                result.append(item)
                categoryCounts[cat, default: 0] += 1
            }
        }

        // Second pass: fill gaps — allow 2 per non-sports category
        if result.count < total {
            let includedIDs = Set(result.map(\.id))
            for item in sorted {
                guard result.count < total else { break }
                guard !includedIDs.contains(item.id) else { continue }
                let cat = item.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let isSports = cat.contains("sport")
                let cap = isSports ? 1 : 2
                if (categoryCounts[cat] ?? 0) < cap {
                    result.append(item)
                    categoryCounts[cat, default: 0] += 1
                }
            }
        }

        return result
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
                VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                    // MARK: Opening — intent & brand (attention peak)
                    VStack(alignment: .leading, spacing: DeviceLayout.screenIntentToBrandedSpacing) {
                        ScreenIntentHeader(
                            title: "Here’s what matters today",
                            subtitle: "Your daily briefing—weather, news, teams, and watch picks in one scroll."
                        )
                        AppBrandedHeader(
                            sectionTitle: "Brief",
                            sectionSubtitle: "",
                            showSectionHeading: false
                        )
                    }

                    // MARK: Habit context (lightweight, does not compete with briefing body)
                    briefHabitContextRow

                    if vm.isLoading && vm.headlines.isEmpty && vm.weather == nil && vm.watchPicks.isEmpty {
                        SkeletonCard()
                        SkeletonCard()
                        SkeletonCard()
                    }

                    if let error = vm.errorMessage {
                        AppContentStateCard(
                            kind: .error,
                            systemImage: "clock.badge.exclamationmark",
                            title: "Your brief is taking longer than expected",
                            message: "\(error)\n\nPull down to refresh, or try again.",
                            retryTitle: "Try again",
                            onRetry: { Task { await vm.refresh() } },
                            isRetryDisabled: vm.isLoading,
                            compact: false
                        )
                    }

                    // MARK: Daily briefing sections (grouped to stay within @ViewBuilder 10-statement limit)
                    Group {

                    // MARK: 1 — World headlines (top priority)
                    briefDailySection(
                        title: "Top headlines",
                        subtitle: “World news, politics, and more”,
                        accessibilityHeading: “Top headlines”
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            if vm.headlines.isEmpty {
                                AppContentStateCard(
                                    kind: .empty,
                                    systemImage: “newspaper.fill”,
                                    title: “No headlines in this snapshot”,
                                    message: “Other sections may still be updating. Pull down to refresh the full Brief.”,
                                    retryTitle: “Refresh Brief”,
                                    onRetry: { Task { await vm.refresh() } },
                                    isRetryDisabled: vm.isLoading,
                                    compact: true,
                                    embedInBrandCard: false
                                )
                            } else {
                                ForEach(vm.headlines) { claim in
                                    briefHeadlineRow(for: claim)
                                }
                            }
                        }
                    }

                    // MARK: 2 — Local news
                    if !vm.localNews.isEmpty {
                        briefDailySection(
                            title: vm.localNewsLocationLabel.isEmpty ? “Local news” : “Local • \(vm.localNewsLocationLabel)”,
                            subtitle: “Headlines near you”,
                            accessibilityHeading: “Local news”
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(vm.localNews) { item in
                                    if let url = URL(string: item.url) {
                                        Button {
                                            AppHaptics.selection()
                                            selectedArticle = BriefArticleDestination(url: url)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.title)
                                                    .font(.subheadline.weight(.semibold))
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                                    .foregroundStyle(.primary)
                                                Text(item.sourceName)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // MARK: 3 — Sports (personalized, still “today”)
                    briefDailySection(
                        title: "Your teams today",
                        subtitle: "Games tied to teams you follow",
                        accessibilityHeading: "Your teams today"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Spacer(minLength: 0)
                                Button("Open Sports") {
                                    AppHaptics.selection()
                                    vm.openSportsFromBrief()
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                            }
                            if vm.sportsTeamPicks.isEmpty {
                                AppContentStateCard(
                                    kind: .empty,
                                    systemImage: "sportscourt.fill",
                                    title: "No team games to highlight",
                                    message: "Follow leagues and teams in Sports → Customize, then check back here.",
                                    retryTitle: "Refresh Brief",
                                    onRetry: { Task { await vm.refresh() } },
                                    isRetryDisabled: vm.isLoading,
                                    compact: true,
                                    embedInBrandCard: false
                                )
                            } else {
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

                    // MARK: 4 — Weather (glanceable day context)
                    if let weather = vm.weather {
                        briefDailySection(
                            title: "Today’s weather",
                            subtitle: "Conditions where you are",
                            accessibilityHeading: "Today, weather"
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(weather.weatherIcon) \(weather.weatherText)")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(Int(weather.temperatureF.rounded()))°F • Wind \(Int(weather.windMPH.rounded())) mph")
                                    .font(.subheadline)
                                if let topAlert = weather.alerts.first {
                                    Text("Alert: \(topAlert.event) (\(topAlert.severity))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .lineLimit(3)
                                } else {
                                    Text("No active weather alerts.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    AppHaptics.selection()
                                    showWeather = true
                                } label: {
                                    Label("Open full weather", systemImage: "cloud.sun")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    // MARK: 5 — Watch (lighter, discovery)
                    briefDailySection(
                        title: "Watch picks",
                        subtitle: "What to stream next",
                        accessibilityHeading: "Watch picks"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            if vm.watchPicks.isEmpty {
                                AppContentStateCard(
                                    kind: .empty,
                                    systemImage: "play.tv.fill",
                                    title: "Nothing to recommend yet",
                                    message: "Open the Watch tab and react to a few shows — we’ll surface better picks here over time.",
                                    retryTitle: "Refresh Brief",
                                    onRetry: { Task { await vm.refresh() } },
                                    isRetryDisabled: vm.isLoading,
                                    compact: true,
                                    embedInBrandCard: false
                                )
                            } else {
                                ForEach(vm.watchPicks) { show in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(show.title)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.85)
                                        Text("\(show.primaryProvider ?? "Streaming") • Trend \(Int(show.trendScore.rounded()))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                        }
                    }

                    // MARK: 6 — Evening (only late day; follow-up to morning read)
                    if vm.isEveningWindow {
                        briefDailySection(
                            title: "Evening wrap",
                            subtitle: "Follow-ups from your briefing",
                            accessibilityHeading: "Evening wrap"
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                if vm.eveningWrapItems.isEmpty {
                                    AppContentStateCard(
                                        kind: .empty,
                                        systemImage: "moon.stars.fill",
                                        title: "Quiet evening so far",
                                        message: "No big follow-ups since your morning read. Check Headlines or pull to refresh.",
                                        retryTitle: "Refresh Brief",
                                        onRetry: { Task { await vm.refresh() } },
                                        isRetryDisabled: vm.isLoading,
                                        compact: true,
                                        embedInBrandCard: false
                                    )
                                } else {
                                    ForEach(vm.eveningWrapItems) { claim in
                                        briefHeadlineRow(for: claim)
                                    }
                                }
                            }
                        }
                    }

                    } // end Group (daily sections)

                    // MARK: Secondary — library & resume (below daily briefing)
                    briefLibraryGroup
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
                ToolbarItem(placement: .topBarTrailing) {
                    AppOverflowMenu()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await vm.refresh()
                            vm.markOpenedNow()
                        }
                    } label: {
                        AppToolbarIcon(systemName: "arrow.triangle.2.circlepath", role: .refresh)
                    }
                    .disabled(vm.isLoading)
                    .accessibilityLabel("Refresh brief")
                    Button {
                        showSaved = true
                    } label: {
                        AppToolbarIcon(systemName: "bookmark.circle", role: .neutral)
                    }
                    .accessibilityLabel("Open saved")
                    AppHelpButton()
                }
            }
        }
        .sheet(item: $selectedArticle) { destination in
            ArticleWebView(url: destination.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showSaved) {
            SavedHubView()
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

    // MARK: - Section hierarchy (daily briefing vs library)

    /// Lightweight habit line—does not compete with the briefing sections below.
    private var briefHabitContextRow: some View {
        BrandCard {
            HStack(alignment: .center, spacing: 10) {
                Label("Last opened \(vm.lastOpenedText)", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if vm.streakCount > 0 {
                    Text("Streak \(vm.streakCount)d")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.streakGradient)
                        .foregroundStyle(Color.white)
                        .clipShape(Capsule())
                }
                Spacer(minLength: 8)
                Text("Notifications in Settings")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// Standard section: title + subtitle (Dynamic Type friendly), then `BrandCard` body.
    @ViewBuilder
    private func briefDailySection<Content: View>(
        title: String,
        subtitle: String,
        accessibilityHeading: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.title2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle)
                    .font(AppTypography.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("\(accessibilityHeading). \(subtitle)")

            BrandCard {
                content()
            }
        }
    }

    /// Resume + saved—visually and structurally after the daily briefing.
    private var briefLibraryGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Library")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if !vm.resumeKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Continue")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    BrandCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(vm.resumeKind == "show" ? "Continue in Watch" : "Continue reading")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            Button {
                                AppHaptics.lightImpact()
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
                                    .font(.body.weight(.semibold))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Button {
                showSaved = true
            } label: {
                HStack(alignment: .center) {
                    Label("Saved articles & shows", systemImage: "books.vertical")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your saved queue")
        }
        .padding(.top, 6)
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

