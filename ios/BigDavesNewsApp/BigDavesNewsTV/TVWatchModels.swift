import Foundation

struct TVWatchShowsResponse: Decodable, Sendable {
    var success: Bool?
    var items: [TVWatchShowItem]
}

struct TVWatchShowItem: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let posterURL: String
    let posterStatus: String?
    let posterTrusted: Bool?
    let synopsis: String
    let providers: [String]
    let primaryProvider: String?
    let genres: [String]
    let primaryGenre: String?
    let releaseDate: String
    let lastEpisodeAirDate: String?
    let nextEpisodeAirDate: String?
    let releaseBadge: String?
    let releaseBadgeLabel: String?
    let seasonEpisodeStatus: String
    let trendScore: Double
    let rankScore: Double?
    let seen: Bool?
    let watchState: String?
    let saved: Bool?
    let savedAtUTC: String?
    let isNewEpisode: Bool?
    let isUpcomingRelease: Bool?
    let userReaction: String?
    let recommendationReason: String?
    let rankOrder: Int?
    /// Server home bucket: `tonight_pick` | `new_episodes` | `continue_watching` | `from_your_list` | `more_picks`
    let homeFeedSection: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case posterURL = "poster_url"
        case posterStatus = "poster_status"
        case posterTrusted = "poster_trusted"
        case synopsis
        case providers
        case primaryProvider = "primary_provider"
        case genres
        case primaryGenre = "primary_genre"
        case releaseDate = "release_date"
        case lastEpisodeAirDate = "last_episode_air_date"
        case nextEpisodeAirDate = "next_episode_air_date"
        case releaseBadge = "release_badge"
        case releaseBadgeLabel = "release_badge_label"
        case seasonEpisodeStatus = "season_episode_status"
        case trendScore = "trend_score"
        case rankScore = "rank_score"
        case seen
        case watchState = "watch_state"
        case saved
        case savedAtUTC = "saved_at_utc"
        case isNewEpisode = "is_new_episode"
        case isUpcomingRelease = "is_upcoming_release"
        case userReaction = "user_reaction"
        case recommendationReason = "recommendation_reason"
        case rankOrder = "rank_order"
        case homeFeedSection = "home_feed_section"
    }

    var watchProgressState: WatchProgressTV {
        let raw = watchState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if raw == "watching" { return .watching }
        if raw == "finished" { return .finished }
        if seen == true { return .finished }
        return .notStarted
    }

    var posterRemoteURL: URL? {
        let raw = (posterStatus ?? "").lowercased()
        if raw == "trusted" || posterTrusted == true {
            let t = posterURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }
            if let u = URL(string: t), let host = u.host?.lowercased(), host.contains("placehold.co") { return nil }
            return URL(string: t)
        }
        return nil
    }
}

enum WatchProgressTV: String, CaseIterable {
    case notStarted = "not_started"
    case watching = "watching"
    case finished = "finished"
}
