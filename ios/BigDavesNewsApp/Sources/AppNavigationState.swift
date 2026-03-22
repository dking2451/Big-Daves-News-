import Foundation

enum AppTab: Hashable {
    case headlines
    case brief
    case sports
    case weather
    case watch
    case settings
}

@MainActor
final class AppNavigationState: ObservableObject {
    static let shared = AppNavigationState()

    @Published var selectedTab: AppTab = .headlines
    /// Bumped when user asks to jump to Tonight’s Pick on Watch (overflow menu or deep link).
    @Published private(set) var watchTonightScrollNonce: Int = 0

    private init() {}

    func openBrief() {
        selectedTab = .brief
    }

    func openSports() {
        selectedTab = .sports
    }

    func openWatch() {
        selectedTab = .watch
    }

    /// After personalization onboarding: land on Watch (preferred) for immediate “Tonight’s Pick” value.
    /// Use `openBriefAsFirstExperience()` only if you intentionally skip Watch (e.g. product A/B).
    func routeToFirstPersonalizedExperience() {
        openWatch()
    }

    func openBriefAsFirstExperience() {
        selectedTab = .brief
    }

    /// Switches to Watch and signals the hero row to scroll into view.
    func openWatchTonightPick() {
        selectedTab = .watch
        watchTonightScrollNonce &+= 1
    }
}
