import Foundation

/// Shared catalog for sports favorites + local preferences pickers (matches Sports customize data).
enum SportsFavoritesCatalog {
    static let leagueToTeams: [String: [String]] = [
        "NFL": ["Dallas Cowboys", "Philadelphia Eagles", "San Francisco 49ers", "Kansas City Chiefs", "Buffalo Bills", "Green Bay Packers"],
        "NBA": ["Los Angeles Lakers", "Boston Celtics", "Golden State Warriors", "Dallas Mavericks", "Miami Heat", "Milwaukee Bucks"],
        "WNBA": ["Las Vegas Aces", "New York Liberty", "Dallas Wings", "Seattle Storm", "Phoenix Mercury", "Chicago Sky"],
        "MLB": ["New York Yankees", "Boston Red Sox", "Los Angeles Dodgers", "Houston Astros", "Texas Rangers", "Atlanta Braves"],
        "NHL": ["Dallas Stars", "New York Rangers", "Boston Bruins", "Colorado Avalanche", "Vegas Golden Knights", "Toronto Maple Leafs"],
        "MLS": ["Inter Miami", "LA Galaxy", "Seattle Sounders", "FC Dallas", "Atlanta United", "LAFC"],
        "NCAAF": ["Alabama", "Georgia", "Texas", "Michigan", "Ohio State", "Oregon"],
        "NCAAB": ["Duke", "North Carolina", "Kansas", "Kentucky", "UConn", "Baylor"],
        "UFC": ["Lightweight", "Welterweight", "Middleweight", "Women's Strawweight", "Featherweight", "Heavyweight"],
        "PGA": ["Scottie Scheffler", "Rory McIlroy", "Xander Schauffele", "Brooks Koepka", "Jordan Spieth", "Collin Morikawa"],
        "ATP": ["Novak Djokovic", "Carlos Alcaraz", "Jannik Sinner", "Daniil Medvedev", "Alexander Zverev", "Taylor Fritz"],
        "WTA": ["Iga Swiatek", "Coco Gauff", "Aryna Sabalenka", "Elena Rybakina", "Jessica Pegula", "Ons Jabeur"]
    ]

    static var leagues: [String] {
        leagueToTeams.keys.sorted()
    }

    static func teams(for league: String) -> [String] {
        leagueToTeams[league] ?? []
    }

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func displayLeague(forNormalized normalized: String) -> String {
        if let match = leagues.first(where: { Self.normalized($0) == normalized }) {
            return match
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
