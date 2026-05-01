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
    func placeholder(in context: Context) -> SportsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SportsEntry) -> Void) {
        if context.isPreview { completion(.placeholder); return }
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

private struct SportsWordmark: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 9, weight: .bold))
            Text("SPORTS")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .kerning(0.8)
        }
        .foregroundStyle(.secondary)
    }
}

private struct LeaguePill: View {
    let league: String
    let isLive: Bool

    var body: some View {
        HStack(spacing: 3) {
            if isLive {
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
            }
            Text(isLive ? "LIVE · \(league)" : league)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(isLive ? .red : .primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.white.opacity(0.18), in: Capsule())
    }
}

private struct GameRowView: View {
    let game: BDNWidgetSportsItem
    let isLive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                LeaguePill(league: game.league, isLive: isLive)
                HStack(spacing: 4) {
                    Text(game.awayTeam)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("@")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(game.homeTeam)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if isLive {
                    Text("\(game.awayScore)–\(game.homeScore)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(game.statusDisplay)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else if game.isFinal {
                    Text("FINAL")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text("\(game.awayScore)–\(game.homeScore)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text(game.statusDisplay)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    if !game.network.isEmpty {
                        Text(game.network)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
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
        case .systemSmall: smallView
        default:           mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            SportsWordmark()
            Spacer(minLength: 6)
            if let game = entry.games.first {
                let isLive = game.isLive && !game.isFinal
                LeaguePill(league: game.league, isLive: isLive)
                    .padding(.bottom, 4)
                Text(game.awayTeam)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("@ \(game.homeTeam)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if isLive {
                    Text("\(game.awayScore)–\(game.homeScore)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                } else if game.isFinal {
                    Text("Final \(game.awayScore)–\(game.homeScore)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text(game.statusDisplay)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            } else {
                Text("No games today")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SportsWordmark()
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            if entry.games.isEmpty {
                Spacer()
                Text("No games scheduled")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.games.prefix(2).enumerated()), id: \.element.id) { idx, game in
                    if idx > 0 {
                        Rectangle()
                            .fill(.white.opacity(0.15))
                            .frame(height: 0.5)
                    }
                    GameRowView(game: game, isLive: game.isLive && !game.isFinal)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widget declaration

struct BDNSportsWidget: Widget {
    let kind = "BDNSportsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SportsProvider()) { entry in
            BDNSportsWidgetView(entry: entry)
                .widgetURL(URL(string: "bdnapp://sports"))
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("Sports")
        .description("Live scores and upcoming games at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
