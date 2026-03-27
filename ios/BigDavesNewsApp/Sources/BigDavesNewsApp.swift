import SwiftUI
import Foundation

@main
struct BigDavesNewsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Larger HTTP cache for Watch/TMDB poster URLs (AsyncImage uses URLSession.shared).
        let memory = 32 * 1024 * 1024
        let disk = 200 * 1024 * 1024
        URLCache.shared = URLCache(
            memoryCapacity: memory,
            diskCapacity: disk,
            directory: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    await MainActor.run {
                        NotificationBadgeManager.clearAll()
                    }
                    if DailyHabitNotificationManager.shared.habitNotificationsEnabled {
                        PushTokenManager.shared.requestSystemTokenRegistration()
                        await PushTokenManager.shared.registerWithBackendIfPossible()
                    }
                    await SportsLiveStatus.shared.refreshIfNeeded(force: true)
                    await SportsAlertsManager.shared.refreshScheduledAlerts()
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task { @MainActor in
                        NotificationBadgeManager.clearAll()
                    }
                    Task {
                        await SportsLiveStatus.shared.refreshIfNeeded(force: true)
                        await SportsAlertsManager.shared.refreshScheduledAlerts()
                    }
                }
        }
    }
}
