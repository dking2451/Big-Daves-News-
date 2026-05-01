import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct HeadlineEntry: TimelineEntry {
    let date: Date
    let headlines: [BDNWidgetClaim]

    static let placeholder = HeadlineEntry(
        date: Date(),
        headlines: [
            BDNWidgetClaim(id: "1", headline: "Senate passes sweeping infrastructure bill after marathon session", subtopic: "Politics", sourceName: "AP News"),
            BDNWidgetClaim(id: "2", headline: "Fed signals pause on rate hikes as inflation cools", subtopic: "Business", sourceName: "Reuters"),
            BDNWidgetClaim(id: "3", headline: "NASA confirms water ice deposits near lunar south pole", subtopic: "Science", sourceName: "The Verge"),
            BDNWidgetClaim(id: "4", headline: "World leaders gather for emergency climate summit", subtopic: "World", sourceName: "BBC"),
        ]
    )
}

// MARK: - Timeline Provider

struct HeadlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeadlineEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (HeadlineEntry) -> Void) {
        if context.isPreview { completion(.placeholder); return }
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

private struct BDNWordmark: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 9, weight: .bold))
            Text("BIG DAVE'S")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .kerning(0.8)
        }
        .foregroundStyle(.secondary)
    }
}

private struct SubtopicPill: View {
    let label: String
    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(0.18), in: Capsule())
    }
}

private struct HeadlineRowView: View {
    let claim: BDNWidgetClaim
    let isFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !isFirst {
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(height: 0.5)
                    .padding(.bottom, 1)
            }
            if !claim.subtopic.isEmpty && isFirst {
                SubtopicPill(label: claim.subtopic)
                    .padding(.bottom, 1)
            }
            Text(claim.headline)
                .font(.system(size: isFirst ? 13 : 11, weight: isFirst ? .semibold : .medium))
                .foregroundStyle(.primary)
                .lineLimit(isFirst ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)
            if !claim.sourceName.isEmpty {
                Text(claim.sourceName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
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
        VStack(alignment: .leading, spacing: 0) {
            BDNWordmark()
            Spacer(minLength: 6)
            if let first = entry.headlines.first {
                if !first.subtopic.isEmpty {
                    SubtopicPill(label: first.subtopic)
                        .padding(.bottom, 5)
                }
                Text(first.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(first.sourceName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Fetching stories...")
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
                BDNWordmark()
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            if entry.headlines.isEmpty {
                Spacer()
                Text("No headlines available")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.headlines.prefix(2).enumerated()), id: \.element.id) { idx, claim in
                    HeadlineRowView(claim: claim, isFirst: idx == 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                BDNWordmark()
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            ForEach(Array(entry.headlines.enumerated()), id: \.element.id) { idx, claim in
                HeadlineRowView(claim: claim, isFirst: idx == 0)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("Top Headlines")
        .description("Stay on top of the day's biggest stories.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}
