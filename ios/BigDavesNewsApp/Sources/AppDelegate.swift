import Foundation
import UIKit
import UserNotifications
#if os(iOS)
import BackgroundTasks
#endif

enum NotificationBadgeManager {
    @MainActor
    static func clearAll() {
        clearAll(application: UIApplication.shared)
    }

    @MainActor
    static func clearAll(application: UIApplication) {
        application.applicationIconBadgeNumber = 0
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        if #available(iOS 16.0, *) {
            center.setBadgeCount(0)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if os(iOS)
        // BGTask handlers must be registered before this method returns.
        BackgroundRefreshManager.registerHandlers()
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await PushTokenManager.shared.handleRegisteredDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushTokenManager.shared.handleRegistrationFailure(error)
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        NotificationBadgeManager.clearAll(application: application)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NotificationBadgeManager.clearAll()
        }
        await APIClient.shared.trackEvent(
            deviceID: WatchDeviceIdentity.current,
            eventName: "push_open",
            eventProps: [
                "identifier": response.notification.request.identifier,
                "deep_link": ((response.notification.request.content.userInfo["deep_link"] as? String) ?? "").lowercased()
            ]
        )
        let userInfo = response.notification.request.content.userInfo
        let deepLink = (userInfo["deep_link"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if deepLink == "sports" {
            await APIClient.shared.trackEvent(
                deviceID: WatchDeviceIdentity.current,
                eventName: "sports_alert_open",
                eventProps: [
                    "alert_type": (userInfo["alert_type"] as? String) ?? "unknown",
                    "event_id": (userInfo["event_id"] as? String) ?? ""
                ]
            )
        }
        if deepLink == "brief" {
            await MainActor.run {
                AppNavigationState.shared.openBrief()
            }
        } else if deepLink == "watch" {
            await MainActor.run {
                AppNavigationState.shared.openWatch()
            }
        } else if deepLink == "sports" {
            await MainActor.run {
                AppNavigationState.shared.openSports()
            }
        }
    }
}
