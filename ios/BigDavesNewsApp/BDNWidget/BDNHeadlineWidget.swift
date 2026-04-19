import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct HeadlineEntry: TimelineEntry {
    let date: Date
    let headlines: [BDNWidgetClaim]

    static let placeholder = HeadlineEntry(
        date: Date(),
        headlines: [
            BDNWidgetClaim(id: "1", headline: "Top story of the day from Big Dave's News", subtopic: "General", sourceName: "AP News"),
            BDNWidgetClaim(id: "2", headline: "Second major headline of the morning", subtopic: "Politics", sourceName: "Reuters"),
            BDNWidgetClaim(id: "3", headline: "Breaking: Third headline loads here", subtopic: "Tech", sourceName: "The Verge"),
            BDNWidgetClaim(id: "4", headline: "World news: Fourth story of the day", subtopic: "World", sourceName: "BBC"),
        ]
    )
}

// MARK: - Timeline Provider

struct HeadlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeadlineEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadlineEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task {
            let headlines = await fetchWidgetHeadlines()
            completion(HeadlineEntry(date: Date(), headlines: headlines))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadlineEntry>) -> Void) {
        Task {
            let headlines = await fetchWidgetHeadlines()
            let entry = HeadlineEntry(date: Date(), headlines: headlines)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }
}

// MARK: - Shared components

private struct BDNBrandMark: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
            Text("BIG DAVE'S")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .kerning(0.5)
        }
    }
}

private struct HeadlineRowView: View {
    let claim: BDNWidgetClaim
    let isFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if \!isFirst {
                Divider()
                    .background(.white.opacity(0.15))
                    .padding(.bottom, 2)
            }
            Text(claim.headline)
                .font(.system(size: isFirst ? 13 : 12, weight: isFirst ? .semibold : .regular))
                .foregroundStyle(.white)
                .lineLimit(isFirst ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)
            Text(claim.sourceName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Widget Views

struct BDNHeadlineWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: HeadlineEntry

    var body: some View {
        switch family {
        case .systemSmall:           smallView
        case .systemMedium:          mediumView
        case .systemLarge:           largeView
        case .accessoryCircular:     accessoryCircularView
        case .accessoryRectangular:  accessoryRectangularView
        case .accessoryInline:       accessoryInlineView
        default:                     smallView
        }
    }

    private var smallView: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.09, blue: 0.18),
                    Color(red: 0.13, green: 0.20, blue: 0.42),
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            VStack(alignment: .leading, spacing: 0) {
                BDNBrandMark()
                Spacer()
                if let first = entry.headlines.first {
                    Text(first.headline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(first.sourceName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 4)
                } else {
                    Text("Loading headlines…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(14)
        }
    }

    private var mediumView: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.09, blue: 0.18),
                    Color(red: 0.13, green: 0.20, blue: 0.42),
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                BDNBrandMark()
                ForEach(Array(entry.headlines.prefix(2).enumerated()), id: \.element.id) { idx, claim in
                    HeadlineRowView(claim: claim, isFirst: idx == 0)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private var largeView: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.09, blue: 0.18),
                    Color(red: 0.13, green: 0.20, blue: 0.42),
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            VStack(alignment: .leading, spacing: 10) {
                BDNBrandMark()
                ForEach(Array(entry.headlines.enumerated()), id: \.element.id) { idx, claim in
                    HeadlineRowView(claim: claim, isFirst: idx == 0)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("BDN")
                    .font(.system(size: 9, weight: .black, design: .rounded))
            }
        }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Big Dave's News", systemImage: "newspaper.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(entry.headlines.first?.headline ?? "Top headlines")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessoryInlineView: some View {
        Label(
            entry.headlines.first?.headline ?? "Top headlines",
            systemImage: "newspaper.fill"
        )
        .lineLimit(1)
    }
}

// MARK: - Widget declaration

struct BDNHeadlineWidget: Widget {
    let kind = "BDNHeadlineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HeadlineProvider()) { entry in
            BDNHeadlineWidgetView(entry: entry)
                .widgetURL(URL(string: "bdnapp://headlines"))
                .containerBackground(
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.09, blue: 0.18),
                            Color(red: 0.13, green: 0.20, blue: 0.42),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    for: .widget
                )
        }
        .configurationDisplayName("Top Headlines")
        .description("Stay on top of the day's biggest stories.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}
