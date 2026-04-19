#if os(iOS)
import BackgroundTasks
import Foundation

/// Manages BGAppRefreshTask registration and scheduling for pre-fetching
/// headlines and sports status while the app is backgrounded.
enum BackgroundRefreshManager {
    static let refreshTaskID = "com.bigdavesnews.app.refresh"

    // MARK: - Registration (call before app finishes launching)

    /// Register BGTask handlers. Must be called inside
    /// `application(_:didFinishLaunchingWithOptions:)` — before it returns.
    static func registerHandlers() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskID,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleRefresh(task: refreshTask)
        }
    }

    // MARK: - Scheduling

    /// Submit the next background refresh request.
    /// Call when the app moves to the `.background` scene phase.
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        // Earliest start: 30 minutes — iOS may delay longer based on usage patterns.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch BGTaskScheduler.Error.notPermitted {
            // Background refresh capability not enabled — no-op.
        } catch {
            // Ignore other scheduling errors (e.g. too many tasks pending).
        }
    }

    // MARK: - Task handler

    private static func handleRefresh(task: BGAppRefreshTask) {
        // Immediately queue the next cycle so we stay in rotation.
        scheduleAppRefresh()

        let workTask = Task {
            do {
                // Fetch fresh headlines.
                let claims = try await APIClient.shared.fetchFacts()

                // Update the "NEW" badge state.
                await HeadlinesBadgeState.shared.didRefresh(topClaimID: claims.first?.id)

                // Re-index top headlines in Spotlight.
                await SpotlightIndexer.indexClaims(claims)

                // Refresh live sports status (non-throwing).
                await SportsLiveStatus.shared.refreshIfNeeded(force: false)

                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        // iOS gives us a finite window — cancel gracefully if time runs out.
        task.expirationHandler = {
            workTask.cancel()
        }
    }
}

#endif
