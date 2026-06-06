import AppIntents

// MARK: - "What should I watch tonight?" Siri Intent

struct WhatShouldIWatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Tonight's Pick"
    static var description = IntentDescription("Get a personalized show recommendation from Big Dave's News")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some ProvidesDialog {
        let userId = SyncedUserIdentity.apiUserKey

        // Fetch shows to find the hero pick.
        let items: [TVWatchShowItem]
        do {
            items = try await TVAPIClient.shared.fetchWatchShows(
                userId: userId,
                limit: 20,
                minimumCount: 10
            )
        } catch {
            return .result(dialog: "Big Dave's News couldn't load recommendations right now. Try again in a moment.")
        }

        guard let hero = items.first else {
            return .result(dialog: "No recommendations available right now. Open Big Dave's News to get started.")
        }

        // Fetch the AI reason.
        let reason: String
        do {
            reason = try await TVAPIClient.shared.fetchTonightsPickReason(
                userId: userId,
                title: hero.title,
                genres: hero.genres,
                synopsis: hero.synopsis,
                providers: hero.providers
            )
        } catch {
            reason = ""
        }

        let provider = hero.primaryProvider ?? hero.providers.first ?? ""
        let providerSuffix = provider.isEmpty ? "" : " on \(provider)"
        let reasonSuffix = reason.isEmpty ? "" : " \(reason)"
        let response = "Tonight's pick is \(hero.title)\(providerSuffix).\(reasonSuffix)"
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - App Shortcuts

struct TVBDNShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatShouldIWatchIntent(),
            phrases: [
                "What should I watch tonight in \(.applicationName)",
                "Tonight's pick in \(.applicationName)",
                "Recommend something in \(.applicationName)"
            ],
            shortTitle: "Tonight's Pick",
            systemImageName: "sparkles.tv"
        )
    }
}
