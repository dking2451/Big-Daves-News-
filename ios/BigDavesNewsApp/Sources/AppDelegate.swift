import Foundation
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
        clearNotificationIndicators(application: application)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            clearNotificationIndicators(application: UIApplication.shared)
        }
        let userInfo = response.notification.request.content.userInfo
        let deepLink = (userInfo["deep_link"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if deepLink == "brief" {
            await MainActor.run {
                AppNavigationState.shared.openBrief()
            }
        }
    }

    @MainActor
    private func clearNotificationIndicators(application: UIApplication) {
        application.applicationIconBadgeNumber = 0
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        if #available(iOS 16.0, *) {
            center.setBadgeCount(0)
        }
    }
}
