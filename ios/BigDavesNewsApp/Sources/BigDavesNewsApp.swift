import SwiftUI

@main
struct BigDavesNewsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    await MainActor.run {
                        NotificationBadgeManager.clearAll()
                    }
                    if UserDefaults.standard.bool(forKey: "bdn-reminder-enabled-ios") {
                        PushTokenManager.shared.requestSystemTokenRegistration()
                        await PushTokenManager.shared.registerWithBackendIfPossible()
                    }
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task { @MainActor in
                        NotificationBadgeManager.clearAll()
                    }
                }
        }
    }
}
