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

// MARK: - Read Morning Brief (speaks AI narration without opening the app)

struct ReadMorningBriefIntent: AppIntent {
    static var title: LocalizedStringResource = "Read Morning Brief"
    static var description = IntentDescription("Hear today's AI-generated morning news brief from Big Dave's News")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some ProvidesDialog {
        let topics = await MainActor.run {
            Array(LocalUserPreferences.shared.favoriteTopicsNormalized)
        }
        do {
            let narration = try await APIClient.shared.fetchBriefNarration(topics: topics)
            let cleaned = narration
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { line -> String in
                    if line.hasPrefix("•") {
                        return line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return line
                }
                .joined(separator: ". ")
            return .result(dialog: IntentDialog(stringLiteral: cleaned.isEmpty ? "No brief available right now." : cleaned))
        } catch {
            return .result(dialog: "Big Dave's News couldn't load your brief right now. Try again in a moment.")
        }
    }
}

// MARK: - Read Sports Digest (speaks AI sports update without opening the app)

struct ReadSportsDigestIntent: AppIntent {
    static var title: LocalizedStringResource = "Read Sports Update"
    static var description = IntentDescription("Hear today's personalized sports digest from Big Dave's News")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some ProvidesDialog {
        let deviceID = WatchDeviceIdentity.current
        let hasFavorites = await MainActor.run {
            let prefs = LocalUserPreferences.shared
            return !prefs.favoriteTeamsNormalized.isEmpty || !prefs.favoriteLeaguesNormalized.isEmpty
        }
        guard hasFavorites else {
            return .result(dialog: "Add favorite teams in Big Dave's News to get a personalized sports update.")
        }
        do {
            let digest = try await APIClient.shared.fetchSportsDigest(deviceID: deviceID)
            let cleaned = digest
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { line -> String in
                    if line.hasPrefix("•") {
                        return line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return line
                }
                .joined(separator: ". ")
            return .result(dialog: IntentDialog(stringLiteral: cleaned.isEmpty ? "No sports update available right now." : cleaned))
        } catch {
            return .result(dialog: "Big Dave's News couldn't load your sports update right now. Try again in a moment.")
        }
    }
}

// MARK: - App Shortcuts provider
// Registers shortcuts with Siri and the Shortcuts app.
// On iPhone 15 Pro+ the Action Button can be assigned to any of these.

struct BDNShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReadMorningBriefIntent(),
            phrases: [
                "Read my brief in \(.applicationName)",
                "What's in the news in \(.applicationName)",
                "Morning brief from \(.applicationName)"
            ],
            shortTitle: "Morning Brief",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: ReadSportsDigestIntent(),
            phrases: [
                "How are my teams doing in \(.applicationName)",
                "Sports update from \(.applicationName)",
                "What's the score in \(.applicationName)"
            ],
            shortTitle: "Sports Update",
            systemImageName: "sportscourt.fill"
        )
        AppShortcut(
            intent: OpenBriefIntent(),
            phrases: [
                "Open \(.applicationName) Brief",
                "Get my brief from \(.applicationName)"
            ],
            shortTitle: "Open Brief",
            systemImageName: "sunrise"
        )
        AppShortcut(
            intent: OpenHeadlinesIntent(),
            phrases: [
                "Open \(.applicationName) Headlines",
                "Check news in \(.applicationName)"
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
