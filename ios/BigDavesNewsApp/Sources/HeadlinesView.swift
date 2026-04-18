import SwiftUI

@MainActor
final class HeadlinesViewModel: ObservableObject {
    /// “All” stays a tight digest; single-category filters show more rows when the API provides them.
    private enum HeadlinesDisplayLimits {
        static let allCategory = 10
        static let singleFilterMax = 30
    }

    @Published var claims: [Claim] = []
    @Published var localNews: [LocalNewsItem] = []
    @Published var localNewsLocationLabel = ""
    @Published var localNewsErrorMessage: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedCategory = "All"
    @Published private(set) var readArticleIDs: Set<String> = []
    @Published private(set) var savedArticleIDs: Set<String> = []

    private let readArticlesKey = "bdn-read-article-ids-ios"
    private let savedArticlesKey = "bdn-saved-article-ids-ios"
    private let deviceID = WatchDeviceIdentity.current

    init() {
        loadReadArticles()
        loadSavedArticleIDs()
    }

    var categories: [String] {
        let unique = Array(Set(claims.map(\.category)))
        let filtered = unique.filter { normalizedTopicPart($0) != "all" && normalizedTopicPart($0) != "local news" }
        let ordered = filtered.sorted { lhs, rhs in
            let lRank = categoryRank(lhs)
            let rRank = categoryRank(rhs)
            if lRank == rRank {
                return lhs < rhs
            }
            return lRank < rRank
        }
        return ["All", "Local News"] + ordered
    }

    var filteredClaims: [Claim] {
        if selectedCategory == "Local News" {
            return []
        }
        if selectedCategory == "All" {
            return Array(
                distinctClaims(from: claims, enforceTopicUniqueness: true)
                    .prefix(HeadlinesDisplayLimits.allCategory)
            )
        }
        let scoped = claims.filter { $0.category == selectedCategory }
        let deep = distinctClaims(from: scoped, enforceTopicUniqueness: false)
        return Array(deep.prefix(HeadlinesDisplayLimits.singleFilterMax))
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        localNewsErrorMessage = nil
        let localZip = normalizedZipOrDefault(UserDefaults.standard.string(forKey: "bdn-weather-zip-ios") ?? "75201")
        async let factsResult: Result<[Claim], Error> = {
            do {
                return .success(try await APIClient.shared.fetchFacts())
            } catch {
                return .failure(error)
            }
        }()
        async let localResult: Result<LocalNewsResponse, Error> = {
            do {
                return .success(try await APIClient.shared.fetchLocalNews(zipCode: localZip, limit: 12))
            } catch {
                return .failure(error)
            }
        }()

        switch await factsResult {
        case .success(let facts):
            if facts.isEmpty, !claims.isEmpty {
                // Keep last successful set when a refresh returns empty.
                errorMessage = nil
            } else {
                claims = facts
            }
        case .failure(let error):
            if claims.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                // Preserve existing headlines and avoid disruptive full error card.
                errorMessage = nil
            }
        }

