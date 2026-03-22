import Foundation
import SwiftUI

/// Drives the multi-step personalization flow; persists into `LocalUserPreferences` on completion.
@MainActor
final class PersonalizationOnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome = 0
        case genres = 1
        case streaming = 2
        case sports = 3
        case done = 4
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

    static let completedKey = "bdn-personalization-onboarding-completed-v1"

    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }
}
