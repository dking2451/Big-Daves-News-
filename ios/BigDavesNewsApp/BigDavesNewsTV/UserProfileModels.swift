import Foundation

/// Mirrors `GET /api/user/profile` composed document.
struct ComposedUserProfile: Codable, Sendable {
    var schemaVersion: Int?
    var userId: String?
    var updatedAt: String?
    var preferences: ProfilePreferencesBlock?
    var watch: ProfileWatchBlock?
    var behavior: ProfileBehaviorBlock?
    var sync: [String: String]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case userId = "user_id"
        case updatedAt = "updated_at"
        case preferences
        case watch
        case behavior
        case sync
    }

    var prefs: ProfilePreferencesBlock { preferences ?? ProfilePreferencesBlock() }
    var watchBlock: ProfileWatchBlock { watch ?? ProfileWatchBlock() }
    var behaviorBlock: ProfileBehaviorBlock { behavior ?? ProfileBehaviorBlock() }
}

struct ProfilePreferencesBlock: Codable, Sendable, Equatable {
    var preferredProviders: [String]?
    var preferredGenres: [String]?
    var favoriteTeams: [String]?
    var favoriteLeagues: [String]?
    var watchEpisodeAlerts: Bool?
    var upcomingReleaseReminders: Bool?

    enum CodingKeys: String, CodingKey {
        case preferredProviders = "preferred_providers"
        case preferredGenres = "preferred_genres"
        case favoriteTeams = "favorite_teams"
        case favoriteLeagues = "favorite_leagues"
        case watchEpisodeAlerts = "watch_episode_alerts"
        case upcomingReleaseReminders = "upcoming_release_reminders"
    }
}

struct ProfileWatchBlock: Codable, Sendable, Equatable {
    var savedShowIds: [String]?
    var watchStateByShow: [String: String]?
    var likedShowIds: [String]?
    var passedShowIds: [String]?

    enum CodingKeys: String, CodingKey {
        case savedShowIds = "saved_show_ids"
        case watchStateByShow = "watch_state_by_show"
        case likedShowIds = "liked_show_ids"
        case passedShowIds = "passed_show_ids"
    }
}

struct ProfileBehaviorBlock: Codable, Sendable, Equatable {
    var recentlySurfaced: [ProfileSurfaceEntry]?
    var lastInteractionAt: String?

    enum CodingKeys: String, CodingKey {
        case recentlySurfaced = "recently_surfaced"
        case lastInteractionAt = "last_interaction_at"
    }
}

struct ProfileSurfaceEntry: Codable, Sendable, Equatable {
    var showId: String?
    var surface: String?
    var at: String?

    enum CodingKeys: String, CodingKey {
        case showId = "show_id"
        case surface
        case at
    }
}
