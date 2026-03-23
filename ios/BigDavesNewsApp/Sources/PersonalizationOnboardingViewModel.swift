import Foundation
import SwiftUI

/// Drives the multi-step personalization flow; persists into `LocalUserPreferences` on completion.
@MainActor
final class PersonalizationOnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome = 0
        case genres = 1
        case streaming = 2
        /// Leagues only — next step is team picks.
        case sportsLeagues = 3
        case sportsTeams = 4
        case done = 5
    }

    @Published var step: Step = .welcome

    @Published var selectedGenreKeys: Set<String> = []
    @Published var selectedProviderKeys: Set<String> = []
    @Published var selectedTeamKeys: Set<String> = []
    @Published var selectedLeagueKeys: Set<String> = []

    let prefs = LocalUserPreferences.shared

    func syncFromExistingPrefs() {
        selectedGenreKeys = prefs.favoriteGenresNormalized
        selectedProviderKeys = prefs.preferredProvidersNormalized
        selectedTeamKeys = prefs.favoriteTeamsNormalized
        selectedLeagueKeys = prefs.favoriteLeaguesNormalized
    }

    var currentStepIndex: Int { step.rawValue }
    let totalSteps = Step.allCases.count

    func goToNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            step = next
        }
    }

    /// Skip both sports screens — jump to completion summary (clears league/team prefs from this flow).
    func skipSportsToCompletion() {
        selectedLeagueKeys = []
        selectedTeamKeys = []
        withAnimation(.easeInOut(duration: 0.28)) {
            step = .done
        }
    }

    /// Leagues the user chose on the previous screen appear first when picking teams.
    func prioritizedLeaguesForTeamPicker(allLeagues: [String]) -> [String] {
        let preferred = allLeagues.filter { selectedLeagueKeys.contains(PreferenceNormalization.league($0)) }
        let rest = allLeagues.filter { !preferred.contains($0) }
        return preferred + rest
    }

    func completeAndPersist() {
        prefs.setFavoriteGenres(selectedGenreKeys)
        prefs.setPreferredProviders(selectedProviderKeys)
        prefs.setFavoriteTeams(selectedTeamKeys)
        prefs.setFavoriteLeagues(selectedLeagueKeys)
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        FirstRunExperience.markFirstValueTooltipPending()
        objectWillChange.send()
    }

    /// Skip entire flow from welcome (or dismiss without saving mid-flow if wired).
    func finishWithoutSaving() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        objectWillChange.send()
    }

    func toggleGenre(displayName: String) {
        let key = PreferenceNormalization.genre(displayName)
        if selectedGenreKeys.contains(key) {
            selectedGenreKeys.remove(key)
        } else {
            selectedGenreKeys.insert(key)
        }
    }

    func toggleProvider(displayName: String) {
        let key = PreferenceNormalization.streamingProvider(displayName)
        if selectedProviderKeys.contains(key) {
            selectedProviderKeys.remove(key)
        } else {
            selectedProviderKeys.insert(key)
        }
    }

    func toggleTeam(displayName: String) {
        let key = PreferenceNormalization.team(displayName)
        if selectedTeamKeys.contains(key) {
            selectedTeamKeys.remove(key)
        } else {
            selectedTeamKeys.insert(key)
        }
    }

    func toggleLeague(displayName: String) {
        let key = PreferenceNormalization.league(displayName)
        if selectedLeagueKeys.contains(key) {
            selectedLeagueKeys.remove(key)
        } else {
            selectedLeagueKeys.insert(key)
        }
    }

    func isGenreSelected(_ displayName: String) -> Bool {
        selectedGenreKeys.contains(PreferenceNormalization.genre(displayName))
    }

    func isProviderSelected(_ displayName: String) -> Bool {
        selectedProviderKeys.contains(PreferenceNormalization.streamingProvider(displayName))
    }

    func isTeamSelected(_ displayName: String) -> Bool {
        selectedTeamKeys.contains(PreferenceNormalization.team(displayName))
    }

    func isLeagueSelected(_ displayName: String) -> Bool {
        selectedLeagueKeys.contains(PreferenceNormalization.league(displayName))
    }

    /// Selected teams that belong to a given league (for accordion badges).
    func selectedTeamCount(forLeague leagueKey: String) -> Int {
        SportsFavoritesCatalog.teams(for: leagueKey).filter { isTeamSelected($0) }.count
    }

    static let completedKey = "bdn-personalization-onboarding-completed-v1"

    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }
}

// MARK: - Replay from Settings / Help

extension Notification.Name {
    /// Posted to show personalization onboarding again (e.g. from Settings).
    static let bdnReplayPersonalizationOnboarding = Notification.Name("bdn.replayPersonalizationOnboarding")
}

enum PersonalizationOnboardingReplay {
    /// Resets completion flag and presents onboarding from `RootTabView` (listen for ``Notification.Name.bdnReplayPersonalizationOnboarding``).
    @MainActor static func trigger() {
        UserDefaults.standard.set(false, forKey: PersonalizationOnboardingViewModel.completedKey)
        FirstRunExperience.clearFirstValueTooltipPending()
        NotificationCenter.default.post(name: .bdnReplayPersonalizationOnboarding, object: nil)
    }
}
