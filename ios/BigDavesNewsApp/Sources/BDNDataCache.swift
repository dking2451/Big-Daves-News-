import Foundation

/// File-backed cache for raw API response payloads.
/// Raw JSON Data is written to the app's Caches directory; timestamps live alongside.
/// Thread-safe for concurrent reads; writes are fire-and-forget background I/O.
enum BDNDataCache {

    // MARK: - Keys

    enum Keys {
        static let facts    = "bdn.facts"
        static let watch    = "bdn.watch"
        static let sports   = "bdn.sports"
        static let weather  = "bdn.weather"
        static func localNews(zip: String) -> String { "bdn.localnews.\(zip)" }
    }

    // MARK: - Directory

    private static let dir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = caches.appendingPathComponent("BDNAPICache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func dataURL(for key: String) -> URL {
        dir.appendingPathComponent(sanitize(key) + ".dat")
    }

    private static func tsURL(for key: String) -> URL {
        dir.appendingPathComponent(sanitize(key) + ".ts")
    }

    private static func sanitize(_ key: String) -> String {
        key.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
    }

    // MARK: - Read / Write

    /// Persist raw payload data and record the current timestamp.
    static func save(_ data: Data, for key: String) {
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: dataURL(for: key), options: .atomic)
            if let tsData = try? JSONEncoder().encode(Date().timeIntervalSince1970) {
                try? tsData.write(to: tsURL(for: key), options: .atomic)
            }
        }
    }

    /// Persist an Encodable value (e.g. a decoded model) directly.
    static func saveEncodable<T: Encodable>(_ value: T, for key: String) {
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(value) {
                try? data.write(to: dataURL(for: key), options: .atomic)
            }
            if let tsData = try? JSONEncoder().encode(Date().timeIntervalSince1970) {
                try? tsData.write(to: tsURL(for: key), options: .atomic)
            }
        }
    }

    /// Load raw cached payload data, or nil if nothing is stored.
    static func load(for key: String) -> Data? {
        try? Data(contentsOf: dataURL(for: key))
    }

    /// Load and decode a cached Decodable value, or nil on any failure.
    static func loadDecodable<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let data = load(for: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Age helpers

    static func timestamp(for key: String) -> Date? {
        guard let tsData = try? Data(contentsOf: tsURL(for: key)),
              let ts = try? JSONDecoder().decode(Double.self, from: tsData) else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    /// Human-readable age string, e.g. "just now", "12m ago", "3h ago".
    static func ageLabel(for key: String) -> String? {
        guard let ts = timestamp(for: key) else { return nil }
        let elapsed = Int(-ts.timeIntervalSinceNow)
        if elapsed < 120  { return "just now" }
        if elapsed < 3600 { return "\(elapsed / 60)m ago" }
        if elapsed < 86400 { return "\(elapsed / 3600)h ago" }
        return "\(elapsed / 86400)d ago"
    }
}
