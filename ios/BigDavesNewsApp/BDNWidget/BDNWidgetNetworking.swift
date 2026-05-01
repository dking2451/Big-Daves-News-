import Foundation

// Widgets run in an isolated process — no access to the main app module.
// All networking and models are self-contained here.

private let bdnBaseURL = "https://big-daves-news-web.onrender.com"

// MARK: - Headline models

struct BDNWidgetClaim: Identifiable {
    let id: String
    let headline: String
    let subtopic: String
    let sourceName: String
}

// Raw shape returned by /api/facts
private struct RawClaim: Decodable {
    let claimId: String
    let text: String
    let subtopic: String
    let evidence: [RawEvidence]

    enum CodingKeys: String, CodingKey {
        case claimId  = "claim_id"
        case text
        case subtopic
        case evidence
    }
}

private struct RawEvidence: Decodable {
    let sourceName: String
    enum CodingKeys: String, CodingKey {
        case sourceName = "source_name"
    }
}

private struct BDNWidgetFactsResponse: Decodable {
    let claims: [RawClaim]
}

func fetchWidgetHeadlines() async -> [BDNWidgetClaim] {
    guard let url = URL(string: "\(bdnBaseURL)/api/facts") else { return [] }
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(BDNWidgetFactsResponse.self, from: data)
        return response.claims.prefix(4).map { raw in
            BDNWidgetClaim(
                id: raw.claimId,
                headline: raw.text,
                subtopic: raw.subtopic,
                sourceName: raw.evidence.first?.sourceName ?? ""
            )
        }
    } catch {
        return []
    }
}

// MARK: - Sports models

struct BDNWidgetSportsItem: Decodable, Identifiable {
    let id: String
    let league: String
    let homeTeam: String
    let awayTeam: String
    let homeScore: String
    let awayScore: String
    let isLive: Bool
    let isFinal: Bool
    let statusDisplay: String
    let network: String

    enum CodingKeys: String, CodingKey {
        case id
        case league
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case homeScore = "home_score"
        case awayScore = "away_score"
        case isLive = "is_live"
        case isFinal = "is_final"
        case statusDisplay = "status_display"
        case network
    }
}

private struct BDNWidgetSportsResponse: Decodable {
    let items: [BDNWidgetSportsItem]
}

func fetchWidgetSports() async -> [BDNWidgetSportsItem] {
    var components = URLComponents(string: "\(bdnBaseURL)/api/sports/now")!
    components.queryItems = [
        URLQueryItem(name: "window_hours", value: "12"),
        URLQueryItem(name: "timezone_name", value: TimeZone.current.identifier),
        URLQueryItem(name: "limit", value: "4"),
    ]
    guard let url = components.url else { return [] }
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(BDNWidgetSportsResponse.self, from: data)
        return Array(response.items.prefix(4))
    } catch {
        return []
    }
}
