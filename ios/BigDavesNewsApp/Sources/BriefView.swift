import SwiftUI

@MainActor
final class BriefViewModel: ObservableObject {
    @Published var headlines: [Claim] = []
    @Published var weather: WeatherSnapshot?
    @Published var watchPicks: [WatchShowItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastOpenedText = "First open"

    let lastOpenedKey = "bdn-brief-last-opened-ios"
    private let watchDeviceID = WatchDeviceIdentity.current

    init() {
        refreshLastOpenedText()
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

        errorMessage = nextError
    }

    func markOpenedNow() {
        let now = Date()
        UserDefaults.standard.set(now, forKey: lastOpenedKey)
        refreshLastOpenedText()
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
                            Spacer()
                            Text("Daily reminder in Settings")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
                    }
                    .disabled(vm.isLoading)
                    AppOverflowMenu()
                }
            }
        }
        .sheet(item: $selectedArticle) { destination in
            ArticleWebView(url: destination.url)
                .ignoresSafeArea()
        }
        .task {
            vm.markOpenedNow()
            await vm.refresh()
        }
    }

    @ViewBuilder
    private func briefHeadlineRow(for claim: Claim) -> some View {
        if let raw = claim.evidence.first?.articleURL, let url = URL(string: raw) {
            Button {
                selectedArticle = BriefArticleDestination(url: url)
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
