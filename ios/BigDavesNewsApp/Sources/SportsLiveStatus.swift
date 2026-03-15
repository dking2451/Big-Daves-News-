import Foundation

@MainActor
final class SportsLiveStatus: ObservableObject {
    static let shared = SportsLiveStatus()

    @Published private(set) var hasLiveGames = false

    private var lastRefreshAt: Date?
    private let refreshCooldownSeconds: TimeInterval = 120

    private init() {}

    func refreshIfNeeded(force: Bool = false) async {
        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < refreshCooldownSeconds {
            return
        }
        await refresh(force: force)
    }

    func refresh(force: Bool = false) async {
        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < refreshCooldownSeconds {
            return
        }
        do {
            let backendProviderKey = SportsProviderPreferences.backendProviderKeyFromDefaults
            let availabilityOnly = UserDefaults.standard.bool(
                forKey: SportsProviderPreferences.availabilityOnlyStorageKey
            ) && !backendProviderKey.isEmpty
            let items = try await APIClient.shared.fetchSportsNow(
                windowHours: 2,
                timezoneName: TimeZone.current.identifier,
                providerKey: backendProviderKey,
                availabilityOnly: availabilityOnly
            )
            hasLiveGames = items.contains(where: { $0.isLive })
            lastRefreshAt = Date()
        } catch {
            // Keep current indicator state if refresh fails.
            lastRefreshAt = Date()
        }
    }

    func apply(items: [SportsEventItem]) {
        hasLiveGames = items.contains(where: { $0.isLive })
        lastRefreshAt = Date()
    }
}
