import Foundation

enum AppTab: Hashable {
    case headlines
    case brief
    case sports
    case business
    case watch
    case settings
}

@MainActor
final class AppNavigationState: ObservableObject {
    static let shared = AppNavigationState()

    @Published var selectedTab: AppTab = .headlines

    private init() {}

    func openBrief() {
        selectedTab = .brief
    }

    func openSports() {
        selectedTab = .sports
    }
}
