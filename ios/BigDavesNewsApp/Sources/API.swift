import Foundation

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

struct WeatherResponse: Decodable {
    let success: Bool
    let message: String?
    let weather: WeatherSnapshot?
}

struct WeatherSnapshot: Decodable {
    let locationLabel: String
    let temperatureF: Double
    let windMPH: Double
    let weatherText: String
    let weatherIcon: String
    let observedAt: String

    enum CodingKeys: String, CodingKey {
        case locationLabel = "location_label"
        case temperatureF = "temperature_f"
        case windMPH = "wind_mph"
        case weatherText = "weather_text"
        case weatherIcon = "weather_icon"
        case observedAt = "observed_at"
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

    func fetchWeather(zipCode: String) async throws -> WeatherSnapshot {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent("api/weather"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "zip_code", value: zipCode)]
        guard let url = components?.url else { throw APIError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        let decoded = try decoder.decode(WeatherResponse.self, from: data)
        if decoded.success, let weather = decoded.weather {
            return weather
        }
        throw APIError.server(decoded.message ?? "Weather unavailable.")
    }

    func fetchMarketChart(symbol: String, range: String) async throws -> MarketChart {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent("api/market-chart"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "_ts", value: String(Int(Date().timeIntervalSince1970)))
        ]
        guard let url = components?.url else { throw APIError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        let decoded = try decoder.decode(MarketChartResponse.self, from: data)
        if decoded.success, let chart = decoded.chart {
            return chart
        }
        throw APIError.server(decoded.message ?? "Chart unavailable.")
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
}
