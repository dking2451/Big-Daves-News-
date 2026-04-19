import Foundation
import UserNotifications

/// Manages the user's opt-in preference for remote breaking-news push notifications.
/// When enabled, the APNs device token is synced to the backend with a `breaking_news_alerts: true`
/// flag so the server knows to send breaking-news pushes to this device.
@MainActor
final class BreakingNewsNotificationManager: ObservableObject {
    static let shared = BreakingNewsNotificationManager()

    @Published var alertsEnabled: Bool
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let alertsEnabledKey = "bdn-breaking-news-alerts-enabled-ios"

    private init() {
        alertsEnabled = UserDefaults.standard.bool(forKey: "bdn-breaking-news-alerts-enabled-ios")
    }

    // MARK: - Public API

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func updateAlertsEnabled(_ enabled: Bool) async {
        if enabled {
            // 1. Request notification permission if not already granted.
            let center = UNUserNotificationCenter.current()
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            guard granted == true else {
                alertsEnabled = false
                persist()
                return
            }
            // 2. Make sure we have an APNs token (no-op if already registered).
            PushTokenManager.shared.requestSystemTokenRegistration()
            alertsEnabled = true
            persist()
            await syncWithBackend(enabled: true)
            await trackEvent("breaking_news_alerts_enabled", props: ["enabled": "true"])
        } else {
            alertsEnabled = false
            persist()
            await syncWithBackend(enabled: false)
            await trackEvent("breaking_news_alerts_enabled", props: ["enabled": "false"])
        }
    }

    // MARK: - Private

    private func syncWithBackend(enabled: Bool) async {
        let token = PushTokenManager.shared.deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        do {
            try await APIClient.shared.setBreakingNewsAlerts(deviceToken: token, enabled: enabled)
        } catch {
            // Best-effort — local preference is saved; retry happens on next toggle or app launch.
        }
    }

    private func persist() {
        UserDefaults.standard.set(alertsEnabled, forKey: alertsEnabledKey)
    }

    private func trackEvent(_ name: String, props: [String: String]) async {
        await APIClient.shared.trackEvent(
            deviceID: WatchDeviceIdentity.current,
            eventName: name,
            eventProps: props
        )
    }
}
