import Foundation

/// Shared catalog for sports favorites + local preferences pickers (matches Sports customize data).
/// Team lists load from **TeamsCatalog.json** in the app bundle (expanded rosters); fallback embedded data if missing.
enum SportsFavoritesCatalog {
    /// Embedded minimum set if JSON fails to load (keeps app functional offline).
    private static let fallbackLeagueToTeams: [String: [String]] = [
        "NFL": ["Dallas Cowboys", "Kansas City Chiefs", "Philadelphia Eagles"],
        "NBA": ["Los Angeles Lakers", "Boston Celtics", "Golden State Warriors"],
        "MLB": ["New York Yankees", "Los Angeles Dodgers", "Houston Astros"],
        "NHL": ["Dallas Stars", "New York Rangers", "Colorado Avalanche"],
        "MLS": ["Inter Miami", "LA Galaxy", "Seattle Sounders"],
        "WNBA": ["Las Vegas Aces", "New York Liberty", "Seattle Storm"],
        "NCAAF": ["Alabama", "Georgia", "Ohio State"],
        "NCAAB": ["Duke", "North Carolina", "Kansas"],
        "UFC": ["Lightweight", "Welterweight", "Heavyweight"],
        "PGA": ["Scottie Scheffler", "Rory McIlroy", "Jordan Spieth"],
        "ATP": ["Novak Djokovic", "Carlos Alcaraz", "Jannik Sinner"],
        "WTA": ["Iga Swiatek", "Coco Gauff", "Aryna Sabalenka"],
        "Formula 1": ["Red Bull Racing", "Ferrari", "Mercedes"],
        "NASCAR": ["Hendrick Motorsports", "Joe Gibbs Racing", "Team Penske"],
        "Premier League": ["Arsenal", "Liverpool", "Manchester City"],
        "Champions League": ["Real Madrid", "Bayern Munich", "Barcelona"]
    ]

    private static let bundledLeagueToTeams: [String: [String]] = loadBundledTeamsCatalog()

    private static func loadBundledTeamsCatalog() -> [String: [String]] {
        guard let url = Bundle.main.url(forResource: "TeamsCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    /// Shown first in onboarding; broader than a single screen, rest follow alphabetically.
    static let featuredLeagueOrder: [String] = [
        "NFL", "NBA", "MLB", "NHL", "MLS",
        "NCAAF", "NCAAB", "WNBA",
        "UFC", "PGA", "ATP", "WTA",
        "Formula 1", "NASCAR",
        "Premier League", "Champions League"
    ]

    static var leagues: [String] {
        let keys = Set(bundledLeagueToTeams.keys).union(Set(fallbackLeagueToTeams.keys))
        let featured = featuredLeagueOrder.filter { keys.contains($0) }
        let rest = keys.subtracting(featured).sorted()
        return featured + rest
    }

    /// Grouped headings for inclusive onboarding (keys filtered to those in the catalog).
    static var leagueCategories: [(name: String, keys: [String])] {
        let definitions: [(String, [String])] = [
            ("Major US sports", ["NFL", "NBA", "MLB", "NHL", "MLS", "NCAAF", "NCAAB", "WNBA"]),
            ("Soccer", ["Premier League", "Champions League"]),
            ("Racing", ["Formula 1", "NASCAR"]),
            ("Tennis, golf & more", ["ATP", "WTA", "UFC", "PGA"])
        ]
        let valid = Set(leagues)
        return definitions.map { name, keys in
            (name, keys.filter { valid.contains($0) })
        }
        .filter { !$0.keys.isEmpty }
    }

    /// Human-friendly labels for UI (keys stay stable for persistence).
    static func displayTitle(for leagueKey: String) -> String {
        switch leagueKey {
        case "NCAAF": return "NCAA Football"
        case "NCAAB": return "NCAA Basketball"
        default: return leagueKey
        }
    }

    static func teams(for league: String) -> [String] {
        if let bundled = bundledLeagueToTeams[league], !bundled.isEmpty {
            return bundled
        }
        return fallbackLeagueToTeams[league] ?? []
    }

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func displayLeague(forNormalized normalized: String) -> String {
        if let match = leagues.first(where: { Self.normalized($0) == normalized }) {
            return displayTitle(for: match)
        }
        return normalized
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                if lower.count <= 4 { return lower.uppercased() }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}
