import Charts
import SwiftUI

@MainActor
final class BusinessViewModel: ObservableObject {
    @Published var symbols: [String] = ["^DJI", "^IXIC"]
    @Published var selectedRange = "3mo"
    @Published var charts: [String: MarketChart] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var newTicker = ""

    private let favoritesKey = "bdn-favorite-tickers-ios"
    private let defaultSymbols = ["^DJI", "^IXIC"]
    private var refreshGeneration = 0

    init() {
        loadFavorites()
    }

    func loadFavorites() {
        guard let raw = UserDefaults.standard.array(forKey: favoritesKey) as? [String] else { return }
        let normalized = raw.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !defaultSymbols.contains($0) }
        symbols = defaultSymbols + Array(Set(normalized)).sorted()
    }

    func saveFavorites() {
        let favorites = symbols.filter { !defaultSymbols.contains($0) }
        UserDefaults.standard.set(favorites, forKey: favoritesKey)
    }

    func addTicker() {
        let ticker = newTicker.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ticker.isEmpty else { return }
        guard !symbols.contains(ticker) else { return }
        symbols.append(ticker)
        newTicker = ""
        saveFavorites()
    }

    func removeTicker(_ symbol: String) {
        guard !defaultSymbols.contains(symbol) else { return }
        symbols.removeAll { $0 == symbol }
        charts[symbol] = nil
        saveFavorites()
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoading = true
        defer {
            if generation == refreshGeneration {
                isLoading = false
            }
        }
        errorMessage = nil
        var nextCharts: [String: MarketChart] = [:]
        var failures: [String] = []
        let symbolsSnapshot = symbols
        let rangeSnapshot = selectedRange

        await withTaskGroup(of: (String, Result<MarketChart, Error>).self) { group in
            for symbol in symbolsSnapshot {
                group.addTask {
                    do {
                        let chart = try await APIClient.shared.fetchMarketChart(symbol: symbol, range: rangeSnapshot)
                        return (symbol, .success(chart))
                    } catch {
                        return (symbol, .failure(error))
                    }
                }
            }

            for await (symbol, result) in group {
                switch result {
                case .success(let chart):
                    nextCharts[symbol] = chart
                case .failure:
                    failures.append(symbol)
                }
            }
        }
        // Prevent stale async results from older requests overwriting current filter.
        guard generation == refreshGeneration else { return }
        guard rangeSnapshot == selectedRange else { return }
        charts = nextCharts
        if !failures.isEmpty {
            if nextCharts.isEmpty {
                errorMessage = "Unable to load market data right now."
            } else {
                errorMessage = "Some symbols failed: \(failures.joined(separator: ", "))"
            }
        }
    }
}

struct BusinessView: View {
    @StateObject private var vm = BusinessViewModel()
    @AppStorage("bdn-business-gentle-scale-ios") private var useGentleScale = false
    @FocusState private var isTickerFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    AppBrandedHeader(
                        sectionTitle: "Business",
                        sectionSubtitle: "Market snapshots, trends, and your watchlist"
                    )
                    if vm.isLoading {
                        BrandCard {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Updating market data...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    BrandCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Range")
                                .font(.headline)
                            Picker("Range", selection: $vm.selectedRange) {
                                Text("1D").tag("1d")
                                Text("1W").tag("1w")
                                Text("3M").tag("3mo")
                                Text("6M").tag("6mo")
                                Text("1Y").tag("1y")
                                Text("All").tag("max")
                            }
                            .pickerStyle(.segmented)
                            Toggle("Less-sensitive chart scale", isOn: $useGentleScale)
                                .font(.subheadline)
                        }
                    }

                    BrandCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add Ticker")
                                .font(.headline)
                            HStack {
                                TextField("e.g. AAPL", text: $vm.newTicker)
                                    .focused($isTickerFieldFocused)
                                    .submitLabel(.done)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        vm.addTicker()
                                        Task { await vm.refresh() }
                                    }
                                Button {
                                    isTickerFieldFocused = true
                                } label: {
                                    Image(systemName: "keyboard")
                                }
                                .buttonStyle(.bordered)
                                Button("Add Ticker") {
                                    if vm.newTicker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        isTickerFieldFocused = true
                                        return
                                    }
                                    vm.addTicker()
                                    Task { await vm.refresh() }
                                    isTickerFieldFocused = false
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(vm.isLoading)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if vm.isLoading && vm.charts.isEmpty {
                            SkeletonCard()
                            SkeletonCard()
                        }
                        if let error = vm.errorMessage {
                            ErrorStateCard(
                                title: "Market data issue",
                                message: error,
                                isRetryDisabled: vm.isLoading
                            ) {
                                Task { await vm.refresh() }
                            }
                        }

