import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Attributes (mirrors BDNLiveActivityAttributes.swift in the main app)

struct BDNLiveActivityAttributes: ActivityAttributes {
    public typealias BDNLiveActivityState = ContentState

    public struct ContentState: Codable, Hashable {
        var homeScore: String
        var awayScore: String
        var statusDisplay: String
        var isLive: Bool
        var isFinal: Bool
        var network: String
    }

    var eventID: String
    var league: String
    var homeTeam: String
    var awayTeam: String
    var sport: String
}

// MARK: - Helpers

private func sportEmoji(for sport: String) -> String {
    switch sport.lowercased() {
    case "basketball": return "🏀"
    case "baseball":   return "⚾"
    case "football":   return "🏈"
    case "hockey":     return "🏒"
    case "soccer":     return "⚽"
    case "tennis":     return "🎾"
    case "golf":       return "⛳"
    default:           return "🏆"
    }
}

private func shortName(_ team: String) -> String {
    // Use last word of team name (e.g. "Kansas City Chiefs" -> "Chiefs")
    team.components(separatedBy: " ").last ?? team
}

// MARK: - Lock Screen / Notification Banner View

struct BDNLiveActivityLockScreenView: View {
    let context: ActivityViewContext<BDNLiveActivityAttributes>

    var body: some View {
        let state = context.state
        let attrs = context.attributes

        HStack(spacing: 0) {
            // Left: sport + league
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(sportEmoji(for: attrs.sport))
                        .font(.system(size: 14))
                    Text(attrs.league)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(state.statusDisplay)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.isFinal ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                if !state.network.isEmpty && !state.isFinal {
                    Text(state.network)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Centre: score block
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text(state.awayScore)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(shortName(attrs.awayTeam))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("–")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.tertiary)
                VStack(spacing: 1) {
                    Text(state.homeScore)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(shortName(attrs.homeTeam))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            // Right: live dot or FINAL
            VStack(alignment: .trailing, spacing: 2) {
                if state.isLive && !state.isFinal {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.red)
                    }
                } else if state.isFinal {
                    Text("FINAL")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.secondary)
                }
                Text("Big Dave's")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Live Activity Widget

struct BDNLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BDNLiveActivityAttributes.self) { context in
            BDNLiveActivityLockScreenView(context: context)
                .containerBackground(.ultraThinMaterial, for: .widget)
        } dynamicIsland: { context in
            let state  = context.state
            let attrs  = context.attributes
            let away   = shortName(attrs.awayTeam)
            let home   = shortName(attrs.homeTeam)
            let score  = "\(state.awayScore)–\(state.homeScore)"
            let emoji  = sportEmoji(for: attrs.sport)

            return DynamicIsland {
                // MARK: Expanded
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(emoji + " " + attrs.league)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(away)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(home)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if state.isLive && !state.isFinal {
                            HStack(spacing: 3) {
                                Circle().fill(Color.red).frame(width: 6, height: 6)
                                Text("LIVE").font(.system(size: 10, weight: .black)).foregroundStyle(.red)
                            }
                        } else {
                            Text("FINAL").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        }
                        Text(state.awayScore)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                        Text(state.homeScore)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(state.statusDisplay)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(state.isFinal ? .secondary : .primary)
                        Spacer()
                        if !state.network.isEmpty && !state.isFinal {
                            Text(state.network)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }

            } compactLeading: {
                // Score in compact pill
                Text(score)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)

            } compactTrailing: {
                // Live dot + sport emoji
                HStack(spacing: 2) {
                    if state.isLive && !state.isFinal {
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                    }
                    Text(emoji)
                        .font(.system(size: 11))
                }
                .padding(.trailing, 4)

            } minimal: {
                // Just the emoji for the minimal pill
                Text(emoji)
                    .font(.system(size: 12))
            }
            .widgetURL(URL(string: "bdnapp://sports"))
            .keylineTint(.red)
        }
    }
}
