import Foundation
import CoreLocation
import WeatherKit

enum APIConfig {
    static let baseURL = URL(string: "https://big-daves-news-web.onrender.com")!
}

struct SubscribeRequest: Encodable {
    let email: String
}

struct SubscribeResponse: Decodable {
    let success: Bool
    let message: String
    let count: Int
    let max: Int
}

struct PushTokenRegisterRequest: Encodable {
    let deviceToken: String
    let platform: String
    let subscriberEmail: String
    let appBundleID: String
    let timezoneName: String

    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
        case platform
        case subscriberEmail = "subscriber_email"
        case appBundleID = "app_bundle_id"
        case timezoneName = "timezone_name"
    }
}

struct PushTokenUnregisterRequest: Encodable {
    let deviceToken: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
        case platform
    }
}

struct PushTokenResponse: Decodable {
    let success: Bool
    let message: String
    let activeDevices: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case activeDevices = "active_devices"
    }
}

struct FactsResponse: Decodable {
    let claims: [Claim]
}

struct LocalNewsResponse: Decodable {
    let success: Bool
    let message: String?
    let zipCode: String
    let locationLabel: String
    let items: [LocalNewsItem]

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case zipCode = "zip_code"
        case locationLabel = "location_label"
        case items
    }
}

struct LocalNewsItem: Decodable, Identifiable {
    let title: String
    let url: String
    let sourceName: String
    let published: String
    let summary: String
    let imageURL: String?
    let isPaywalled: Bool
    var id: String { "\(title)|\(url)" }

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case sourceName = "source_name"
        case published
        case summary
        case imageURL = "image_url"
        case isPaywalled = "is_paywalled"
    }
}

struct Claim: Decodable, Identifiable {
    let claimID: String
    let text: String
    let category: String
    let subtopic: String
    let status: String
    let confidence: String
    let imageURL: String?
    let evidence: [ClaimEvidence]

    var id: String { claimID }

    enum CodingKeys: String, CodingKey {
        case claimID = "claim_id"
        case text
        case category
        case subtopic
        case status
        case confidence
        case imageURL = "image_url"
        case evidence
    }
}

struct ClaimEvidence: Decodable {
    let sourceName: String
    let articleTitle: String
    let articleURL: String

    enum CodingKeys: String, CodingKey {
        case sourceName = "source_name"
        case articleTitle = "article_title"
        case articleURL = "article_url"
    }
}

struct WeatherResponse: Codable {
    let success: Bool
    let message: String?
    let weather: WeatherSnapshot?
}

struct WeatherSnapshot: Codable {
    let locationLabel: String
    let temperatureF: Double
    let windMPH: Double
    let weatherText: String
    let weatherIcon: String
    let observedAt: String
    let latitude: Double?
    let longitude: Double?
    let mapURL: String?
    let mapEmbedURL: String?
    let alerts: [WeatherAlert]
    let rainTimeline: [RainPoint]
    let forecast5Day: [ForecastDay]

    enum CodingKeys: String, CodingKey {
        case locationLabel = "location_label"
        case temperatureF = "temperature_f"
        case windMPH = "wind_mph"
        case weatherText = "weather_text"
        case weatherIcon = "weather_icon"
        case observedAt = "observed_at"
        case latitude
        case longitude
        case mapURL = "map_url"
        case mapEmbedURL = "map_embed_url"
        case alerts
        case rainTimeline = "rain_timeline"
        case forecast5Day = "forecast_5day"
    }
}

struct WeatherAlert: Codable, Identifiable {
    let headline: String
    let severity: String
    let event: String
    let effective: String?
    let ends: String?
    let description: String
    let url: String?
    var id: String { "\(headline)-\(event)-\(effective ?? "")" }
}

struct RainPoint: Codable, Identifiable {
    let time: String
    let precipitationProbability: Double?
    let precipitationIn: Double?
    var id: String { time }

    enum CodingKeys: String, CodingKey {
        case time
        case precipitationProbability = "precipitation_probability"
        case precipitationIn = "precipitation_in"
    }
}

struct ForecastDay: Codable, Identifiable {
    let date: String
    let weatherText: String
    let weatherIcon: String
    let tempMaxF: Double?
    let tempMinF: Double?
    let precipitationProbabilityMax: Double?
    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date
        case weatherText = "weather_text"
        case weatherIcon = "weather_icon"
        case tempMaxF = "temp_max_f"
        case tempMinF = "temp_min_f"
        case precipitationProbabilityMax = "precipitation_probability_max"
    }
}

struct MarketChartResponse: Decodable {
    let success: Bool
    let message: String?
    let chart: MarketChart?
}

