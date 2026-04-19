#if os(iOS)
import AppIntents
import Foundation

// MARK: - Focus Filter

/// Lets users customize Big Dave's News behavior when a Focus mode is active.
/// Appears in Settings > Focus > [Focus Name] > Apps > Big Dave's News.
struct BDNFocusFilter: SetFocusFilterIntent {

    static var title: LocalizedStringResource = "Big Daves News"

    // Explicit conformance to InstanceDisplayRepresentable (inherited via AppIntent).
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Big Daves News Filter")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Big Daves News")
    }

    /// When false, sports score push alerts are suppressed while Focus is on.
    @Parameter(title: "Show Sports Alerts", default: true)
    var showSportsAlerts: Bool

    /// When true, the NEW badge on the Headlines tab is hidden during Focus.
    @Parameter(title: "Hide New Stories Badge", default: false)
    var hideNewStoriesBadge: Bool

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(showSportsAlerts, forKey: BDNFocusSettings.sportsAlertsKey)
        UserDefaults.standard.set(hideNewStoriesBadge, forKey: BDNFocusSettings.hideBadgeKey)
        return .result()
    }
}

// MARK: - Settings store

/// Shared keys for reading Focus Filter preferences throughout the app.
enum BDNFocusSettings {
    static let sportsAlertsKey = "bdn-focus-sports-alerts-enabled"
    static let hideBadgeKey    = "bdn-focus-hide-new-badge"

    static var sportsAlertsEnabled: Bool {
        UserDefaults.standard.object(forKey: sportsAlertsKey) as? Bool ?? true
    }

    static var newStoriesBadgeHidden: Bool {
        UserDefaults.standard.bool(forKey: hideBadgeKey)
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: sportsAlertsKey)
        UserDefaults.standard.removeObject(forKey: hideBadgeKey)
    }
}
#endif
