import Foundation

extension FamilyEvent {
    /// URL for Apple Maps directions; prefers stored coordinates when present and valid.
    func mapsDirectionsURL() -> URL? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lat = locationLatitude, let lon = locationLongitude,
           lat.isFinite, lon.isFinite,
           lat >= -90, lat <= 90, lon >= -180, lon <= 180
        {
            let s = String(format: "%.6f,%.6f", lat, lon)
            return URL(string: "http://maps.apple.com/?daddr=\(s)&dirflg=d")
        }
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "http://maps.apple.com/?daddr=\(encoded)&dirflg=d")
    }
}
