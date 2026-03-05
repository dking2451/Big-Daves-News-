import SwiftUI

@main
struct BigDavesNewsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    if UserDefaults.standard.bool(forKey: "bdn-reminder-enabled-ios") {
                        PushTokenManager.shared.requestSystemTokenRegistration()
                        await PushTokenManager.shared.registerWithBackendIfPossible()
                    }
                }
        }
    }
}
