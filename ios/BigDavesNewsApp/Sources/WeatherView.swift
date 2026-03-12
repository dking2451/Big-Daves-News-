import CoreLocation
import SwiftUI
import UIKit

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

@MainActor
final class WeatherViewModel: ObservableObject {
    enum LocationMode: String {
        case currentLocation
        case zipCode
    }

    @Published var mode: LocationMode = (UserDefaults.standard.string(forKey: "bdn-weather-mode-ios") == "zipCode") ? .zipCode : .currentLocation
    @Published var zipCode: String = UserDefaults.standard.string(forKey: "bdn-weather-zip-ios") ?? "75201"
    @Published var weather: WeatherSnapshot?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    func refresh(currentLocation: CLLocationCoordinate2D?) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        do {
            if mode == .currentLocation {
                guard let location = currentLocation else {
                    if let cached = loadWeatherCache(key: locationPendingCacheKey()) {
                        weather = cached
                        infoMessage = "Waiting for iPhone location. Showing last local weather."
                    } else {
                        errorMessage = "Current location not available yet. Tap Use Phone Location and allow permission."
                    }
                    isLoading = false
                    return
                }
                let snapshot = try await APIClient.shared.fetchWeather(lat: location.latitude, lon: location.longitude)
                weather = snapshot
                saveWeatherCache(snapshot, key: locationCacheKey(for: location))
                saveWeatherCache(snapshot, key: locationPendingCacheKey())
            } else {
                let normalizedZip = normalizedZipOrFallback(zipCode)
                let snapshot = try await APIClient.shared.fetchWeather(zipCode: normalizedZip)
                zipCode = normalizedZip
                UserDefaults.standard.set(normalizedZip, forKey: "bdn-weather-zip-ios")
                weather = snapshot
                saveWeatherCache(snapshot, key: zipCacheKey(zipCode: normalizedZip))
            }
        } catch {
            if mode == .currentLocation, let location = currentLocation {
                if let cached = loadWeatherCache(key: locationCacheKey(for: location)) {
                    weather = cached
                    infoMessage = "Weather provider is busy. Showing last local update."
                } else if let cached = loadWeatherCache(key: locationPendingCacheKey()) {
                    weather = cached
                    infoMessage = "Weather provider is busy. Showing last local update."
                } else {
                    errorMessage = friendlyWeatherMessage(from: error.localizedDescription)
                }
            } else {
                if let cached = loadWeatherCache(key: zipCacheKey(zipCode: zipCode)) {
                    weather = cached
                    infoMessage = "Weather provider is busy. Showing last available ZIP weather."
                } else {
                    errorMessage = friendlyWeatherMessage(from: error.localizedDescription)
                }
            }
        }
        UserDefaults.standard.set(mode.rawValue, forKey: "bdn-weather-mode-ios")
        isLoading = false
    }

    private func locationCacheKey(for location: CLLocationCoordinate2D) -> String {
        let lat = String(format: "%.2f", location.latitude)
        let lon = String(format: "%.2f", location.longitude)
        return "bdn-weather-cache-ios-current-\(lat)-\(lon)"
    }

    private func locationPendingCacheKey() -> String {
        "bdn-weather-cache-ios-current-last"
    }

    private func zipCacheKey(zipCode: String) -> String {
        "bdn-weather-cache-ios-zip-\(zipCode)"
    }

    private func saveWeatherCache(_ snapshot: WeatherSnapshot, key: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func loadWeatherCache(key: String) -> WeatherSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    private func friendlyWeatherMessage(from message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("busy") || lower.contains("429") || lower.contains("too many requests") {
            return "Weather provider is busy. Please retry in 1-2 minutes."
        }
        if lower.contains("could not find that zip") || lower.contains("invalid zip") || lower.contains("zip") {
            return "We couldn't find that ZIP. Please enter a 5-digit US ZIP code."
        }
        if lower.contains("timeout") {
            return "Weather lookup timed out. Please retry in a moment."
        }
        return message
    }

    private func normalizedZipOrFallback(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count >= 5 {
            return String(digits.prefix(5))
        }
        let saved = UserDefaults.standard.string(forKey: "bdn-weather-zip-ios") ?? ""
        let savedDigits = saved.filter(\.isNumber)
        if savedDigits.count >= 5 {
            return String(savedDigits.prefix(5))
        }
        return "75201"
    }
}