                        ForEach(vm.symbols, id: \.self) { symbol in
                            BrandCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(symbol == "^DJI" ? "DOW" : (symbol == "^IXIC" ? "NASDAQ" : symbol))
                                            .font(.headline)
                                        if let latestPrice = vm.charts[symbol]?.points.last?.v {
                                            Text("Current: \(formattedPrice(latestPrice))")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if let chart = vm.charts[symbol], let change = changeMetrics(for: chart.points) {
                                            Text(change.badgeText)
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(change.color.opacity(0.15))
                                                .foregroundStyle(change.color)
                                                .clipShape(Capsule())
                                        }
                                        if symbol != "^DJI" && symbol != "^IXIC" {
                                            Button(role: .destructive) {
                                                vm.removeTicker(symbol)
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                        }
                                    }

                                    if let chart = vm.charts[symbol], !chart.points.isEmpty {
                                        if vm.selectedRange == "1d" {
                                            ScrollView(.horizontal, showsIndicators: true) {
                                                Chart(chart.points) { point in
                                                    LineMark(
                                                        x: .value("Time", point.date),
                                                        y: .value("Value", point.v)
                                                    )
                                                    .interpolationMethod(.catmullRom)
                                                }
                                                .chartYScale(domain: yDomain(for: chart.points, gentle: useGentleScale, selectedRange: vm.selectedRange))
                                                .chartXAxis {
                                                    AxisMarks(values: xAxisStride(for: chart.points, selectedRange: vm.selectedRange)) { value in
                                                        AxisGridLine()
                                                        AxisTick()
                                                        AxisValueLabel(format: xAxisLabelFormat(for: chart.points, selectedRange: vm.selectedRange))
                                                    }
                                                }
                                                .frame(width: max(360, CGFloat(chart.points.count) * 22), height: 170)
                                            }
                                        } else {
                                            Chart(chart.points) { point in
                                                LineMark(
                                                    x: .value("Time", point.date),
                                                    y: .value("Value", point.v)
                                                )
                                                .interpolationMethod(.catmullRom)
                                            }
                                            .chartYScale(domain: yDomain(for: chart.points, gentle: useGentleScale, selectedRange: vm.selectedRange))
                                            .chartXAxis {
                                                AxisMarks(values: xAxisStride(for: chart.points, selectedRange: vm.selectedRange)) { value in
                                                    AxisGridLine()
                                                    AxisTick()
                                                    AxisValueLabel(format: xAxisLabelFormat(for: chart.points, selectedRange: vm.selectedRange))
                                                }
                                            }
                                            .frame(height: 170)
                                        }
                                    } else if vm.isLoading {
                                        ProgressView()
                                    } else {
                                        Text("No chart data yet.")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("")
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                            .padding(8)
                            .background(AppTheme.primary.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .disabled(vm.isLoading)
                    .accessibilityLabel("Refresh business data")
                    AppOverflowMenu()
                }
            }
            .onChange(of: vm.selectedRange) { _ in
                Task { await vm.refresh() }
            }
        }
        .task {
            await vm.refresh()
        }
    }

    private func yDomain(for points: [MarketPoint], gentle: Bool, selectedRange: String) -> ClosedRange<Double> {
        let values = points.map(\.v)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }
        let mid = (minValue + maxValue) / 2
        if minValue == maxValue {
            let relative = gentle ? 0.03 : 0.01
            let pad = max(1.0, abs(minValue) * relative)
            return (minValue - pad)...(maxValue + pad)
        }
        let spread = maxValue - minValue
        let rangePadFactor = selectedRange == "1d" ? 0.04 : 0.12
        let basePad = max(spread * rangePadFactor, 0.25)
        if !gentle {
            return (minValue - basePad)...(maxValue + basePad)
        }

        // Widen small ranges to reduce exaggerated movement.
        let minSpreadForGentle = max(abs(mid) * 0.05, spread)
        let extraPad = (minSpreadForGentle - spread) / 2
        let pad = max(basePad, extraPad + (spread * 0.08))
        return (minValue - pad)...(maxValue + pad)
    }

    private func xAxisStride(for points: [MarketPoint], selectedRange: String) -> AxisMarkValues {
        let spanHours = spanInHours(points)
        switch selectedRange {
        case "1d":
            // If fallback data is daily points, avoid unreadable hourly labels.
            return spanHours <= 36 ? .stride(by: .hour, count: 1) : .stride(by: .day, count: 1)
        case "1w":
            return .stride(by: .day, count: 1)
        case "3mo":
            return .stride(by: .day, count: 14)
        case "6mo":
            return .stride(by: .month, count: 1)
        case "1y":
            return .stride(by: .month, count: 2)
        default:
            // "All" range should show year-based ticks for readability.
            return .stride(by: .year, count: 1)
        }
    }

    private func xAxisLabelFormat(for points: [MarketPoint], selectedRange: String) -> Date.FormatStyle {
        let spanHours = spanInHours(points)
        switch selectedRange {
        case "1d":
            return spanHours <= 36
                ? .dateTime.hour(.defaultDigits(amPM: .omitted))
                : .dateTime.month(.abbreviated).day()
        case "1w":
            // Weekly range should read as days (not hours) for clarity.
            return .dateTime.weekday(.abbreviated)
        case "3mo":
            return .dateTime.month(.abbreviated).day()
        default:
            // "All" range should present years on the x-axis.
            return .dateTime.year()
        }
    }

    private func spanInHours(_ points: [MarketPoint]) -> Double {
        guard let first = points.first?.date, let last = points.last?.date else { return 0 }
        return last.timeIntervalSince(first) / 3600
    }

    private func changeMetrics(for points: [MarketPoint]) -> (badgeText: String, color: Color)? {
        guard let first = points.first?.v, let last = points.last?.v, first != 0 else { return nil }
        let delta = last - first
        let pct = (delta / first) * 100
        let sign = pct >= 0 ? "+" : ""
        let text = "\(sign)\(String(format: "%.2f", pct))%"
        let color: Color = pct >= 0 ? .green : .red
        return (text, color)
    }

    private func formattedPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
