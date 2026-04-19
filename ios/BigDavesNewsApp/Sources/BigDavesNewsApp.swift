import SwiftUI
import Foundation
#if os(iOS)
import CoreSpotlight
#endif

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
                    switch phase {
                    case .active:
                        Task { @MainActor in
                            NotificationBadgeManager.clearAll()
                        }
                        Task {
                            await SportsLiveStatus.shared.refreshIfNeeded(force: true)
                            await SportsAlertsManager.shared.refreshScheduledAlerts()
                        }
                    case .background:
                        #if os(iOS)
                        BackgroundRefreshManager.scheduleAppRefresh()
                        #endif
                    default:
                        break
                    }
                }
                #if os(iOS)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                    let tab = SpotlightIndexer.resolveTab(from: id)
                    AppNavigationState.shared.selectedTab = tab
                }
                #endif
        }
    }
}
