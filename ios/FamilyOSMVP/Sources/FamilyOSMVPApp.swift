import SwiftUI
import UIKit
import UserNotifications

@main
struct FamilyOSMVPApp: App {
    @UIApplicationDelegateAdaptor(FamilyOSAppDelegate.self) private var appDelegate

    @StateObject private var store = EventStore()

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environmentObject(store)
        }
    }
}

/// Delivers URL opens through `NotificationCenter` so `RootContentView` can consume the Share Extension handoff
/// even when SwiftUI `onOpenURL` does not run (common when returning from a share extension while the app was suspended).
/// Also handles the “Import ready” local notification tap (badge + deep link when share does not foreground the app).
final class FamilyOSAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.scheme == "familyosmvp" else { return false }
        NotificationCenter.default.post(name: .familyOSOpenImportURL, object: url)
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if ShareImportNotifier.isImportReadyNotification(notification) {
            completionHandler([.banner, .badge, .sound])
        } else {
            completionHandler([])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard ShareImportNotifier.isImportReadyNotification(response.notification),
              let url = ShareImportNotifier.deeplinkURL(from: response.notification)
        else { return }
        NotificationCenter.default.post(name: .familyOSOpenImportURL, object: url)
    }
}
