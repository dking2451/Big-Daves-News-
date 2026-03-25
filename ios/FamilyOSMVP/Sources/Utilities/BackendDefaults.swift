import Foundation

enum BackendDefaults {
    static let localSimulatorURL = "http://127.0.0.1:8000"
    /// Must match your **live** Render Web Service URL (dashboard → service → copy URL). If `/health` returns 404, deploy `backend/family-os-mvp-api` or update this string.
    static let renderURL = "https://family-os-mvp.onrender.com"

    /// Default for `AppStorage("backendURL")`. Use production so **physical devices** work without manual setup; simulators can switch to localhost in Settings.
    static let defaultBackendURL = renderURL

    /// True when the URL points at this device (`127.0.0.1` / `localhost`) — only works on Simulator or with a LAN IP to a dev machine.
    static func isLocalhostBackendURL(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("127.0.0.1") || lower.contains("localhost")
    }
}
