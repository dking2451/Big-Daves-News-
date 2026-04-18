import Foundation

/// Tracks whether new headlines have arrived since the user last viewed the Headlines tab.
/// Updated by HeadlinesViewModel after each successful refresh; cleared by HeadlinesView on appear.
@MainActor
final class HeadlinesBadgeState: ObservableObject {
    static let shared = HeadlinesBadgeState()

    @Published private(set) var hasNewStories = false

    private let lastSeenKey = "bdn-headlines-last-seen-claim-id"

    private init() {}

    /// Called by HeadlinesViewModel after a successful refresh.
    /// If the top claim has changed since the user last viewed the tab, sets hasNewStories = true.
    func didRefresh(topClaimID: String?) {
        guard let claimID = topClaimID, !claimID.isEmpty else { return }
        let lastSeen = UserDefaults.standard.string(forKey: lastSeenKey) ?? ""
        if claimID != lastSeen {
            hasNewStories = true
        }
    }

    /// Called when the user opens the Headlines tab. Clears the badge and saves current top claim.
    func markSeen(topClaimID: String?) {
        hasNewStories = false
        if let claimID = topClaimID, !claimID.isEmpty {
            UserDefaults.standard.set(claimID, forKey: lastSeenKey)
        }
    }
}
