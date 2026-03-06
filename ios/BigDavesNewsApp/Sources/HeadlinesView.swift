import SwiftUI

@MainActor
final class HeadlinesViewModel: ObservableObject {
    @Published var claims: [Claim] = []
    @Published var localNews: [LocalNewsItem] = []
    @Published var localNewsLocationLabel = ""
    @Published var localNewsErrorMessage: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedCategory = "All"

    var categories: [String] {
        let unique = Array(Set(claims.map(\.category)))
        let ordered = unique.sorted { lhs, rhs in
            let lRank = categoryRank(lhs)
            let rRank = categoryRank(rhs)
            if lRank == rRank {
                return lhs < rhs
            }
            return lRank < rRank
        }
        return ["All"] + ordered
    }

    var filteredClaims: [Claim] {
        if selectedCategory == "All" {
            return Array(distinctClaims(from: claims, enforceTopicUniqueness: true).prefix(10))
        }
        let scoped = claims.filter { $0.category == selectedCategory }
        return distinctClaims(from: scoped, enforceTopicUniqueness: false)
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        localNewsErrorMessage = nil
        let localZip = normalizedZipOrDefault(UserDefaults.standard.string(forKey: "bdn-weather-zip-ios") ?? "75201")
        do {
            async let factsTask = APIClient.shared.fetchFacts()
            async let localNewsTask = APIClient.shared.fetchLocalNews(zipCode: localZip, limit: 8)
            claims = try await factsTask
            do {
                let localResponse = try await localNewsTask
                localNews = localResponse.items
                localNewsLocationLabel = localResponse.locationLabel
            } catch {
                localNews = []
                localNewsLocationLabel = ""
                localNewsErrorMessage = "Local news is temporarily unavailable."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
    @StateObject private var vm = HeadlinesViewModel()
    @State private var expandedClaimIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.claims.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            AppBrandedHeader(
                                sectionTitle: "Headlines",
                                sectionSubtitle: "Top stories are loading..."
                            )
                            SkeletonCard()
                            SkeletonCard()
                            SkeletonCard()
                        }
                        .padding(.horizontal)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            AppBrandedHeader(
                                sectionTitle: "Headlines",
                                sectionSubtitle: vm.selectedCategory == "All"
                                    ? "Top \(vm.filteredClaims.count) stories across categories"
                                    : "\(vm.filteredClaims.count) stories in \(vm.selectedCategory)"
                            )
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
                                                        .font(.title3.weight(.semibold))
                                                        .frame(width: 42, height: 42)
                                                        .background(
                                                            vm.selectedCategory == category
                                                                ? AppTheme.accent
                                                                : AppTheme.primary.opacity(0.12)
                                                        )
                                                        .foregroundStyle(
                                                            vm.selectedCategory == category
                                                                ? Color.white
                                                                : AppTheme.primary
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

                            if !vm.localNews.isEmpty || vm.localNewsErrorMessage != nil {
                                BrandCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(vm.localNewsLocationLabel.isEmpty
                                             ? "Local News"
                                             : "Local News • \(vm.localNewsLocationLabel)")
                                            .font(.headline)
                                        if let localError = vm.localNewsErrorMessage {
                                            Text(localError)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            ForEach(vm.localNews.prefix(5)) { item in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    if let url = URL(string: item.url) {
                                                        Link(item.title, destination: url)
                                                            .font(.subheadline.weight(.semibold))
                                                            .lineLimit(2)
                                                    } else {
                                                        Text(item.title)
                                                            .font(.subheadline.weight(.semibold))
                                                            .lineLimit(2)
                                                    }
                                                    let source = item.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    if !source.isEmpty {
                                                        Text(source)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                .padding(.vertical, 2)
                                            }
                                        }
                                    }
                                }
                            }

                            if let error = vm.errorMessage {
                                ErrorStateCard(
                                    title: "Headlines unavailable",
                                    message: error,
                                    isRetryDisabled: vm.isLoading
                                ) {
                                    Task { await vm.refresh() }
                                }
                            }

                            ForEach(vm.filteredClaims) { claim in
                                BrandCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let imageURL = claim.imageURL, let url = URL(string: imageURL) {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(height: 170)
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
                                        Text(isExpanded ? claim.text : compactHeadline(from: claim.text))
                                            .font(.headline)
                                            .lineLimit(isExpanded ? nil : 2)
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
                    }
                    .padding(.horizontal)
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
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isLoading)
                }
            }
        }
        .task {
            await vm.refresh()
        }
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
}
