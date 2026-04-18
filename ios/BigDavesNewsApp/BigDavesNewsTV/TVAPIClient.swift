import Foundation

enum TVAPIConfig {
    static let baseURL = URL(string: "https://big-daves-news-web.onrender.com")!
}

enum TVAPIError: Error {
    case badStatus(Int)
    case decode
    case empty
}

actor TVAPIClient {
    static let shared = TVAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchProfile(userId: String) async throws -> ComposedUserProfile {
        var comp = URLComponents(url: TVAPIConfig.baseURL.appendingPathComponent("api/user/profile"), resolvingAgainstBaseURL: false)!
        comp.queryItems = [URLQueryItem(name: "user_id", value: userId)]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw TVAPIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        struct Envelope: Decodable {
            let success: Bool?
            let profile: ComposedUserProfile?
        }
        let env = try decoder.decode(Envelope.self, from: data)
        guard env.success != false, let p = env.profile else {
            throw TVAPIError.decode
        }
        return p
    }

    /// Fire-and-forget friendly: encodes `patch` as JSON object under `patch` key.
    func patchProfile(userId: String, patch: [String: Any]) async throws -> ComposedUserProfile {
        var req = URLRequest(url: TVAPIConfig.baseURL.appendingPathComponent("api/user/profile"))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["user_id": userId, "patch": patch]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw TVAPIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        struct Envelope: Decodable {
            let success: Bool?
            let profile: ComposedUserProfile?
        }
        let env = try decoder.decode(Envelope.self, from: data)
        guard env.success != false, let p = env.profile else {
            throw TVAPIError.decode
        }
        return p
    }

    func fetchWatchShows(userId: String, limit: Int = 40, minimumCount: Int = 28) async throws -> [TVWatchShowItem] {
        var comp = URLComponents(url: TVAPIConfig.baseURL.appendingPathComponent("api/watch"), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "device_id", value: userId),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "minimum_count", value: String(minimumCount)),
            URLQueryItem(name: "hide_seen", value: "true"),
            URLQueryItem(name: "only_saved", value: "false"),
        ]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw TVAPIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try decoder.decode(TVWatchShowsResponse.self, from: data)
        return decoded.items
    }

    /// Saved list only: `only_saved=true`, `hide_seen=false` so finished titles still appear for the Finished rail.
    func fetchWatchShowsMyList(userId: String, limit: Int = 50, minimumCount: Int = 24) async throws -> [TVWatchShowItem] {
        var comp = URLComponents(url: TVAPIConfig.baseURL.appendingPathComponent("api/watch"), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "device_id", value: userId),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "minimum_count", value: String(minimumCount)),
            URLQueryItem(name: "hide_seen", value: "false"),
            URLQueryItem(name: "only_saved", value: "true"),
        ]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw TVAPIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try decoder.decode(TVWatchShowsResponse.self, from: data)
        return decoded.items
    }

    /// `/api/sports/now` — `include_ocho` stays off for tvOS (Ocho uses separate styling on iOS).
    func fetchSportsNow(
        deviceId: String,
        windowHours: Int = 12,
        timezoneName: String = TimeZone.current.identifier,
        providerKey: String = "",
        availabilityOnly: Bool = false,
        includeOcho: Bool = false
    ) async throws -> [TVSportsEventItem] {
        let boundedHours = max(1, min(windowHours, 12))
        var comp = URLComponents(url: TVAPIConfig.baseURL.appendingPathComponent("api/sports/now"), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "window_hours", value: String(boundedHours)),
            URLQueryItem(name: "timezone_name", value: timezoneName),
            URLQueryItem(name: "provider_key", value: providerKey),
            URLQueryItem(name: "availability_only", value: availabilityOnly ? "true" : "false"),
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "include_ocho", value: includeOcho ? "true" : "false"),
        ]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw TVAPIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try decoder.decode(TVSportsNowResponse.self, from: data)
        guard decoded.success else {
            throw TVAPIError.empty
        }
        return decoded.items
    }
}
