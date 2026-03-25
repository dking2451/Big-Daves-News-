import Foundation
import UserNotifications

/// Local notification + badge when the Share Extension saves a handoff but the host app may not come to the foreground.
enum ShareImportNotifier {
    static let notificationIdentifier = "com.familyos.mvp.shareImportReady"
    private static let deeplinkUserInfoKey = "familyOSDeeplink"

    /// Schedules a short-delayed alert so a fast open + `ShareHandoff.consume()` can cancel before anything is shown.
    static func scheduleImportReadyNotification() async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if !granted { return }
            } catch {
                return
            }
            status = await center.notificationSettings().authorizationStatus
        }
        switch status {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied, .notDetermined:
            return
        @unknown default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Import ready"
        content.body = "Tap to review what you shared into Family OS."
        content.sound = .default
        content.userInfo = [deeplinkUserInfoKey: "familyosmvp://import"]
        content.badge = NSNumber(value: 1)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.25, repeats: false)
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            // Best-effort only
        }
    }

    /// Removes the pending/delivered import nudge and clears the app icon badge once the user is in the import flow.
    static func clearImportReadyNotificationForHandledShare() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
        Task {
            if #available(iOS 17.0, *) {
                try? await center.setBadgeCount(0)
            }
        }
    }

    static func deeplinkURL(from notification: UNNotification) -> URL? {
        guard isImportReadyNotification(notification) else { return nil }
        guard let s = notification.request.content.userInfo[deeplinkUserInfoKey] as? String else { return nil }
        return URL(string: s)
    }

    static func isImportReadyNotification(_ notification: UNNotification) -> Bool {
        notification.request.identifier == notificationIdentifier
    }
}