        switch await localResult {
        case .success(let localResponse):
            localNews = localResponse.items
            localNewsLocationLabel = localResponse.locationLabel
            localNewsErrorMessage = nil
        case .failure:
            if localNews.isEmpty {
                localNewsLocationLabel = ""
                localNewsErrorMessage = "Local news is temporarily unavailable."
            } else {
                localNewsErrorMessage = "Could not refresh local headlines. Showing latest available."
            }
        }
        isLoading = false
    }

    func isArticleRead(_ articleID: String) -> Bool {
        readArticleIDs.contains(articleID)
    }

    func markArticleRead(_ articleID: String) {
        let key = articleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if readArticleIDs.insert(key).inserted {
            saveReadArticles()
        }
    }

    func isArticleSaved(_ articleID: String) -> Bool {
        savedArticleIDs.contains(articleIDKey(from: articleID))
    }

    func refreshSavedArticles() async {
        do {
            let items = try await APIClient.shared.fetchSavedArticles(deviceID: deviceID)
            let ids = Set(items.map { articleIDKey(from: $0.articleID) })
            savedArticleIDs = ids
            saveSavedArticleIDs()
        } catch {
            // Keep local state if backend is unavailable.
        }
    }

    func toggleSavedArticle(
        articleID: String,
        title: String,
        url: String,
        sourceName: String,
        summary: String,
        imageURL: String
    ) async {
        let key = articleIDKey(from: articleID)
        let shouldSave = !savedArticleIDs.contains(key)
        do {
            try await APIClient.shared.setSavedArticle(
                deviceID: deviceID,
                articleID: key,
                title: title,
                url: url,
                sourceName: sourceName,
                summary: summary,
                imageURL: imageURL,
                saved: shouldSave
            )
            if shouldSave {
                savedArticleIDs.insert(key)
            } else {
                savedArticleIDs.remove(key)
            }
            saveSavedArticleIDs()
            await APIClient.shared.trackEvent(
                deviceID: deviceID,
                eventName: "article_save",
                eventProps: [
                    "article_id": key,
                    "saved": shouldSave ? "true" : "false",
                    "source": sourceName
                ]
            )
        } catch {
            // Ignore failures to avoid disrupting reading flow.
        }
    }

    private func loadReadArticles() {
        let stored = UserDefaults.standard.array(forKey: readArticlesKey) as? [String] ?? []
        readArticleIDs = Set(stored.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private func saveReadArticles() {
        UserDefaults.standard.set(Array(readArticleIDs).sorted(), forKey: readArticlesKey)
    }

    private func loadSavedArticleIDs() {
        let stored = UserDefaults.standard.array(forKey: savedArticlesKey) as? [String] ?? []
        savedArticleIDs = Set(stored.map(articleIDKey(from:)).filter { !$0.isEmpty })
    }

    private func saveSavedArticleIDs() {
        UserDefaults.standard.set(Array(savedArticleIDs).sorted(), forKey: savedArticlesKey)
    }

    private func articleIDKey(from raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func distinctClaims(from items: [Claim], enforceTopicUniqueness: Bool) -> [Claim] {
        var seenTopics: Set<String> = []
        var seenTexts: Set<String> = []
        var seenSourceImage: Set<String> = []
        var seenSourceArticle: Set<String> = []
        var result: [Claim] = []

        for claim in items {
            let topicKey = "\(normalizedTopicPart(claim.category))|\(normalizedTopicPart(claim.subtopic))"
            let textKey = normalizedText(claim.text)
            let source = normalizedTopicPart(claim.evidence.first?.sourceName ?? "")
            let imageKey = normalizedURLKey(claim.imageURL)
            let articleKey = normalizedURLKey(claim.evidence.first?.articleURL)
            let sourceImageKey = source.isEmpty || imageKey.isEmpty ? "" : "\(source)|\(imageKey)"
            let sourceArticleKey = source.isEmpty || articleKey.isEmpty ? "" : "\(source)|\(articleKey)"

            // Keep one representative per topic and suppress repeated/aliased story variants.
            if (enforceTopicUniqueness && seenTopics.contains(topicKey))
                || seenTexts.contains(textKey)
                || (!sourceImageKey.isEmpty && seenSourceImage.contains(sourceImageKey))
                || (!sourceArticleKey.isEmpty && seenSourceArticle.contains(sourceArticleKey))
            {
                continue
            }

            seenTopics.insert(topicKey)
            seenTexts.insert(textKey)
            if !sourceImageKey.isEmpty { seenSourceImage.insert(sourceImageKey) }
            if !sourceArticleKey.isEmpty { seenSourceArticle.insert(sourceArticleKey) }
            result.append(claim)
        }
        return result
    }

    private func normalizedTopicPart(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func categoryRank(_ category: String) -> Int {
        let key = normalizedTopicPart(category)
        if key.contains("local") {
            return 0
        }
        if key.contains("world") || key.contains("global") || key.contains("international") {
            return 1
        }
        if key.contains("politic") || key.contains("election") || key.contains("government") {
            return 2
        }
        if key.contains("sport") {
            return 3
        }
        if key.contains("business") || key.contains("market") || key.contains("finance") {
            return 4
        }
        return 50
    }

    private func normalizedText(_ value: String) -> String {
        let lower = value.lowercased()
        let filtered = lower.map { char -> Character in
            if char.isLetter || char.isNumber || char.isWhitespace {
                return char
            }
            return " "
        }
        return String(filtered)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedURLKey(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty, var components = URLComponents(string: raw) else { return "" }
        components.query = nil
        components.fragment = nil
        let host = (components.host ?? "").lowercased()
        let path = components.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if host.isEmpty && path.isEmpty { return "" }
        return "\(host)/\(path)"
    }

    private func normalizedZipOrDefault(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count >= 5 {
            return String(digits.prefix(5))
        }
        return "75201"
    }
}

struct HeadlinesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var vm = HeadlinesViewModel()
    @StateObject private var toast = AppToastState()
    @State private var expandedClaimIDs: Set<String> = []
    @State private var selectedArticle: ArticleDestination?
    @State private var showNewsChat = false
    @AppStorage("bdn-local-news-free-only-ios") private var localNewsFreeOnly = true
    private let deviceID = WatchDeviceIdentity.current

    /// Matches the original `Local News` card visibility rule.
    private var shouldShowLocalNewsBlock: Bool {
        (vm.selectedCategory == "All" || vm.selectedCategory == "Local News")
            && (!vm.localNews.isEmpty || vm.localNewsErrorMessage != nil || vm.isLoading == false)
    }

    /// iPad full width: editorial + local side-by-side when browsing “All” with local available.
    private var useHeadlinesSplitLayout: Bool {
        DeviceLayout.useRegularWidthTabletLayout(horizontalSizeClass: horizontalSizeClass)
            && vm.selectedCategory == "All"
            && shouldShowLocalNewsBlock
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.claims.isEmpty {
                    GeometryReader { geo in
                        ScrollView {
                            VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                                VStack(alignment: .leading, spacing: DeviceLayout.screenIntentToBrandedSpacing) {
                                    ScreenIntentHeader(title: "Headlines", subtitle: "Browse today's stories")
                                    AppBrandedHeader(
                                        sectionTitle: "Headlines",
                                        sectionSubtitle: "",
                                        showSectionHeading: false
                                    )
                                }
                                SkeletonCard()
                                SkeletonCard()
                                SkeletonCard()
                            }
                            .frame(width: contentRailWidth(for: geo.size.width), alignment: .leading)
                            .padding(.horizontal, contentRailInset(for: geo.size.width))
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                } else {
                    GeometryReader { geo in
                        ScrollView {
                            VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                            VStack(alignment: .leading, spacing: DeviceLayout.screenIntentToBrandedSpacing) {
                                ScreenIntentHeader(title: "Headlines", subtitle: "Browse today's stories")
                                AppBrandedHeader(
                                    sectionTitle: "Headlines",
                                    sectionSubtitle: "",
                                    showSectionHeading: false
                                )
                            }
                            BrandCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Categories")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.subtitle)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(vm.categories, id: \.self) { category in
                                                Button {
                                                    vm.selectedCategory = category
                                                } label: {
                                                    Image(systemName: iconName(for: category))
                                                        .font((DeviceLayout.isLargePad ? Font.title : (DeviceLayout.isPad ? Font.title2 : Font.title3)).weight(.semibold))
                                                        .frame(
                                                            width: DeviceLayout.isLargePad ? 56 : (DeviceLayout.isPad ? 50 : 42),
                                                            height: DeviceLayout.isLargePad ? 56 : (DeviceLayout.isPad ? 50 : 42)
                                                        )
                                                        .background(
                                                            vm.selectedCategory == category
                                                                ? selectedCategoryChipColor
                                                                : AppTheme.primary.opacity(0.12)
                                                        )
                                                        .foregroundStyle(
                                                            vm.selectedCategory == category
                                                                ? Color.white
                                                                : Color.primary
                                                        )
                                                        .clipShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel(category)
                                        }
                                    }
                                }
                                }
                            }

                            // Ask the News prompt card
                            Button {
                                showNewsChat = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "sparkles")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.primary)
                                    Text("Ask about today's news…")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.subtitle)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.subtitle.opacity(0.6))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .background(AppTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DeviceLayout.cardCornerRadius)
                                        .stroke(AppTheme.primary.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Ask a question about today's news")

                            if useHeadlinesSplitLayout {
                                HStack(alignment: .top, spacing: 20) {
                                    VStack(alignment: .leading, spacing: DeviceLayout.sectionSpacing) {
                                        editorialHeadlinesBlocks
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    headlinesLocalNewsCard
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else {
                                if shouldShowLocalNewsBlock {
                                    headlinesLocalNewsCard
                                }
                                editorialHeadlinesBlocks
                            }
                            }
                            .frame(width: contentRailWidth(for: geo.size.width), alignment: .leading)
                            .padding(.horizontal, contentRailInset(for: geo.size.width))
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .refreshable {
                        await vm.refresh()
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AppOverflowMenu()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showNewsChat = true
                    } label: {
                        AppToolbarIcon(systemName: "sparkles", role: .neutral)
                    }
                    .accessibilityLabel("Ask about today's news")
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        AppToolbarIcon(systemName: "arrow.triangle.2.circlepath", role: .refresh)
                    }
                    .disabled(vm.isLoading)
                    .accessibilityLabel("Refresh headlines")
                    AppHelpButton()
                }
            }
        }
        .sheet(item: $selectedArticle) { destination in
            ArticleWebView(url: destination.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showNewsChat) {
            NewsChatView()
        }
        .appToastOverlay(toast: toast)
        .task {
            await vm.refreshSavedArticles()
            await vm.refresh()
        }
    }

    // MARK: - iPad: local vs editorial columns

    /// Local news card (shared by stacked and split layouts).
    @ViewBuilder
    private var headlinesLocalNewsCard: some View {
        BrandCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.localNewsLocationLabel.isEmpty
                    ? "Local News"
                    : "Local News • \(vm.localNewsLocationLabel)")
                    .font(.headline)
                if let localError = vm.localNewsErrorMessage {
                    AppContentStateCard(
                        kind: .error,
                        systemImage: "mappin.and.ellipse",
                        title: "Local news unavailable",
                        message: localError,
                        retryTitle: "Try again",
                        onRetry: { Task { await vm.refresh() } },
                        isRetryDisabled: vm.isLoading,
                        compact: true,
                        embedInBrandCard: false
                    )
                } else if vm.localNews.isEmpty {
                    AppContentStateCard(
                        kind: .empty,
                        systemImage: "location.fill",
                        title: "No local stories right now",
                        message: "We’ll show nearby headlines when they’re available. Pull to refresh.",
                        retryTitle: "Refresh",
                        onRetry: { Task { await vm.refresh() } },
                        isRetryDisabled: vm.isLoading,
                        compact: true,
                        embedInBrandCard: false
                    )
                } else {
                    Toggle("Free only", isOn: $localNewsFreeOnly)
                        .font(.caption.weight(.semibold))
                        .tint(AppTheme.primary)

                    let localBaseItems = localNewsFreeOnly
                        ? vm.localNews.filter { !$0.isPaywalled }
                        : vm.localNews
                    let localItems = vm.selectedCategory == "Local News"
                        ? Array(localBaseItems.prefix(12))
                        : Array(localBaseItems.prefix(5))
                    if localItems.isEmpty {
                        AppContentStateCard(
                            kind: .empty,
                            systemImage: localNewsFreeOnly ? "lock.fill" : "newspaper.fill",
                            title: localNewsFreeOnly
                                ? "No free stories with this filter"
                                : "Nothing to show here",
                            message: localNewsFreeOnly
                                ? "Turn off Free only to include subscription sources, or pull to refresh."
                                : "Try again in a moment or pull to refresh.",
                            retryTitle: "Refresh",
                            onRetry: { Task { await vm.refresh() } },
                            isRetryDisabled: vm.isLoading,
                            compact: true,
                            embedInBrandCard: false
                        )
                    }
                    ForEach(localItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            localNewsMediaView(for: item)
                            if let url = URL(string: item.url) {
                                Button {
                                    vm.markArticleRead(item.url)
                                    rememberLastArticle(
                                        title: item.title,
                                        url: item.url,
                                        source: item.sourceName
                                    )
                                    Task {
                                        await APIClient.shared.trackEvent(
                                            deviceID: deviceID,
                                            eventName: "article_open",
                                            eventProps: [
                                                "article_id": articleID(from: item.url),
                                                "source": item.sourceName
                                            ]
                                        )
                                    }
                                    selectedArticle = ArticleDestination(url: url)
                                } label: {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                        .foregroundStyle(vm.isArticleRead(item.url) ? .secondary : .primary)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                            }
                            let source = item.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
                            HStack(spacing: 6) {
                                ContentSourceChip(label: ContentSourceMapping.headlinesLocalChip())
                                Button {
                                    AppHaptics.selection()
                                    let alreadySaved = vm.isArticleSaved(articleID(from: item.url))
                                    Task {
                                        await vm.toggleSavedArticle(
                                            articleID: articleID(from: item.url),
                                            title: item.title,
                                            url: item.url,
                                            sourceName: item.sourceName,
                                            summary: item.summary,
                                            imageURL: item.imageURL ?? ""
                                        )
                                        if !alreadySaved {
                                            toast.show("Article saved")
                                        }
                                    }
                                } label: {
                                    Image(systemName: vm.isArticleSaved(articleID(from: item.url)) ? "bookmark.fill" : "bookmark")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                if let shareURL = URL(string: item.url) {
                                    ShareLink(
                                        item: shareURL,
                                        subject: Text(item.title),
                                        message: Text("via Big Dave's News")
                                    ) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                                if !source.isEmpty {
                                    Text(source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.isPaywalled ? "Subscription" : "Free")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((item.isPaywalled ? Color.orange : Color.green).opacity(0.18))
                                    .foregroundStyle(item.isPaywalled ? Color.orange : Color.green)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    /// Facts / editorial cards (excluding the local column).
    @ViewBuilder
    private var editorialHeadlinesBlocks: some View {
        if let error = vm.errorMessage, vm.selectedCategory != "Local News" {
            ErrorStateCard(
                title: "Can’t load headlines",
                message: error,
                retryTitle: "Try again",
                isRetryDisabled: vm.isLoading
            ) {
                Task { await vm.refresh() }
            }
        }

        if !vm.isLoading, vm.errorMessage == nil, vm.selectedCategory != "Local News",
           vm.filteredClaims.isEmpty {
            AppContentStateCard(
                kind: .empty,
                systemImage: "newspaper.fill",
                title: "Nothing new right now",
                message: "Check back soon — new stories roll in throughout the day.",
                retryTitle: "Refresh",
                onRetry: { Task { await vm.refresh() } },
                isRetryDisabled: vm.isLoading,
                compact: false
            )
        }

        ForEach(vm.filteredClaims) { claim in
            BrandCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ContentSourceChip(label: ContentSourceMapping.headlinesFactsChip())
                        Spacer(minLength: 0)
                    }
                    if let imageURL = claim.imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: DeviceLayout.isLargePad ? 250 : (DeviceLayout.isPad ? 220 : 170))
                                    .clipped()
                                    .cornerRadius(10)
                            case .failure:
                                EmptyView()
                            case .empty:
                                ProgressView().frame(height: 40)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    let isExpanded = expandedClaimIDs.contains(claim.id)
                    if let articleURL = claim.evidence.first?.articleURL, let url = URL(string: articleURL) {
                        Button {
                            vm.markArticleRead(articleURL)
                            rememberLastArticle(
                                title: compactHeadline(from: claim.text),
                                url: articleURL,
                                source: claim.evidence.first?.sourceName ?? ""
                            )
                            Task {
                                await APIClient.shared.trackEvent(
                                    deviceID: deviceID,
                                    eventName: "article_open",
                                    eventProps: [
                                        "article_id": articleID(from: articleURL),
                                        "source": claim.evidence.first?.sourceName ?? ""
                                    ]
                                )
                            }
                            selectedArticle = ArticleDestination(url: url)
                        } label: {
                            Text(isExpanded ? claim.text : compactHeadline(from: claim.text))
                                .font(.headline)
                                .lineLimit(isExpanded ? nil : 2)
                                .foregroundStyle(vm.isArticleRead(articleURL) ? .secondary : .primary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(isExpanded ? claim.text : compactHeadline(from: claim.text))
                            .font(.headline)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                    Button(isExpanded ? "Show less" : "Show full") {
                        if isExpanded {
                            expandedClaimIDs.remove(claim.id)
                        } else {
                            expandedClaimIDs.insert(claim.id)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    if let first = claim.evidence.first {
                        HStack(spacing: 14) {
                            Button {
                                AppHaptics.selection()
                                let alreadySaved = vm.isArticleSaved(articleID(from: first.articleURL))
                                Task {
                                    await vm.toggleSavedArticle(
                                        articleID: articleID(from: first.articleURL),
                                        title: compactHeadline(from: claim.text),
                                        url: first.articleURL,
                                        sourceName: first.sourceName,
                                        summary: claim.text,
                                        imageURL: claim.imageURL ?? ""
                                    )
                                    if !alreadySaved {
                                        toast.show("Article saved")
                                    }
                                }
                            } label: {
                                Label(
                                    vm.isArticleSaved(articleID(from: first.articleURL)) ? "Saved" : "Save",
                                    systemImage: vm.isArticleSaved(articleID(from: first.articleURL)) ? "bookmark.fill" : "bookmark"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            if let shareURL = URL(string: first.articleURL) {
                                ShareLink(
                                    item: shareURL,
                                    subject: Text(compactHeadline(from: claim.text)),
                                    message: Text("via Big Dave's News")
                                ) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("\(claim.category) • \(claim.subtopic)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let first = claim.evidence.first, let url = URL(string: first.articleURL) {
                        Link(first.sourceName, destination: url)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func articleID(from rawURL: String) -> String {
        rawURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func rememberLastArticle(title: String, url: String, source: String) {
        UserDefaults.standard.set("article", forKey: "bdn-last-content-kind-ios")
        UserDefaults.standard.set(title, forKey: "bdn-last-content-title-ios")
        UserDefaults.standard.set(url, forKey: "bdn-last-content-url-ios")
        UserDefaults.standard.set(source, forKey: "bdn-last-content-source-ios")
        UserDefaults.standard.set(Date(), forKey: "bdn-last-content-opened-ios")
    }

    private func compactHeadline(from raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return raw }

        // Prefer the lead clause if feed text includes long trailing context.
        let clauseSeparators = [" | ", " — ", " - ", ": "]
        for sep in clauseSeparators {
            if let range = text.range(of: sep) {
                let lead = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if lead.count >= 24 {
                    text = lead
                    break
                }
            }
        }

        // Fall back to first sentence when available.
        if let sentenceEnd = text.range(of: ". ") {
            let firstSentence = String(text[..<sentenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if firstSentence.count >= 30 {
                text = firstSentence
            }
        }

        // Final cap for a concise, scannable mobile headline.
        let words = text.split(separator: " ")
        let maxWords = 14
        if words.count > maxWords {
            text = words.prefix(maxWords).joined(separator: " ") + "..."
        } else if text.count > 95 {
            text = String(text.prefix(92)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return text
    }

    private func iconName(for category: String) -> String {
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "all" { return "line.3.horizontal.decrease.circle" }
        if key.contains("local") { return "location.fill" }
        if key.contains("business") || key.contains("market") || key.contains("finance") { return "chart.line.uptrend.xyaxis" }
        if key.contains("sport") { return "sportscourt" }
        if key.contains("weather") { return "cloud.sun" }
        if key.contains("politic") || key.contains("election") { return "building.columns" }
        if key.contains("tech") || key.contains("ai") { return "cpu" }
        if key.contains("health") { return "cross.case" }
        if key.contains("entertain") || key.contains("culture") { return "sparkles.tv" }
        if key.contains("world") || key.contains("international") { return "globe.americas" }
        return "newspaper"
    }

    private var selectedCategoryChipColor: Color {
        colorScheme == .dark ? .cyan : AppTheme.accent
    }

    private func contentRailInset(for screenWidth: CGFloat) -> CGFloat {
        if DeviceLayout.isPad {
            return DeviceLayout.horizontalPadding
        }
        // Keep phone inset stable and explicit.
        return 16
    }

    private func contentRailWidth(for screenWidth: CGFloat) -> CGFloat {
        let inset = contentRailInset(for: screenWidth)
        let available = max(0, screenWidth - (inset * 2))
        if DeviceLayout.isPad {
            return min(DeviceLayout.contentMaxWidth, available)
        }
        return available
    }

    @ViewBuilder
    private func localNewsMediaView(for item: LocalNewsItem) -> some View {
        let trimmed = (item.imageURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let imageURL = URL(string: trimmed), !trimmed.isEmpty {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: DeviceLayout.isLargePad ? 190 : (DeviceLayout.isPad ? 170 : 130))
                        .clipped()
                        .cornerRadius(10)
                case .failure:
                    localNewsTextOnlyMediaTag(source: item.sourceName)
                case .empty:
                    localNewsTextOnlyMediaTag(source: item.sourceName, isLoading: true)
                @unknown default:
                    localNewsTextOnlyMediaTag(source: item.sourceName)
                }
            }
        } else {
            localNewsTextOnlyMediaTag(source: item.sourceName)
        }
    }

    private func localNewsTextOnlyMediaTag(source: String, isLoading: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isLoading ? "photo" : "newspaper.fill")
                .foregroundStyle(.secondary)
            Text(isLoading ? "Loading photo..." : "Text-only story")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ArticleDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
