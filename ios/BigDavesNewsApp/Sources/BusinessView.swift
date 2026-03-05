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
        isLoading = true
        errorMessage = nil
        var nextCharts: [String: MarketChart] = [:]
        do {
            for symbol in symbols {
                let chart = try await APIClient.shared.fetchMarketChart(symbol: symbol, range: selectedRange)
                nextCharts[symbol] = chart
            }
            charts = nextCharts
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct BusinessView: View {
    @StateObject private var vm = BusinessViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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
                        }
                    }

                    BrandCard {
                        HStack {
                            TextField("AAPL", text: $vm.newTicker)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            Button("Add") {
                                vm.addTicker()
                                Task { await vm.refresh() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if let error = vm.errorMessage {
                        BrandCard {
                            Text(error).foregroundStyle(.red)
                        }
                    }

                    ForEach(vm.symbols, id: \.self) { symbol in
                        BrandCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(symbol == "^DJI" ? "DOW" : (symbol == "^IXIC" ? "NASDAQ" : symbol))
                                        .font(.headline)
                                    Spacer()
                                    if symbol != "^DJI" && symbol != "^IXIC" {
                                        Button(role: .destructive) {
                                            vm.removeTicker(symbol)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                }

                                if let chart = vm.charts[symbol], !chart.points.isEmpty {
                                    Chart(chart.points) { point in
                                        LineMark(
                                            x: .value("Time", point.t),
                                            y: .value("Value", point.v)
                                        )
                                    }
                                    .frame(height: 170)
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
            .navigationTitle("Business")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
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
}
