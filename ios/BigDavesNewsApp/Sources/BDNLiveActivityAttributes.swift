#if os(iOS)
import ActivityKit
import Foundation

// MARK: - Live Activity Attributes
// Shared data contract between the main app (starts/updates) and the widget extension (renders).
// The identical struct is redefined in BDNWidget/BDNLiveActivityView.swift for the extension process.

struct BDNLiveActivityAttributes: ActivityAttributes {
    public typealias BDNLiveActivityState = ContentState

    public struct ContentState: Codable, Hashable {
        var homeScore: String
        var awayScore: String
        var statusDisplay: String  // "Q3 7:42", "7th Inning", "2nd Period", etc.
        var isLive: Bool
        var isFinal: Bool
        var network: String
    }

    // Static — set at start, never changes
    var eventID: String
    var league: String
    var homeTeam: String
    var awayTeam: String
    var sport: String
}

// MARK: - Sports Live Activity Manager

@available(iOS 16.2, *)
@MainActor
final class SportsLiveActivityManager {
    static let shared = SportsLiveActivityManager()
    private init() {}

    // Maps eventID -> active Activity
    private var activities: [String: Activity<BDNLiveActivityAttributes>] = [:]

    func syncWithGames(_ items: [SportsEventItem]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let liveGames   = items.filter { $0.isLive && !$0.isFinal }
        let finalGames  = items.filter { $0.isFinal }
        let liveIDs     = Set(liveGames.map { $0.eventID })

        // End activities for finished or no-longer-live games
        for (eventID, activity) in activities where !liveIDs.contains(eventID) {
            let matchedFinal = finalGames.first { $0.eventID == eventID }
            let finalState = BDNLiveActivityAttributes.ContentState(
                homeScore: matchedFinal?.homeScore ?? activity.content.state.homeScore,
                awayScore: matchedFinal?.awayScore ?? activity.content.state.awayScore,
                statusDisplay: "Final",
                isLive: false,
                isFinal: true,
                network: matchedFinal?.network ?? activity.content.state.network
            )
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date.now.addingTimeInterval(30))
            )
            activities.removeValue(forKey: eventID)
        }

        // Start or update for live games
        for item in liveGames {
            let state = BDNLiveActivityAttributes.ContentState(
                homeScore: item.homeScore,
                awayScore: item.awayScore,
                statusDisplay: item.statusText.isEmpty ? item.timingLabel ?? "" : item.statusText,
                isLive: true,
                isFinal: false,
                network: item.network
            )
            let content = ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(90))

            if let existing = activities[item.eventID] {
                await existing.update(content)
            } else {
                let attrs = BDNLiveActivityAttributes(
                    eventID: item.eventID,
                    league: item.league,
                    homeTeam: item.homeTeam,
                    awayTeam: item.awayTeam,
                    sport: item.sport
                )
                do {
                    let activity = try Activity<BDNLiveActivityAttributes>.request(
                        attributes: attrs,
                        content: content,
                        pushType: nil
                    )
                    activities[item.eventID] = activity
                } catch {
                    // Activity limit reached or not authorized — fail silently
                }
            }
        }
    }

    /// Call on app foreground to re-adopt any activities this process didn't start.
    func reloadExistingActivities() {
        for activity in Activity<BDNLiveActivityAttributes>.activities {
            activities[activity.attributes.eventID] = activity
        }
    }
}
#endif
