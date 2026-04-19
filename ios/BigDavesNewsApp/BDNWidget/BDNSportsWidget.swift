import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct SportsEntry: TimelineEntry {
    let date: Date
    let games: [BDNWidgetSportsItem]

    static let placeholder = SportsEntry(
        date: Date(),
        games: [
            BDNWidgetSportsItem(
                id: "1", league: "NBA",
                homeTeam: "Lakers", awayTeam: "Celtics",
                homeScore: "0", awayScore: "0",
                isLive: false, isFinal: false,
                statusDisplay: "7:30 PM ET", network: "ESPN"
            ),
            BDNWidgetSportsItem(
                id: "2", league: "MLB",
                homeTeam: "Yankees", awayTeam: "Red Sox",
                homeScore: "3", awayScore: "1",
                isLive: true, isFinal: false,
                statusDisplay: "7th Inning", network: "FS1"
            ),
        ]
    )
}

// MARK: - Timeline Provider

struct SportsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SportsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SportsEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task {
            let games = await fetchWidgetSports()
            completion(SportsEntry(date: Date(), games: games))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SportsEntry>) -> Void) {
        Task {
            let games = await fetchWidgetSports()
            let entry = SportsEntry(date: Date(), games: games)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }
}

// MARK: - Shared components

private struct SportsBrandMark: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
            Text("SPORTS")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .kerning(0.5)
        }
    }
}

private struct GameRowView: View {
    let game: BDNWidgetSportsItem

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(game.league)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .textCase(.uppercase)
                HStack(spacing: 3) {
                    Text(game.awayTeam)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("@")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(game.homeTeam)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if game.isLive && \!game.isFinal {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(.red)
                            .frame(width: 5, height: 5)
                        Text("LIVE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.red)
                    }
                    Text("\(game.awayScore)–\(game.homeScore)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                } else if game.isFinal {
                    Text("FINAL")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("\(game.awayScore)–\(game.homeScore)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text(game.statusDisplay)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    if \!game.network.isEmpty {
                        Text(game.network)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
        }
    }
}

// MARK: - Widget Views

struct BDNSportsWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SportsEntry

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        default:            mediumView
        }
    }

    private var smallView: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.12, blue: 0.07),
                    Color(red: 0.08, green: 0.22, blue: 0.12),
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            VStack(alignment: .leading, spacing: 0) {
                SportsBrandMark()
                Spacer()
                if let game = entry.games.first {
                    Text(game.league)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .textCase(.uppercase)
                        .padding(.bottom, 3)
                    Text(game.awayTeam)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("@ \(game.homeTeam)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Group {
                        if game.isLive && \!game.isFinal {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 6, height: 6)
                                Text("\(game.awayScore)–\(game.homeScore)")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                        } else if game.isFinal {
                            Text("Final \(game.awayScore)–\(game.homeScore)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        } else {
                            Text(game.statusDisplay)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .padding(.top, 5)
                } else {
                    Text("No games today")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(14)
        }
    }

    private var mediumView: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.12, blue: 0.07),
                    Color(red: 0.08, green: 0.22, blue: 0.12),
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                SportsBrandMark()
                if entry.games.isEmpty {
                    Spacer()
                    Text("No games scheduled")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                } else {
                    ForEach(Array(entry.games.prefix(2).enumerated()), id: \.element.id) { idx, game in
                        if idx > 0 {
                            Divider().background(.white.opacity(0.12))
                        }
                        GameRowView(game: game)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}

// MARK: - Widget declaration

struct BDNSportsWidget: Widget {
    let kind = "BDNSportsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SportsProvider()) { entry in
            BDNSportsWidgetView(entry: entry)
                .widgetURL(URL(string: "bdnapp://sports"))
                .containerBackground(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.12, blue: 0.07),
                            Color(red: 0.08, green: 0.22, blue: 0.12),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    for: .widget
                )
        }
        .configurationDisplayName("Sports")
        .description("Live scores and upcoming games at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
