import Foundation

/// Mirrors `/api/sports/now` rows for the tvOS target (kept local to avoid pulling the iOS app module).
struct TVSportsNowResponse: Decodable {
    let success: Bool
    let message: String?
    let items: [TVSportsEventItem]

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case items
    }
}

struct TVSportsEventItem: Identifiable, Hashable, Decodable {
    let eventID: String
    let league: String
    let sport: String
    let title: String
    let startTimeUTC: String
    let startTimeLocal: String
    let statusText: String
    let state: String
    let isLive: Bool
    let isFinal: Bool
    let startsInMinutes: Int
    let homeTeam: String
    let awayTeam: String
    let homeScore: String
    let awayScore: String
    let network: String
    let networks: [String]?
    let isAvailableOnProvider: Bool?
    let matchedProviderNetworks: [String]?
    let isFavoriteLeague: Bool?
    let favoriteTeamCount: Int?
    let rankingScore: Double?
    let rankingReason: String?
    let sourceType: String?
    let isAltSport: Bool?
    let timingLabel: String?
    let ochoPromotedFromCore: Bool?

    var id: String {
        let trimmed = eventID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "\(league)-\(title)-\(startTimeUTC)"
    }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case league
        case sport
        case title
        case startTimeUTC = "start_time_utc"
        case startTimeLocal = "start_time_local"
        case statusText = "status_text"
        case state
        case isLive = "is_live"
        case isFinal = "is_final"
        case startsInMinutes = "starts_in_minutes"
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case homeScore = "home_score"
        case awayScore = "away_score"
        case network
        case networks
        case isAvailableOnProvider = "is_available_on_provider"
        case matchedProviderNetworks = "matched_provider_networks"
        case isFavoriteLeague = "is_favorite_league"
        case favoriteTeamCount = "favorite_team_count"
        case rankingScore = "ranking_score"
        case rankingReason = "ranking_reason"
        case sourceType = "source_type"
        case isAltSport = "is_alt_sport"
        case timingLabel = "timing_label"
        case ochoPromotedFromCore = "ocho_promoted_from_core"
    }
}

enum TVSportsCardDisplayStatus: String {
    case live
    case startingSoon
    case scheduled

    var title: String {
        switch self {
        case .live: return "LIVE"
        case .startingSoon: return "Starting Soon"
        case .scheduled: return "Scheduled"
        }
    }
}

extension TVSportsEventItem {
    /// Aligns with server `timing_label` (`live_now` | `starting_soon` | `tonight`) with fallbacks.
    func resolvedTimingLabel() -> String {
        if isLive { return "live_now" }
        if let t = timingLabel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !t.isEmpty {
            return t
        }
        if startsInMinutes >= 0, startsInMinutes <= 120 { return "starting_soon" }
        return "tonight"
    }

    var matchupLine: String {
        let a = awayTeam.trimmingCharacters(in: .whitespacesAndNewlines)
        let h = homeTeam.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty, !h.isEmpty { return "\(a) @ \(h)" }
        let tl = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return tl.isEmpty ? "Matchup" : tl
    }

    var displayStatus: TVSportsCardDisplayStatus {
        if isLive { return .live }
        switch resolvedTimingLabel() {
        case "starting_soon": return .startingSoon
        default: return .scheduled
        }
    }

    var footnoteProvider: String? {
        let n = network.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        if let first = networks?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            return first
        }
        return nil
    }

    var scoreOrTimeLine: String {
        if isLive {
            let a = awayScore.trimmingCharacters(in: .whitespacesAndNewlines)
            let h = homeScore.trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty, !h.isEmpty { return "\(a) – \(h)" }
            let st = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !st.isEmpty { return st }
            return "Live"
        }
        if let pretty = Self.shortTime(fromISO: startTimeLocal) ?? Self.shortTime(fromISO: startTimeUTC) {
            return pretty
        }
        let st = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !st.isEmpty { return st }
        if startsInMinutes >= 0 { return "Starts in \(startsInMinutes) min" }
        return "Scheduled"
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func shortTime(fromISO raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let parsed = isoFrac.date(from: s) ?? isoPlain.date(from: s)
        guard let d = parsed else { return nil }
        let out = DateFormatter()
        out.timeStyle = .short
        out.dateStyle = .none
        out.timeZone = .current
        return out.string(from: d)
    }
}

extension TVSportsEventItem {
    static let ochoFallbackEventID = "ocho-tune-in-stub"

    fileprivate var normalizedSourceType: String {
        (sourceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isCuratedSource: Bool { normalizedSourceType == "curated" }
    var isEspnExtendedSource: Bool { normalizedSourceType == "espn_extended" }
    var isLiveFeedSource: Bool { normalizedSourceType == "live_feed" }

    /// ESPN extended, curated listings, or alt-sport flagged rows from `/api/sports/now?include_ocho=true`.
    var isOchoPipelineRow: Bool {
        isAltSport == true || isCuratedSource || isEspnExtendedSource
    }

    var isOchoFallbackStub: Bool { id == TVSportsEventItem.ochoFallbackEventID }

    func statusPillText(naturalMicrocopy: Bool) -> String {
        if naturalMicrocopy {
            switch displayStatus {
            case .live: return "LIVE"
            case .startingSoon: return "Starting Soon"
            case .scheduled:
                return resolvedTimingLabel() == "tonight" ? "Tonight" : "Upcoming"
            }
        }
        return displayStatus.title
    }

    /// Last-resort row so THE OCHO never renders totally empty.
    static func ochoFallbackTuneIn() -> TVSportsEventItem {
        let data = Data(
            """
            {"event_id":"ocho-tune-in-stub","league":"THE OCHO","sport":"alt_sports","title":"Alt sports roll around the clock — peek again soon","start_time_utc":"2099-01-01T00:00:00Z","start_time_local":"2099-01-01T00:00:00Z","status_text":"Something's always coming up.","state":"pre","is_live":false,"is_final":false,"starts_in_minutes":999,"home_team":"","away_team":"","home_score":"","away_score":"","network":"","source_type":"curated","is_alt_sport":true,"timing_label":"tonight"}
            """.utf8
        )
        guard let stub = try? JSONDecoder().decode(TVSportsEventItem.self, from: data) else {
            fatalError("TVSportsEventItem.ochoFallbackTuneIn decode failed")
        }
        return stub
    }
}