struct MarketChart: Decodable {
    let displayName: String?
    let interval: String?
    let points: [MarketPoint]

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case interval
        case points
    }
}

struct MarketPoint: Decodable, Identifiable {
    let t: String
    let v: Double
    var id: String { t }
    var date: Date {
        if let date = Self.isoFormatterWithFractionalSeconds.date(from: t) {
            return date
        }
        return Self.isoFormatter.date(from: t) ?? .distantPast
    }

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum APIError: LocalizedError {
    case badURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid request URL."
        case .invalidResponse:
            return "Unexpected server response."
        case .server(let message):
            return message
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    private init() {}

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()

    func fetchFacts() async throws -> [Claim] {
        let url = APIConfig.baseURL.appendingPathComponent("api/facts")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(FactsResponse.self, from: data).claims
    }

    func fetchLocalNews(zipCode: String, limit: Int = 8) async throws -> LocalNewsResponse {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent("api/local-news"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "zip_code", value: zipCode),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 25))))
        ]
        guard let url = components?.url else { throw APIError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        let decoded = try decoder.decode(LocalNewsResponse.self, from: data)
        if decoded.success {
            return decoded
        }
        throw APIError.server(decoded.message ?? "Local news unavailable.")
    }

    func fetchWeather(zipCode: String) async throws -> WeatherSnapshot {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent("api/weather"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "zip_code", value: zipCode)]
        guard let url = components?.url else { throw APIError.badURL }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return try await fetchWeatherDirect(zipCode: zipCode)
            }
            let decoded = try decoder.decode(WeatherResponse.self, from: data)
            if decoded.success, let weather = decoded.weather {
                return weather
            }
            let message = decoded.message ?? "Weather unavailable."
            if isProviderBusyMessage(message) {
                return try await fetchWeatherDirect(zipCode: zipCode)
            }
            throw APIError.server(message)
        } catch {
            return try await fetchWeatherDirect(zipCode: zipCode)
        }
    }

    func fetchWeather(lat: Double, lon: Double) async throws -> WeatherSnapshot {
        // For live location, prefer direct provider fetch to reduce stale/cloud-cache mismatches.
        if let direct = try? await fetchWeatherDirect(lat: lat, lon: lon, locationLabel: "Current location") {
            return direct
        }
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent("api/weather"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon))
        ]
        guard let url = components?.url else { throw APIError.badURL }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return try await fetchWeatherDirect(lat: lat, lon: lon, locationLabel: "Current location")
            }
            let decoded = try decoder.decode(WeatherResponse.self, from: data)
            if decoded.success, let weather = decoded.weather {
                return weather
            }
            let message = decoded.message ?? "Weather unavailable."
            if isProviderBusyMessage(message) {
                return try await fetchWeatherDirect(lat: lat, lon: lon, locationLabel: "Current location")
            }
            throw APIError.server(message)
        } catch {
            return try await fetchWeatherDirect(lat: lat, lon: lon, locationLabel: "Current location")
        }
    }

    func fetchMarketChart(symbol: String, range: String) async throws -> MarketChart {
        if range == "1d" {
            // Prefer direct intraday bars for 1D so charts are not sparse/flat.
            if let intraday = try? await fetchMarketChartFromYahoo(symbol: symbol, interval: "15m", range: "1d"),
               !intraday.points.isEmpty {
                return intraday
            }
        }
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent("api/market-chart"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "_ts", value: String(Int(Date().timeIntervalSince1970)))
        ]
        guard let url = components?.url else { throw APIError.badURL }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                // Fall back to direct data source if backend is unavailable.
                return try await fetchMarketChartFromStooq(symbol: symbol, range: range)
            }
            let decoded = try decoder.decode(MarketChartResponse.self, from: data)
            if decoded.success, let chart = decoded.chart, !chart.points.isEmpty {
                return chart
            }
            if (decoded.message ?? "").localizedCaseInsensitiveContains("timed out") {
                return try await fetchMarketChartFromStooq(symbol: symbol, range: range)
            }
            throw APIError.server(decoded.message ?? "Chart unavailable.")
        } catch {
            return try await fetchMarketChartFromStooq(symbol: symbol, range: range)
        }
    }

    func subscribeEmail(_ email: String) async throws -> SubscribeResponse {
        let url = APIConfig.baseURL.appendingPathComponent("api/subscribe")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SubscribeRequest(email: email))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(SubscribeResponse.self, from: data)
    }

    func registerPushToken(
        token: String,
        subscriberEmail: String = "",
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.bigdavesnews.app",
        timezoneName: String = TimeZone.current.identifier
    ) async throws -> PushTokenResponse {
        let url = APIConfig.baseURL.appendingPathComponent("api/push/register-token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PushTokenRegisterRequest(
                deviceToken: token,
                platform: "ios",
                subscriberEmail: subscriberEmail,
                appBundleID: bundleID,
                timezoneName: timezoneName
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(PushTokenResponse.self, from: data)
    }

    func unregisterPushToken(token: String) async throws -> PushTokenResponse {
        let url = APIConfig.baseURL.appendingPathComponent("api/push/unregister-token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PushTokenUnregisterRequest(deviceToken: token, platform: "ios")
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(PushTokenResponse.self, from: data)
    }

    private func fetchMarketChartFromStooq(symbol: String, range: String) async throws -> MarketChart {
        var components = URLComponents(string: "https://stooq.com/q/d/l/")!
        components.queryItems = [
            URLQueryItem(name: "s", value: stooqSymbol(for: symbol)),
            URLQueryItem(name: "i", value: "d")
        ]
        guard let url = components.url else { throw APIError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.server("Market feed unavailable.")
        }
        guard let csv = String(data: data, encoding: .utf8) else {
            throw APIError.server("Invalid market feed format.")
        }
        let points = parseStooqCSV(csv, range: range)
        if points.isEmpty {
            throw APIError.server("No market data returned.")
        }
        return MarketChart(
            displayName: displayName(for: symbol),
            interval: "1d",
            points: points
        )
    }

    private func fetchMarketChartFromYahoo(symbol: String, interval: String, range: String) async throws -> MarketChart {
        let yahooSymbol = normalizeSymbol(symbol)
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(yahooSymbol)")!
        components.queryItems = [
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "range", value: range)
        ]
        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.server("Yahoo market feed unavailable.")
        }

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let chart = object?["chart"] as? [String: Any]
        let result = (chart?["result"] as? [[String: Any]])?.first
        guard let result else { throw APIError.server("Yahoo market feed unavailable.") }
        let timestamps = result["timestamp"] as? [Double] ?? []
        let indicators = result["indicators"] as? [String: Any]
        let quotes = indicators?["quote"] as? [[String: Any]]
        let quote = quotes?.first
        let closes = quote?["close"] as? [Double?] ?? []

        var points: [MarketPoint] = []
        for (idx, ts) in timestamps.enumerated() {
            guard idx < closes.count, let close = closes[idx] else { continue }
            let date = Date(timeIntervalSince1970: ts)
            points.append(MarketPoint(t: isoString(from: date), v: close))
        }
        if points.isEmpty { throw APIError.server("No market data returned.") }

        return MarketChart(
            displayName: displayName(for: symbol),
            interval: interval,
            points: points
        )
    }

    private func stooqSymbol(for symbol: String) -> String {
        let normalized = normalizeSymbol(symbol)
        if normalized == "^IXIC" { return "^ndq" }
        if normalized.hasPrefix("^") { return normalized.lowercased() }
        if normalized.contains(".") { return normalized.lowercased() }
        return "\(normalized.lowercased()).us"
    }

    private func normalizeSymbol(_ symbol: String) -> String {
        let raw = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if ["DOW", "DJI", "^DJI"].contains(raw) { return "^DJI" }
        if ["NASDAQ", "IXIC", "^IXIC", "NASDAC"].contains(raw) { return "^IXIC" }
        return raw
    }

    private func displayName(for symbol: String) -> String {
        switch normalizeSymbol(symbol) {
        case "^DJI":
            return "Dow Jones Industrial Average"
        case "^IXIC":
            return "NASDAQ Composite"
        default:
            return normalizeSymbol(symbol)
        }
    }

    private func parseStooqCSV(_ csv: String, range: String) -> [MarketPoint] {
        let lines = csv.split(whereSeparator: \.isNewline)
        guard lines.count > 1 else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        var parsed: [(date: Date, point: MarketPoint)] = []
        for line in lines.dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 5 else { continue }
            let dateRaw = String(cols[0])
            let closeRaw = String(cols[4])
            guard let d = formatter.date(from: dateRaw), let v = Double(closeRaw) else { continue }
            parsed.append((d, MarketPoint(t: isoString(from: d), v: v)))
        }
        guard !parsed.isEmpty else { return [] }
        parsed.sort { $0.date < $1.date }

        let filtered: [(date: Date, point: MarketPoint)]
        switch range {
        case "1d":
            // Stooq daily feed has no true intraday candles; use recent days
            // so 1D view still shows movement instead of a flat single point.
            filtered = filterByDays(parsed, days: 7)
        case "1w":
            filtered = filterByDays(parsed, days: 7)
        case "3mo":
            filtered = filterByDays(parsed, days: 90)
        case "6mo":
            filtered = filterByDays(parsed, days: 180)
        case "1y":
            filtered = filterByDays(parsed, days: 365)
        default:
            filtered = parsed
        }
        return filtered.map(\.point)
    }

    private func filterByDays(_ points: [(date: Date, point: MarketPoint)], days: Int) -> [(date: Date, point: MarketPoint)] {
        guard let latest = points.last?.date else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: latest) ?? latest
        return points.filter { $0.date >= start }
    }

    private func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func isProviderBusyMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("busy") || lower.contains("429") || lower.contains("too many requests") || lower.contains("timeout")
    }

    private struct OpenMeteoGeocodeResponse: Decodable {
        struct Result: Decodable {
            let latitude: Double
            let longitude: Double
            let name: String?
            let admin1: String?
            let countryCode: String?

            enum CodingKeys: String, CodingKey {
                case latitude
                case longitude
                case name
                case admin1
                case countryCode = "country_code"
            }
        }

        let results: [Result]?
    }

    private struct OpenMeteoForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature2m: Double?
            let weatherCode: Int?
            let windSpeed10m: Double?
            let time: String?

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case windSpeed10m = "wind_speed_10m"
                case time
            }
        }

        struct Hourly: Decodable {
            let time: [String]?
            let precipitationProbability: [Double]?
            let precipitation: [Double]?

            enum CodingKeys: String, CodingKey {
                case time
                case precipitationProbability = "precipitation_probability"
                case precipitation
            }
        }

        struct Daily: Decodable {
            let time: [String]?
            let weatherCode: [Int]?
            let tempMax: [Double]?
            let tempMin: [Double]?
            let precipMax: [Double]?

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case tempMax = "temperature_2m_max"
                case tempMin = "temperature_2m_min"
                case precipMax = "precipitation_probability_max"
            }
        }

        let latitude: Double?
        let longitude: Double?
        let current: Current?
        let hourly: Hourly?
        let daily: Daily?
    }

    private struct NOAAPointsResponse: Decodable {
        struct Properties: Decodable {
            let forecast: String?
            let forecastHourly: String?

            enum CodingKeys: String, CodingKey {
                case forecast
                case forecastHourly = "forecastHourly"
            }
        }

        let properties: Properties?
    }

    private struct NOAAForecastResponse: Decodable {
        struct Properties: Decodable {
            struct Period: Decodable {
                struct ProbabilityOfPrecipitation: Decodable {
                    let value: Double?
                }

                let name: String?
                let startTime: String?
                let isDaytime: Bool?
                let temperature: Double?
                let temperatureUnit: String?
                let windSpeed: String?
                let shortForecast: String?
                let probabilityOfPrecipitation: ProbabilityOfPrecipitation?
            }

            let updated: String?
            let periods: [Period]?
        }

        let properties: Properties?
    }

    private struct NOAAWeatherBundle {
        let currentTemperatureF: Double?
        let currentWindMPH: Double?
        let currentShortForecast: String?
        let observedAt: String?
        let forecast5Day: [ForecastDay]
        let alerts: [WeatherAlert]
    }

    private struct NOAAActiveAlertsResponse: Decodable {
        struct Feature: Decodable {
            let id: String?

            struct Properties: Decodable {
                let headline: String?
                let severity: String?
                let event: String?
                let effective: String?
                let ends: String?
                let description: String?
                let web: String?
                let uri: String?
            }

            let properties: Properties?
        }

        let features: [Feature]?
    }

    private func fetchWeatherFromWeatherKit(lat: Double, lon: Double, locationLabel: String) async throws -> WeatherSnapshot {
        let location = CLLocation(latitude: lat, longitude: lon)
        let weather = try await WeatherService.shared.weather(for: location)
        let current = weather.currentWeather

        let rain: [RainPoint] = Array(weather.hourlyForecast.forecast.prefix(12)).map { hour in
            let chancePercent = max(0.0, min(100.0, hour.precipitationChance * 100.0))
            return RainPoint(
                time: isoString(from: hour.date),
                precipitationProbability: chancePercent,
                precipitationIn: nil
            )
        }

        let forecast: [ForecastDay] = Array(weather.dailyForecast.forecast.prefix(5)).map { day in
            let chancePercent = max(0.0, min(100.0, day.precipitationChance * 100.0))
            return ForecastDay(
                date: isoDayString(from: day.date),
                weatherText: weatherTextFromCondition(day.condition),
                weatherIcon: weatherIconFromSymbolName(day.symbolName),
                tempMaxF: day.highTemperature.converted(to: .fahrenheit).value,
                tempMinF: day.lowTemperature.converted(to: .fahrenheit).value,
                precipitationProbabilityMax: chancePercent
            )
        }

        let alerts = await fetchUSWeatherAlerts(lat: lat, lon: lon)
        return WeatherSnapshot(
            locationLabel: locationLabel,
            temperatureF: current.temperature.converted(to: .fahrenheit).value,
            windMPH: current.wind.speed.converted(to: .milesPerHour).value,
            weatherText: weatherTextFromCondition(current.condition),
            weatherIcon: weatherIconFromSymbolName(current.symbolName),
            observedAt: isoString(from: current.date),
            latitude: lat,
            longitude: lon,
            mapURL: "https://www.windy.com/\(lat)/\(lon)?\(lat),\(lon),8",
            mapEmbedURL: "https://embed.windy.com/embed2.html?lat=\(lat)&lon=\(lon)&zoom=7&level=surface&overlay=radar&product=radar&menu=true&message=true&marker=true",
            alerts: alerts,
            rainTimeline: rain,
            forecast5Day: forecast
        )
    }

    private func fetchWeatherDirect(zipCode: String) async throws -> WeatherSnapshot {
        var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geo.queryItems = [
            URLQueryItem(name: "name", value: zipCode),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let geoURL = geo.url else { throw APIError.badURL }
        let (geoData, geoResponse) = try await URLSession.shared.data(from: geoURL)
        guard let geoHttp = geoResponse as? HTTPURLResponse, (200...299).contains(geoHttp.statusCode) else {
            throw APIError.server("Location lookup unavailable.")
        }
        let decodedGeo = try decoder.decode(OpenMeteoGeocodeResponse.self, from: geoData)
        guard let first = decodedGeo.results?.first else {
            throw APIError.server("Could not find that ZIP/location.")
        }
        let label = [first.name, first.admin1, first.countryCode].compactMap { $0 }.joined(separator: ", ")
        return try await fetchWeatherDirect(
            lat: first.latitude,
            lon: first.longitude,
            locationLabel: label.isEmpty ? zipCode : label
        )
    }

    private func fetchWeatherDirect(lat: Double, lon: Double, locationLabel: String) async throws -> WeatherSnapshot {
        // Primary path: Apple WeatherKit forecast on-device.
        if let weatherKitSnapshot = try? await fetchWeatherFromWeatherKit(lat: lat, lon: lon, locationLabel: locationLabel) {
            return weatherKitSnapshot
        }

        let noaaBundle = await fetchNOAAWeatherBundle(lat: lat, lon: lon)

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "precipitation_probability,precipitation"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_hours", value: "24"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { throw APIError.badURL }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            if let noaaBundle {
                return WeatherSnapshot(
                    locationLabel: locationLabel,
                    temperatureF: noaaBundle.currentTemperatureF ?? 0,
                    windMPH: noaaBundle.currentWindMPH ?? 0,
                    weatherText: noaaBundle.currentShortForecast ?? "Changing Conditions",
                    weatherIcon: weatherIconFromForecastText(noaaBundle.currentShortForecast ?? ""),
                    observedAt: noaaBundle.observedAt ?? isoString(from: Date()),
                    latitude: lat,
                    longitude: lon,
                    mapURL: "https://www.windy.com/\(lat)/\(lon)?\(lat),\(lon),8",
                    mapEmbedURL: "https://embed.windy.com/embed2.html?lat=\(lat)&lon=\(lon)&zoom=7&level=surface&overlay=radar&product=radar&menu=true&message=true&marker=true",
                    alerts: noaaBundle.alerts,
                    rainTimeline: [],
                    forecast5Day: noaaBundle.forecast5Day
                )
            }
            throw APIError.server("Weather provider unavailable.")
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let noaaBundle {
                return WeatherSnapshot(
                    locationLabel: locationLabel,
                    temperatureF: noaaBundle.currentTemperatureF ?? 0,
                    windMPH: noaaBundle.currentWindMPH ?? 0,
                    weatherText: noaaBundle.currentShortForecast ?? "Changing Conditions",
                    weatherIcon: weatherIconFromForecastText(noaaBundle.currentShortForecast ?? ""),
                    observedAt: noaaBundle.observedAt ?? isoString(from: Date()),
                    latitude: lat,
                    longitude: lon,
                    mapURL: "https://www.windy.com/\(lat)/\(lon)?\(lat),\(lon),8",
                    mapEmbedURL: "https://embed.windy.com/embed2.html?lat=\(lat)&lon=\(lon)&zoom=7&level=surface&overlay=radar&product=radar&menu=true&message=true&marker=true",
                    alerts: noaaBundle.alerts,
                    rainTimeline: [],
                    forecast5Day: noaaBundle.forecast5Day
                )
            }
            throw APIError.server("Weather provider unavailable.")
        }
        let payload = try decoder.decode(OpenMeteoForecastResponse.self, from: data)

        let code = payload.current?.weatherCode ?? 0
        let rainTimes = payload.hourly?.time ?? []
        let rainProbs = payload.hourly?.precipitationProbability ?? []
        let rainAmounts = payload.hourly?.precipitation ?? []
        let rain: [RainPoint] = Array(zip(rainTimes.indices, rainTimes).prefix(12)).map { idx, t in
            RainPoint(
                time: t,
                precipitationProbability: idx < rainProbs.count ? rainProbs[idx] : nil,
                precipitationIn: idx < rainAmounts.count ? rainAmounts[idx] : nil
            )
        }

        let dailyTimes = payload.daily?.time ?? []
        let dailyCodes = payload.daily?.weatherCode ?? []
        let dailyMax = payload.daily?.tempMax ?? []
        let dailyMin = payload.daily?.tempMin ?? []
        let dailyPrecip = payload.daily?.precipMax ?? []
        let forecast: [ForecastDay] = Array(zip(dailyTimes.indices, dailyTimes)).map { idx, day in
            let dayCode = idx < dailyCodes.count ? dailyCodes[idx] : 0
            return ForecastDay(
                date: day,
                weatherText: weatherText(for: dayCode),
                weatherIcon: weatherIcon(for: dayCode),
                tempMaxF: idx < dailyMax.count ? dailyMax[idx] : nil,
                tempMinF: idx < dailyMin.count ? dailyMin[idx] : nil,
                precipitationProbabilityMax: idx < dailyPrecip.count ? dailyPrecip[idx] : nil
            )
        }

        let alerts = (noaaBundle?.alerts.isEmpty == false) ? (noaaBundle?.alerts ?? []) : await fetchUSWeatherAlerts(lat: lat, lon: lon)
        let mergedForecast = (noaaBundle?.forecast5Day.isEmpty == false) ? (noaaBundle?.forecast5Day ?? forecast) : forecast
        let weatherTextValue = noaaBundle?.currentShortForecast ?? weatherText(for: code)
        let weatherIconValue = weatherIconFromForecastText(weatherTextValue)
        let temperatureValue = noaaBundle?.currentTemperatureF ?? payload.current?.temperature2m ?? 0
        let windValue = noaaBundle?.currentWindMPH ?? payload.current?.windSpeed10m ?? 0
        let observedValue = noaaBundle?.observedAt ?? payload.current?.time ?? isoString(from: Date())

        return WeatherSnapshot(
            locationLabel: locationLabel,
            temperatureF: temperatureValue,
            windMPH: windValue,
            weatherText: weatherTextValue,
            weatherIcon: weatherIconValue,
            observedAt: observedValue,
            latitude: payload.latitude ?? lat,
            longitude: payload.longitude ?? lon,
            mapURL: "https://www.windy.com/\(lat)/\(lon)?\(lat),\(lon),8",
            mapEmbedURL: "https://embed.windy.com/embed2.html?lat=\(lat)&lon=\(lon)&zoom=7&level=surface&overlay=radar&product=radar&menu=true&message=true&marker=true",
            alerts: alerts,
            rainTimeline: rain,
            forecast5Day: mergedForecast
        )
    }

    private func fetchNOAAWeatherBundle(lat: Double, lon: Double) async -> NOAAWeatherBundle? {
        guard isLikelyUSCoordinate(lat: lat, lon: lon) else { return nil }
        guard let pointsURL = URL(string: "https://api.weather.gov/points/\(lat),\(lon)") else { return nil }

        var pointsRequest = URLRequest(url: pointsURL)
        pointsRequest.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        pointsRequest.setValue("BigDavesNewsApp/1.0 (iOS weather)", forHTTPHeaderField: "User-Agent")

        do {
            let (pointsData, pointsResponse) = try await URLSession.shared.data(for: pointsRequest)
            guard let pointsHTTP = pointsResponse as? HTTPURLResponse, (200...299).contains(pointsHTTP.statusCode) else {
                return nil
            }
            let points = try decoder.decode(NOAAPointsResponse.self, from: pointsData)
            guard
                let forecastURL = points.properties?.forecast, !forecastURL.isEmpty,
                let hourlyURL = points.properties?.forecastHourly, !hourlyURL.isEmpty
            else {
                return nil
            }

            async let forecastPeriodsTask = fetchNOAAForecastPeriods(urlString: forecastURL)
            async let hourlyPeriodsTask = fetchNOAAForecastPeriods(urlString: hourlyURL)
            async let alertsTask = fetchUSWeatherAlerts(lat: lat, lon: lon)

            let forecastPeriods = (try? await forecastPeriodsTask) ?? []
            let hourlyPeriods = (try? await hourlyPeriodsTask) ?? []
            let alerts = await alertsTask

            let forecastDays = buildNOAAForecastDays(from: forecastPeriods)
            let currentPeriod = currentNOAAPeriod(from: hourlyPeriods)

            return NOAAWeatherBundle(
                currentTemperatureF: temperatureF(from: currentPeriod?.temperature, unit: currentPeriod?.temperatureUnit),
                currentWindMPH: mphValue(from: currentPeriod?.windSpeed),
                currentShortForecast: currentPeriod?.shortForecast,
                observedAt: currentPeriod?.startTime,
                forecast5Day: forecastDays,
                alerts: alerts
            )
        } catch {
            return nil
        }
    }

    private func fetchNOAAForecastPeriods(urlString: String) async throws -> [NOAAForecastResponse.Properties.Period] {
        guard let url = URL(string: urlString) else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.setValue("BigDavesNewsApp/1.0 (iOS weather)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.server("NOAA forecast unavailable.")
        }
        let decoded = try decoder.decode(NOAAForecastResponse.self, from: data)
        return decoded.properties?.periods ?? []
    }

    private func currentNOAAPeriod(from periods: [NOAAForecastResponse.Properties.Period]) -> NOAAForecastResponse.Properties.Period? {
        let now = Date()
        let sorted = periods
            .compactMap { period -> (NOAAForecastResponse.Properties.Period, Date)? in
                guard let start = dateFromISO(period.startTime) else { return nil }
                return (period, start)
            }
            .sorted { $0.1 < $1.1 }
        if let upcoming = sorted.first(where: { $0.1 >= now })?.0 {
            return upcoming
        }
        return sorted.last?.0
    }

    private func buildNOAAForecastDays(from periods: [NOAAForecastResponse.Properties.Period]) -> [ForecastDay] {
        var byDay: [String: [NOAAForecastResponse.Properties.Period]] = [:]
        for period in periods {
            guard let start = dateFromISO(period.startTime) else { continue }
            let key = isoDayString(from: start)
            byDay[key, default: []].append(period)
        }

        let sortedKeys = byDay.keys.sorted()
        var result: [ForecastDay] = []
        for key in sortedKeys {
            guard let dayPeriods = byDay[key], !dayPeriods.isEmpty else { continue }
            let representative = dayPeriods.first(where: { $0.isDaytime == true }) ?? dayPeriods.first
            let short = representative?.shortForecast?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Changing Conditions"
            let temps = dayPeriods.compactMap { temperatureF(from: $0.temperature, unit: $0.temperatureUnit) }
            let maxTemp = temps.max()
            let minTemp = temps.min()
            let precipMax = dayPeriods.compactMap { $0.probabilityOfPrecipitation?.value }.max()
            result.append(
                ForecastDay(
                    date: key,
                    weatherText: short,
                    weatherIcon: weatherIconFromForecastText(short),
                    tempMaxF: maxTemp,
                    tempMinF: minTemp,
                    precipitationProbabilityMax: precipMax
                )
            )
        }
        return Array(result.prefix(7))
    }

    private func weatherIconFromForecastText(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("thunder") || lower.contains("t-storm") || lower.contains("storm") { return "⛈️" }
        if lower.contains("snow") || lower.contains("flurr") || lower.contains("sleet") { return "❄️" }
        if lower.contains("rain") || lower.contains("shower") || lower.contains("drizzle") { return "🌧️" }
        if lower.contains("fog") || lower.contains("haze") || lower.contains("smoke") { return "🌫️" }
        if lower.contains("cloud") || lower.contains("overcast") { return "⛅" }
        if lower.contains("sun") || lower.contains("clear") || lower.contains("fair") { return "☀️" }
        return "🌤️"
    }

    private func weatherIconFromSymbolName(_ symbol: String) -> String {
        let lower = symbol.lowercased()
        if lower.contains("cloud.bolt") || lower.contains("thunder") { return "⛈️" }
        if lower.contains("snow") || lower.contains("sleet") || lower.contains("hail") { return "❄️" }
        if lower.contains("rain") || lower.contains("drizzle") || lower.contains("shower") { return "🌧️" }
        if lower.contains("fog") || lower.contains("smoke") || lower.contains("haze") { return "🌫️" }
        if lower.contains("cloud") { return "⛅" }
        if lower.contains("sun") || lower.contains("clear") || lower.contains("moon") { return "☀️" }
        return "🌤️"
    }

    private func weatherTextFromCondition(_ condition: WeatherCondition) -> String {
        String(describing: condition)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func temperatureF(from value: Double?, unit: String?) -> Double? {
        guard let value else { return nil }
        let key = (unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if key == "F" || key.isEmpty { return value }
        if key == "C" { return (value * 9.0 / 5.0) + 32.0 }
        return value
    }

    private func mphValue(from raw: String?) -> Double? {
        guard let raw else { return nil }
        let numbers = raw
            .split { !($0.isNumber || $0 == ".") }
            .compactMap { Double($0) }
        guard !numbers.isEmpty else { return nil }
        if numbers.count == 1 { return numbers[0] }
        return (numbers[0] + numbers[1]) / 2.0
    }

    private func dateFromISO(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: raw) {
            return parsed
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private func isoDayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func fetchUSWeatherAlerts(lat: Double, lon: Double) async -> [WeatherAlert] {
        guard isLikelyUSCoordinate(lat: lat, lon: lon) else { return [] }
        var components = URLComponents(string: "https://api.weather.gov/alerts/active")!
        components.queryItems = [URLQueryItem(name: "point", value: "\(lat),\(lon)")]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.setValue("BigDavesNewsApp/1.0 (iOS weather alerts)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
            let payload = try decoder.decode(NOAAActiveAlertsResponse.self, from: data)
            let mapped: [WeatherAlert] = (payload.features ?? []).compactMap { feature in
                guard let props = feature.properties else { return nil }
                let headline = (props.headline ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let event = (props.event ?? "Weather Alert").trimmingCharacters(in: .whitespacesAndNewlines)
                let severity = (props.severity ?? "Unknown").trimmingCharacters(in: .whitespacesAndNewlines)
                let description = (props.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if headline.isEmpty && description.isEmpty {
                    return nil
                }
                return WeatherAlert(
                    headline: headline.isEmpty ? event : headline,
                    severity: severity,
                    event: event,
                    effective: props.effective,
                    ends: props.ends,
                    description: description,
                    url: preferredNOAAAlertURL(web: props.web, uri: props.uri, featureID: feature.id)
                )
            }
            return mapped.sorted { lhs, rhs in
                severityRank(lhs.severity) < severityRank(rhs.severity)
            }
        } catch {
            return []
        }
    }

    private func isLikelyUSCoordinate(lat: Double, lon: Double) -> Bool {
        // Broad US bounds, including Alaska/Hawaii longitudes.
        lat >= 18.0 && lat <= 72.0 && lon >= -179.0 && lon <= -66.0
    }

    private func severityRank(_ raw: String) -> Int {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.contains("extreme") { return 0 }
        if key.contains("severe") { return 1 }
        if key.contains("moderate") { return 2 }
        if key.contains("minor") { return 3 }
        return 4
    }

    private func preferredNOAAAlertURL(web: String?, uri: String?, featureID: String?) -> String? {
        let candidates = [web, uri, featureID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && URL(string: $0) != nil }

        // Prefer human-readable Weather.gov pages and avoid JSON API endpoints.
        if let weatherGovDetail = candidates.first(where: {
            let lower = $0.lowercased()
            return lower.contains("weather.gov")
                && !lower.contains("api.weather.gov")
                && !isGenericNOAAHomePage(lower)
        }) {
            return weatherGovDetail
        }
        if let noaaDetail = candidates.first(where: {
            let lower = $0.lowercased()
            return lower.contains("noaa.gov") && !isGenericNOAAHomePage(lower)
        }) {
            return noaaDetail
        }
        return nil
    }

    private func isGenericNOAAHomePage(_ lowerURL: String) -> Bool {
        lowerURL == "https://www.noaa.gov"
            || lowerURL == "https://noaa.gov"
            || lowerURL == "https://www.weather.gov"
            || lowerURL == "https://weather.gov"
            || lowerURL == "https://www.weather.gov/"
            || lowerURL == "https://weather.gov/"
    }

    private func weatherText(for code: Int) -> String {
        switch code {
        case 0: return "Clear Sky"
        case 1: return "Mainly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 61, 63, 65, 80: return "Rain"
        case 71, 73, 75: return "Snow"
        case 95: return "Thunderstorm"
        default: return "Changing Conditions"
        }
    }

    private func weatherIcon(for code: Int) -> String {
        switch code {
        case 0: return "☀️"
        case 1, 2, 3: return "⛅"
        case 45, 48: return "🌫️"
        case 51, 53, 55, 61, 63, 65, 80: return "🌧️"
        case 71, 73, 75: return "❄️"
        case 95: return "⛈️"
        default: return "🌤️"
        }
    }
}
