import SwiftUI

// MARK: - User-facing labels (matches product copy)

/// Stable labels shown in chips and detail; map from backend enums / screen context.
enum ContentSourceLabel: String, CaseIterable {
    case curated = "Curated"
    case local = "Local"
    case espnLive = "ESPN Live"
    case stadiumListing = "Stadium Listing"
    case curatedListing = "Curated Listing"
}

// MARK: - Backend mapping (recommendations)

/// Maps API / pipeline values to user-facing `ContentSourceLabel`.
///
/// **Sports** (`source_type` from `/api/sports/now`):
/// - `live_feed` → **ESPN Live** (ESPN scoreboard / broadcast metadata)
/// - `stadium_curated` → **Stadium Listing** (manual `stadium_schedule.json`)
/// - `showcase` → **Curated Listing** (optional app-generated backfill; usually off)
/// - Empty / unknown → no chip on the card; detail sheet explains or shows raw if needed
///
/// **Headlines**
/// - Curated facts (`/api/facts` → `Claim`) → **Curated** (editorial pipeline)
/// - Local news (`/api/local-news` → `LocalNewsItem`) → **Local**
enum ContentSourceMapping {
    static func headlinesFactsChip() -> ContentSourceLabel {
        .curated
    }

    static func headlinesLocalChip() -> ContentSourceLabel {
        .local
    }

    /// Chip for sports list rows; returns `nil` when we shouldn’t imply a known pipeline.
    static func sportsCardLabel(for sourceType: String?) -> ContentSourceLabel? {
        let raw = (sourceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "live_feed":
            return .espnLive
        case "stadium_curated":
            return .stadiumListing
        case "showcase":
            return .curatedListing
        case "":
            return .espnLive
        default:
            return nil
        }
    }

    static func sportsDetailTitle(for sourceType: String?) -> String {
        let raw = (sourceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "live_feed", "":
            return "ESPN live data"
        case "stadium_curated":
            return "Stadium listing"
        case "showcase":
            return "Curated listing"
        default:
            return "Other"
        }
    }

    static func sportsDetailFootnote(for sourceType: String?) -> String {
        let raw = (sourceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "live_feed", "":
            return "Schedules, scores, and broadcast info come from ESPN’s public feed. Availability on your provider is estimated separately."
        case "stadium_curated":
            return "Times and titles are maintained manually for Stadium / Bally Sports-style listings and may differ from other guides."
        case "showcase":
            return "This row is a placeholder event used when live feeds are sparse. Prefer live or Stadium listings when available."
        default:
            if raw.isEmpty {
                return sportsDetailFootnote(for: "live_feed")
            }
            return "Source type “\(sourceType ?? "")” — see team and network details below."
        }
    }
}

// MARK: - Chip view

/// Small, secondary capsule for content provenance. Prefer one chip per card row where space allows.
struct ContentSourceChip: View {
    let label: ContentSourceLabel
    var body: some View {
        Text(label.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
            .accessibilityLabel("Content source: \(label.rawValue)")
    }

    private var foregroundColor: Color {
        Color.secondary
    }

    private var backgroundColor: Color {
        Color(.tertiarySystemFill)
    }
}
