#if os(iOS)
import AppIntents
import Foundation

// MARK: - Individual tab-opening intents

struct OpenHeadlinesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Headlines"
    static var description = IntentDescription("Jump to the Headlines tab in Big Dave's News")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationState.shared.selectedTab = .headlines
        return .result()
    }
}

struct OpenBriefIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Morning Brief"
    static var description = IntentDescription("Open the Morning Brief in Big Dave's News")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationState.shared.selectedTab = .brief
        return .result()
    }
}

struct OpenWatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Watch"
    static var description = IntentDescription("Jump to the Watch tab in Big Dave's News")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationState.shared.selectedTab = .watch
        return .result()
    }
}

struct OpenSportsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Sports"
    static var description = IntentDescription("Jump to the Sports tab in Big Dave's News")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationState.shared.selectedTab = .sports
        return .result()
    }
}

// MARK: - App Shortcuts provider
// Registers shortcuts with Siri and the Shortcuts app.
// On iPhone 15 Pro+ the Action Button can be assigned to any of these.

struct BDNShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBriefIntent(),
            phrases: [
                "Open \(.applicationName) Brief",
                "Morning news with \(.applicationName)",
                "Get my brief from \(.applicationName)"
            ],
            shortTitle: "Morning Brief",
            systemImageName: "sunrise"
        )
        AppShortcut(
            intent: OpenHeadlinesIntent(),
            phrases: [
                "Open \(.applicationName) Headlines",
                "Check news in \(.applicationName)",
                "What's the news in \(.applicationName)"
            ],
            shortTitle: "Headlines",
            systemImageName: "newspaper"
        )
        AppShortcut(
            intent: OpenWatchIntent(),
            phrases: [
                "Open \(.applicationName) Watch",
                "What to watch in \(.applicationName)"
            ],
            shortTitle: "Watch",
            systemImageName: "play.tv"
        )
        AppShortcut(
            intent: OpenSportsIntent(),
            phrases: [
                "Open \(.applicationName) Sports",
                "Check scores in \(.applicationName)"
            ],
            shortTitle: "Sports",
            systemImageName: "sportscourt"
        )
    }
}

#endif
