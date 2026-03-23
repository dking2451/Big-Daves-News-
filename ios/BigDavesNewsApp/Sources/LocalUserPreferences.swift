import Foundation
import SwiftUI

// MARK: - Normalization (shared with Watch / Sports heuristics)

enum PreferenceNormalization {
    static func genre(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Aligns onboarding labels with Watch provider strings (legacy “max” → `hbo max`).
    static func streamingProvider(_ value: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw == "max" { return "hbo max" }
        return raw
    }

    static func team(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func league(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Catalogs (UI + defaults; no network)

enum UserPreferencesCatalog {
    /// Matches common Watch genre chips for ranking boosts.
    static let genres: [String] = [
        "Drama", "Comedy", "Action", "Crime", "Sci-Fi", "Reality", "Documentary", "Animation",
        "Thriller", "Romance", "Horror", "Fantasy"
    ]

    /// Fast onboarding order (subset + order tuned for quick scan).
    static let onboardingGenres: [String] = [
        "Action", "Drama", "Comedy", "Sci-Fi", "Documentary", "Reality", "Crime", "Animation",
        "Thriller", "Horror", "Fantasy", "Romance"
    ]

    /// Display names aligned with Watch provider ordering.
    static let streamingProviders: [String] = [
        "Netflix", "Apple TV+", "HBO Max", "Paramount+", "Peacock", "Prime Video", "Hulu", "Disney+"
    ]

    /// Stored as `hbo max` via `PreferenceNormalization.streamingProvider` (legacy `max` still normalizes).
    static let onboardingStreamingProviders: [String] = [
        "Netflix", "Apple TV+", "Prime Video", "HBO Max", "Disney+", "Hulu", "Paramount+", "Peacock"
    ]

    /// Flattened (league, team) pairs from the same catalog Sports uses for favorites UI.
    static var teamChoices: [(league: String, team: String)] {
        SportsFavoritesCatalog.leagues.flatMap { league in
            SportsFavoritesCatalog.teams(for: league).map { (league, $0) }
        }
    }
}

// MARK: - Persistence payload

private struct LocalUserPreferencesPayload: Codable {
    var favoriteTeamKeys: [String]
    var favoriteGenreKeys: [String]
    var preferredProviderKeys: [String]
    var favoriteLeagueKeys: [String]?
}

// MARK: - Store

/// Device-local tastes (no account). Feeds **ranking** on Watch and Sports; optional filter hints only elsewhere.
@MainActor
final class LocalUserPreferences: ObservableObject {
    static let shared = LocalUserPreferences()

    private static let storageKey = "bdn-local-user-preferences-v2"

    /// Normalized team names (lowercased, trimmed).
    @Published private(set) var favoriteTeamsNormalized: Set<String> = []

    /// Normalized genre tokens.
    @Published private(set) var favoriteGenresNormalized: Set<String> = []

    /// Normalized streaming provider display names.
    @Published private(set) var preferredProvidersNormalized: Set<String> = []

    /// Normalized league labels (e.g. nfl, nba) for Sports / Brief boosts.
    @Published private(set) var favoriteLeaguesNormalized: Set<String> = []

    private init() {
        load()
    }

    var hasWatchPreferences: Bool {
        !favoriteGenresNormalized.isEmpty || !preferredProvidersNormalized.isEmpty
    }

    var hasSportsPreferences: Bool {
        !favoriteTeamsNormalized.isEmpty || !favoriteLeaguesNormalized.isEmpty
    }

    var isEmpty: Bool {
        favoriteTeamsNormalized.isEmpty && favoriteGenresNormalized.isEmpty && preferredProvidersNormalized.isEmpty
            && favoriteLeaguesNormalized.isEmpty
    }

    func setFavoriteTeams(_ teams: Set<String>) {
        favoriteTeamsNormalized = Set(teams.map { PreferenceNormalization.team($0) }.filter { !$0.isEmpty })
        persist()
    }

    func setFavoriteGenres(_ genres: Set<String>) {
        favoriteGenresNormalized = Set(genres.map { PreferenceNormalization.genre($0) }.filter { !$0.isEmpty })
        persist()
    }

    func setPreferredProviders(_ providers: Set<String>) {
        preferredProvidersNormalized = Set(providers.map { PreferenceNormalization.streamingProvider($0) }.filter { !$0.isEmpty })
        persist()
    }

    func setFavoriteLeagues(_ leagues: Set<String>) {
        favoriteLeaguesNormalized = Set(leagues.map { PreferenceNormalization.league($0) }.filter { !$0.isEmpty })
        persist()
    }

    func clearAll() {
        favoriteTeamsNormalized = []
        favoriteGenresNormalized = []
        preferredProvidersNormalized = []
        favoriteLeaguesNormalized = []
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(LocalUserPreferencesPayload.self, from: data) else {
            return
        }
        favoriteTeamsNormalized = Set(decoded.favoriteTeamKeys.map { PreferenceNormalization.team($0) })
        favoriteGenresNormalized = Set(decoded.favoriteGenreKeys.map { PreferenceNormalization.genre($0) })
        preferredProvidersNormalized = Set(decoded.preferredProviderKeys.map { PreferenceNormalization.streamingProvider($0) })
        favoriteLeaguesNormalized = Set((decoded.favoriteLeagueKeys ?? []).map { PreferenceNormalization.league($0) })
    }

    private func persist() {
        let payload = LocalUserPreferencesPayload(
            favoriteTeamKeys: Array(favoriteTeamsNormalized).sorted(),
            favoriteGenreKeys: Array(favoriteGenresNormalized).sorted(),
            preferredProviderKeys: Array(preferredProvidersNormalized).sorted(),
            favoriteLeagueKeys: Array(favoriteLeaguesNormalized).sorted()
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Watch ranking (soft boost; does not hide non-matching titles)

    func applyWatchRanking(_ shows: [WatchShowItem]) -> [WatchShowItem] {
        guard hasWatchPreferences else { return shows }
        return shows.sorted { lhs, rhs in
            let ls = watchPreferenceScore(lhs)
            let rs = watchPreferenceScore(rhs)
            if ls != rs { return ls > rs }
            return lhs.trendScore > rhs.trendScore
        }
    }

    private func watchPreferenceScore(_ show: WatchShowItem) -> Int {
        var score = 0
        if !preferredProvidersNormalized.isEmpty {
            let primary = PreferenceNormalization.streamingProvider(show.primaryProvider ?? "")
            let providers = show.providers.map { PreferenceNormalization.streamingProvider($0) }
            if preferredProvidersNormalized.contains(primary) {
                score += 4
            } else if providers.contains(where: { preferredProvidersNormalized.contains($0) }) {
                score += 2
            }
        }
        if !favoriteGenresNormalized.isEmpty {
            let hits = show.genres.filter { g in
                favoriteGenresNormalized.contains(PreferenceNormalization.genre(g))
            }.count
            score += min(hits * 3, 9)
        }
        return score
    }

    // MARK: - Brief (soft ranking for watch + sports rows)

    func applyBriefSportsRanking(_ items: [SportsEventItem]) -> [SportsEventItem] {
        let teamFav = favoriteTeamsNormalized
        let leagueFav = favoriteLeaguesNormalized
        guard !teamFav.isEmpty || !leagueFav.isEmpty else { return items }
        func score(_ item: SportsEventItem) -> Int {
            var s = (item.favoriteTeamCount ?? 0) > 0 ? 2 : 0
            let home = PreferenceNormalization.team(item.homeTeam)
            let away = PreferenceNormalization.team(item.awayTeam)
            if teamFav.contains(home) || teamFav.contains(away) { s += 5 }
            let lg = PreferenceNormalization.league(item.league)
            if leagueFav.contains(lg) { s += 3 }
            return s
        }
        return items.sorted { lhs, rhs in
            let a = score(lhs)
            let b = score(rhs)
            if a != b { return a > b }
            return lhs.startsInMinutes < rhs.startsInMinutes
        }
    }
}
