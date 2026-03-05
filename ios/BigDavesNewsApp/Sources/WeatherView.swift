import SwiftUI

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var zipCode: String = UserDefaults.standard.string(forKey: "bdn-weather-zip-ios") ?? "75201"
    @Published var weather: WeatherSnapshot?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let snapshot = try await APIClient.shared.fetchWeather(zipCode: zipCode)
            weather = snapshot
            UserDefaults.standard.set(zipCode, forKey: "bdn-weather-zip-ios")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct WeatherView: View {
    @StateObject private var vm = WeatherViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    BrandCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Location")
                                .font(.headline)
                            TextField("ZIP code", text: $vm.zipCode)
                                .keyboardType(.numberPad)
                            Button("Refresh Weather") {
                                Task { await vm.refresh() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if vm.isLoading {
                        BrandCard {
                            ProgressView("Loading weather...")
                        }
                    }

                    if let error = vm.errorMessage {
                        BrandCard {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }

                    if let weather = vm.weather {
                        BrandCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(weather.locationLabel).font(.headline)
                                Text("\(weather.weatherIcon) \(weather.weatherText)")
                                Text("Temp: \(weather.temperatureF, specifier: "%.1f")°F")
                                Text("Wind: \(weather.windMPH, specifier: "%.1f") mph")
                                Text("Updated: \(weather.observedAt)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Weather")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await vm.refresh()
        }
    }
}