final class WeatherLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var locationLabel: String?
    @Published var locationError: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func refreshLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            self.currentLocation = coordinate
            self.locationError = nil
        }
        if let coordinate {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                let placemark = placemarks?.first
                let parts = [placemark?.locality, placemark?.administrativeArea, placemark?.country]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                let label = parts.isEmpty ? nil : parts.joined(separator: ", ")
                Task { @MainActor in
                    self?.locationLabel = label
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.locationError = message
        }
    }
}

struct WeatherView: View {
    @StateObject private var vm = WeatherViewModel()
    @StateObject private var locationManager = WeatherLocationManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AppBrandedHeader(
                        sectionTitle: "Weather",
                        sectionSubtitle: vm.mode == .currentLocation
                            ? "Live local conditions and forecast"
                            : "ZIP-based weather and forecast"
                    )
                    BrandCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Location")
                                .font(.headline)
                            Picker("Weather source", selection: $vm.mode) {
                                Text("Current Location").tag(WeatherViewModel.LocationMode.currentLocation)
                                Text("ZIP Code").tag(WeatherViewModel.LocationMode.zipCode)
                            }
                            .pickerStyle(.segmented)

                            if vm.mode == .zipCode {
                                TextField("ZIP code", text: $vm.zipCode)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                HStack {
                                    Button("Use Phone Location") {
                                        locationManager.refreshLocation()
                                        if locationManager.currentLocation != nil {
                                            Task { await vm.refresh(currentLocation: locationManager.currentLocation) }
                                        } else {
                                            vm.infoMessage = "Getting current location..."
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    if let label = locationManager.locationLabel, !label.isEmpty {
                                        Text(label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if let location = locationManager.currentLocation {
                                        Text(String(format: "Lat %.3f, Lon %.3f", location.latitude, location.longitude))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                                    Text("Location access is off. Enable it in iOS Settings for local weather.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if locationManager.currentLocation == nil {
                                    Text("Waiting for iPhone location...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let locationError = locationManager.locationError {
                                    Text(locationError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            Button("Refresh Weather") {
                                Task { await vm.refresh(currentLocation: locationManager.currentLocation) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(vm.isLoading)
                        }
                    }

                    if vm.isLoading {
                        SkeletonCard()
                        SkeletonCard()
                    }

                    if let error = vm.errorMessage {
                        ErrorStateCard(
                            title: "Weather unavailable",
                            message: error,
                            isRetryDisabled: vm.isLoading
                        ) {
                            Task { await vm.refresh(currentLocation: locationManager.currentLocation) }
                        }
                    }
                    if let info = vm.infoMessage {
                        BrandCard {
                            Text(info)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let weather = vm.weather {
                        BrandCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(displayLocationLabel(weather: weather)).font(.headline)
                                Text("\(weather.weatherIcon) \(displayWeatherText(weather.weatherText, icon: weather.weatherIcon))")
                                Text("Temp: \(weather.temperatureF, specifier: "%.1f")°F")
                                Text("Wind: \(weather.windMPH, specifier: "%.1f") mph")
                                Text("Updated: \(weather.observedAt)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                #if DEBUG
                                if let source = weather.dataProvider, !source.isEmpty {
                                    Text("Source: \(source)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                #endif
                            }
                        }

                        if !weather.alerts.isEmpty {
                            BrandCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Weather Alerts")
                                        .font(.headline)
                                    ForEach(weather.alerts.prefix(3)) { alert in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(alert.headline)
                                                .font(.subheadline.weight(.semibold))
                                            Text("\(alert.event) • \(alert.severity)")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(alertColor(for: alert.severity))
                                            if !alert.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text(alert.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(3)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    Button {
                                        openAppleWeather(for: weather)
                                    } label: {
                                        Label("Open in Apple Weather", systemImage: "cloud.sun")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        if !weather.forecast5Day.isEmpty {
                            BrandCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("5-Day Forecast")
                                        .font(.headline)
                                    ForEach(displayedForecastDays(from: weather)) { day in
                                        HStack(alignment: .center, spacing: 10) {
                                            Text(day.isToday ? "TOD" : shortWeekday(from: day.date))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.blue)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.12))
                                                .clipShape(Capsule())

                                            Text(day.weatherIcon)
                                                .font(.title3)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(displayWeatherText(day.weatherText, icon: day.weatherIcon))
                                                    .font(.subheadline.weight(.semibold))
                                                if let precip = day.precipitationProbabilityMax {
                                                    Text("Rain \(Int(precip))%")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            Spacer()
                                            HStack(spacing: 6) {
                                                Text("\(Int(day.tempMaxF ?? 0))°")
                                                    .font(.subheadline.weight(.bold))
                                                    .foregroundStyle(.red)
                                                Text("\(Int(day.tempMinF ?? 0))°")
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }

                        if !weather.rainTimeline.isEmpty {
                            BrandCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Live Rain Chances")
                                        .font(.headline)
                                    ForEach(Array(weather.rainTimeline.prefix(6).enumerated()), id: \.element.id) { index, point in
                                        HStack {
                                            Text(hourBlockLabel(index))
                                                .font(.caption.weight(.semibold))
                                                .frame(width: 48, alignment: .leading)

                                            GeometryReader { geo in
                                                let pct = max(0, min(100, point.precipitationProbability ?? 0))
                                                let width = geo.size.width * CGFloat(pct / 100)
                                                ZStack(alignment: .leading) {
                                                    Capsule()
                                                        .fill(Color.blue.opacity(0.15))
                                                    Capsule()
                                                        .fill(Color.blue.opacity(0.85))
                                                        .frame(width: width)
                                                }
                                            }
                                            .frame(height: 10)

                                            Spacer()
                                            Text("\(Int(point.precipitationProbability ?? 0))%")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }

                        if let embed = weather.mapEmbedURL, let embedURL = URL(string: embed) {
                            BrandCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Live Radar")
                                        .font(.headline)
                                    RadarWebView(url: embedURL)
                                        .frame(height: DeviceLayout.isLargePad ? 320 : (DeviceLayout.isPad ? 280 : 250))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Button {
                                        openAppleWeather(for: weather)
                                    } label: {
                                        Label("Open in Apple Weather", systemImage: "cloud.sun")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    if let fullMap = weather.mapURL, let fullMapURL = URL(string: fullMap) {
                                        Link("Open Full Radar", destination: fullMapURL)
                                            .font(.caption.weight(.semibold))
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.refresh(currentLocation: locationManager.currentLocation) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isLoading)
                    AppOverflowMenu()
                }
            }
        }
        .onChange(of: locationManager.currentLocation) { coordinate in
            guard vm.mode == .currentLocation, coordinate != nil else { return }
            Task { await vm.refresh(currentLocation: coordinate) }
        }
        .onChange(of: vm.mode) { mode in
            if mode == .currentLocation {
                locationManager.refreshLocation()
                if locationManager.currentLocation == nil {
                    vm.infoMessage = "Getting current location..."
                }
            }
        }
        .task {
            if vm.mode == .currentLocation {
                locationManager.refreshLocation()
                if locationManager.currentLocation == nil {
                    vm.infoMessage = "Getting current location..."
                } else {
                    await vm.refresh(currentLocation: locationManager.currentLocation)
                }
            } else {
                await vm.refresh(currentLocation: locationManager.currentLocation)
            }
        }
    }

    private struct ForecastDisplayDay: Identifiable {
        let id: String
        let date: String
        let weatherText: String
        let weatherIcon: String
        let tempMaxF: Double?
        let tempMinF: Double?
        let precipitationProbabilityMax: Double?
        let isToday: Bool
    }

    private func displayedForecastDays(from weather: WeatherSnapshot) -> [ForecastDisplayDay] {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let sorted = weather.forecast5Day.compactMap { day -> (ForecastDay, Date)? in
            guard let date = parseDayDate(day.date) else { return nil }
            return (day, date)
        }
        .sorted { $0.1 < $1.1 }

        // Product requirement: show next day + following 4 days.
        var selected = sorted.filter { $0.1 > todayStart }.prefix(5).map(\.0)
        if selected.isEmpty {
            selected = sorted.prefix(5).map(\.0)
        }

        return Array(selected.prefix(5)).map { day in
            let parsedDate = parseDayDate(day.date)
            let isToday = parsedDate.map { Calendar.current.isDateInToday($0) } ?? false
            return ForecastDisplayDay(
                id: day.date,
                date: day.date,
                weatherText: day.weatherText,
                weatherIcon: day.weatherIcon,
                tempMaxF: day.tempMaxF,
                tempMinF: day.tempMinF,
                precipitationProbabilityMax: day.precipitationProbabilityMax,
                isToday: isToday
            )
        }
    }

    private func parseDayDate(_ isoDate: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.date(from: isoDate)
    }

    private func shortWeekday(from isoDate: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.locale = Locale(identifier: "en_US_POSIX")
        input.timeZone = TimeZone(secondsFromGMT: 0)

        guard let date = input.date(from: isoDate) else {
            return isoDate
        }

        let output = DateFormatter()
        output.dateFormat = "EEE"
        output.locale = Locale.current
        return output.string(from: date).uppercased()
    }

    private func displayLocationLabel(weather: WeatherSnapshot) -> String {
        if vm.mode == .currentLocation, let label = locationManager.locationLabel, !label.isEmpty {
            return label
        }
        return weather.locationLabel
    }

    private func shortTime(from isoDateTime: String) -> String {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: isoDateTime) {
            let out = DateFormatter()
            out.dateFormat = "ha"
            out.amSymbol = "a"
            out.pmSymbol = "p"
            return out.string(from: date).lowercased()
        }
        return isoDateTime
    }

    private func hourBlockLabel(_ index: Int) -> String {
        if index <= 0 { return "Now" }
        return "+\(index)h"
    }

    private func displayWeatherText(_ raw: String, icon: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if trimmed.isEmpty || lower == "weather update" || lower == "weather" || lower == "unknown" {
            switch icon {
            case "☀️":
                return "Sunny"
            case "⛅":
                return "Partly Cloudy"
            case "🌫️":
                return "Foggy"
            case "🌧️":
                return "Rain Likely"
            case "❄️":
                return "Snow Possible"
            case "⛈️":
                return "Thunderstorms"
            default:
                return "Changing Conditions"
            }
        }
        return trimmed
    }

    private func alertColor(for severity: String) -> Color {
        let key = severity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.contains("extreme") || key.contains("severe") {
            return .red
        }
        if key.contains("moderate") {
            return .orange
        }
        return .secondary
    }

    private func noaaAlertsURL(for weather: WeatherSnapshot) -> URL? {
        guard let lat = weather.latitude, let lon = weather.longitude else { return nil }
        var components = URLComponents(string: "https://forecast.weather.gov/MapClick.php")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon))
        ]
        return components?.url
    }

    private func openAppleWeather(for weather: WeatherSnapshot) {
        guard let lat = weather.latitude, let lon = weather.longitude else {
            if let windy = weather.mapURL, let windyURL = URL(string: windy) {
                UIApplication.shared.open(windyURL)
            }
            return
        }
        var components = URLComponents(string: "https://weather.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "long", value: String(lon))
        ]
        guard let appleURL = components?.url else {
            if let windy = weather.mapURL, let windyURL = URL(string: windy) {
                UIApplication.shared.open(windyURL)
            }
            return
        }
        UIApplication.shared.open(appleURL, options: [:]) { accepted in
            if accepted { return }
            if let windy = weather.mapURL, let windyURL = URL(string: windy) {
                UIApplication.shared.open(windyURL)
            }
        }
    }
}
