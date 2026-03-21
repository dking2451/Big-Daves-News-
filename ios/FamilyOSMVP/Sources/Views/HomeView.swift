import SwiftUI

struct HomeView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: EventStore
    @State private var showingQuickAdd = false
    @State private var showingManualAdd = false
    @State private var showingPasteText = false
    @State private var expandedOccurrenceKey: String?
    @State private var isLaterExpanded = false
    private let homeHorizonDays = 5
    private let horizontalPadding: CGFloat = 16
    private let sectionSpacing: CGFloat = 18
    private let cardCornerRadius: CGFloat = 14

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    NextUpView(
                        event: nextUpEvent,
                        timeText: nextUpEvent.map(nextUpTimeText(for:)),
                        onGetDirections: { destination in
                            openDirections(for: destination)
                        },
                        cornerRadius: cardCornerRadius
                    )
                    summaryCard
                    WeeklySummaryCard(summary: weeklySummary, cornerRadius: cardCornerRadius)

                    sectionHeader("Today")

                    if todayGroupedEvents.isEmpty {
                        todayEmptyState
                    } else {
                        ForEach(todayGroupedEvents) { grouped in
                            compactEventRow(for: grouped, showsDayContext: false)
                        }
                    }

                    DisclosureGroup(isExpanded: $isLaterExpanded) {
                        if laterGroupedEvents.isEmpty {
                            Text("Nothing later in the next \(homeHorizonDays) days.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                        } else {
                            ForEach(laterGroupedEvents) { grouped in
                                compactEventRow(for: grouped, showsDayContext: true)
                            }
                        }
                    } label: {
                        HStack {
                            sectionHeader("Later")
                            Spacer()
                            Text("\(laterGroupedEvents.count)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                        }
                    }
                    .tint(.primary)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 88)
            }

            Button {
                showingQuickAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quick add event")
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showingPasteText = true
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Paste event text")

                    Button {
                        showingManualAdd = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Open full add event form")
                }
            }
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddView()
        }
        .sheet(isPresented: $showingPasteText) {
            NavigationStack {
                PasteTextImportView()
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showingManualAdd) {
            NavigationStack {
                ManualAddEventView()
            }
        }
    }

    private func openDirections(for destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let url = URL(string: "http://maps.apple.com/?daddr=\(encoded)&dirflg=d") else { return }
        openURL(url)
    }

    private var homeEvents: [FamilyEvent] {
        store.eventsInNextDays(homeHorizonDays)
    }

    private var nextUpEvent: FamilyEvent? {
        getNextEvent(events: store.upcomingEvents())
    }

    private var weeklySummary: WeeklySummarySnapshot {
        computeWeeklySummary(from: store.eventsInNextDays(7), now: Date())
    }

    private var todayGroupedEvents: [GroupedEvent] {
        groupedHomeEvents.filter { Calendar.current.isDateInToday($0.primary.startDateTime) }
    }

    private var laterGroupedEvents: [GroupedEvent] {
        groupedHomeEvents.filter { !Calendar.current.isDateInToday($0.primary.startDateTime) }
    }

    private var groupedHomeEvents: [GroupedEvent] {
        EventDisplayGrouping.groupedDisplayEvents(events: homeEvents)
    }

    private func compactEventRow(for grouped: GroupedEvent, showsDayContext: Bool) -> some View {
        let event = grouped.primary
        let key = occurrenceKey(for: event)
        let isExpanded = expandedOccurrenceKey == key
        let accent = familyRowAccent(for: grouped)
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(0.85))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedOccurrenceKey = isExpanded ? nil : key
                }
            } label: {
                HStack(spacing: 8) {
                    Text(event.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(event.startDateTime.formatted(date: .omitted, time: .shortened))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if showsDayContext {
                            Text(laterDayContext(for: event.startDateTime))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: grouped, showsDayContext: showsDayContext))

            if isExpanded {
                Divider()

                if grouped.combinedCount > 1, !grouped.isCrossChildFamilyMoment {
                    Text("Combined from \(grouped.combinedCount) similar entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    if event.recurrenceRule != .none {
                        homeMetaChip(text: event.recurrenceRule.displayName, systemName: "repeat", tint: .indigo)
                    }
                    if event.assignment != .unassigned {
                        homeMetaChip(
                            text: event.assignment.displayName,
                            systemName: event.assignment.chipIconSystemName,
                            tint: event.assignment.chipTint
                        )
                    }
                    homeMetaChip(
                        text: event.category.displayName,
                        systemName: categoryIcon(for: event.category),
                        tint: categoryColor(for: event.category)
                    )
                    if grouped.isCrossChildFamilyMoment {
                        homeMetaChip(
                            text: grouped.childNamesDisplayLine(),
                            systemName: "person.3.fill",
                            tint: .secondary
                        )
                    } else if !event.childName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        homeMetaChip(text: event.childName, systemName: "person.fill", tint: .secondary)
                    }
                }

                if !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 8) {
                        Label(event.location, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            openDirections(for: event.location)
                        } label: {
                            Image(systemName: "location.north.line.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Get directions to \(event.location)")
                    }
                }

                NavigationLink {
                    EventDetailView(event: event)
                } label: {
                    Label("View details", systemImage: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        }
        .padding(12)
        .background(homeCardBackground(cornerRadius: cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .stroke(accent.opacity(0.24), lineWidth: 1)
        }
    }

    private func familyRowAccent(for grouped: GroupedEvent) -> Color {
        if grouped.isCrossChildFamilyMoment { return Color.accentColor }
        return childColor(for: grouped.primary)
    }

    private func occurrenceKey(for event: FamilyEvent) -> String {
        "\(event.id.uuidString)-\(Int(event.startDateTime.timeIntervalSince1970))"
    }

    private func getNextEvent(events: [FamilyEvent]) -> FamilyEvent? {
        let now = Date()
        let indexed = events.enumerated().filter { _, event in
            event.startDateTime >= now
        }
        guard !indexed.isEmpty else { return nil }
        let best = indexed.min { lhs, rhs in
            if lhs.element.startDateTime == rhs.element.startDateTime {
                return lhs.offset < rhs.offset
            }
            return lhs.element.startDateTime < rhs.element.startDateTime
        }
        return best?.element
    }

    private func formatRelativeDate(_ eventDate: Date) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfEvent = calendar.startOfDay(for: eventDate)
        let dayOffset = calendar.dateComponents([.day], from: startOfToday, to: startOfEvent).day ?? 0

        switch dayOffset {
        case ..<1:
            return "Today"
        case 1:
            return "Tomorrow"
        default:
            return "In \(dayOffset) days"
        }
    }

    private func nextUpTimeText(for event: FamilyEvent) -> String {
        let relative = formatRelativeDate(event.startDateTime)
        let time = event.startDateTime.formatted(date: .omitted, time: .shortened)
        return "\(relative) at \(time)"
    }

    private func laterDayContext(for date: Date) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfEventDay = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfEventDay).day ?? 0

        let relativeText: String
        switch days {
        case 0:
            relativeText = "Today"
        case 1:
            relativeText = "Tomorrow"
        default:
            relativeText = "In \(days) days"
        }

        let dayText = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(relativeText) · \(dayText)"
    }

    private func accessibilityLabel(for grouped: GroupedEvent, showsDayContext: Bool) -> String {
        let event = grouped.primary
        let timeText = event.startDateTime.formatted(date: .omitted, time: .shortened)
        let kids = grouped.isCrossChildFamilyMoment ? ", \(grouped.childNamesDisplayLine())" : ""
        if showsDayContext {
            return "\(event.title)\(kids), \(laterDayContext(for: event.startDateTime)), \(timeText)"
        }
        return "\(event.title)\(kids), \(timeText)"
    }

    private func categoryIcon(for category: EventCategory) -> String {
        switch category {
        case .school: return "graduationcap.fill"
        case .sports: return "figure.run"
        case .medical: return "cross.case.fill"
        case .social: return "person.2.fill"
        case .other: return "sparkles"
        }
    }

    private func categoryColor(for category: EventCategory) -> Color {
        switch category {
        case .school: return .blue
        case .sports: return .green
        case .medical: return .red
        case .social: return .purple
        case .other: return .gray
        }
    }

    private func childColor(for event: FamilyEvent) -> Color {
        let child = event.childName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !child.isEmpty else { return .primary }
        let token = store.childColorToken(for: child)
        return ChildColorPalette.color(for: token)
    }

    private func computeWeeklySummary(from events: [FamilyEvent], now: Date) -> WeeklySummarySnapshot {
        let sorted = events.sorted { $0.startDateTime < $1.startDateTime }
        let totalEvents = sorted.count
        let analysis = ConflictAnalyzer.analyze(events: sorted)
        let conflictCount = analysis.conflictedEventCount
        let warningCount = analysis.warningEventCount
        let nextEvent = sorted.first(where: { $0.endDateTime >= now })
        let busiestDay = busiestDayText(in: sorted)

        return WeeklySummarySnapshot(
            totalEvents: totalEvents,
            conflictCount: conflictCount,
            warningCount: warningCount,
            nextEventTitle: nextEvent?.title,
            nextEventTimeText: nextEvent?.startDateTime.formatted(date: .abbreviated, time: .shortened),
            busiestDayText: busiestDay
        )
    }

    private func busiestDayText(in events: [FamilyEvent]) -> String? {
        guard !events.isEmpty else { return nil }
        let calendar = Calendar.current
        let countsByDay = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startDateTime)
        }.mapValues(\.count)

        guard
            let busiest = countsByDay.max(by: { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key > rhs.key
                }
                return lhs.value < rhs.value
            })
        else {
            return nil
        }

        let dayText = busiest.key.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(dayText) (\(busiest.value))"
    }

    private var summaryCard: some View {
        let weekEvents = homeEvents
        return VStack(alignment: .leading, spacing: 8) {
            Text("Next \(homeHorizonDays) Days")
                .font(.headline)
            Text("\(weekEvents.count) upcoming event\(weekEvents.count == 1 ? "" : "s")")
                .font(.title2.weight(.bold))
            Text("Focused view for critical and timely family events.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(homeCardBackground(cornerRadius: cardCornerRadius))
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var todayEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No events today")
                .font(.headline)
            Text("You're all clear for now. Add a quick event anytime.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button {
                showingQuickAdd = true
            } label: {
                Label("Quick Add", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(homeCardBackground(cornerRadius: cardCornerRadius))
    }

    @ViewBuilder
    private func homeCardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func homeMetaChip(text: String, systemName: String, tint: Color) -> some View {
        Label(text, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }
}

private struct WeeklySummarySnapshot {
    let totalEvents: Int
    let conflictCount: Int
    let warningCount: Int
    let nextEventTitle: String?
    let nextEventTimeText: String?
    let busiestDayText: String?

    var hasEvents: Bool { totalEvents > 0 }
}

private struct NextUpView: View {
    let event: FamilyEvent?
    let timeText: String?
    let onGetDirections: (String) -> Void
    let cornerRadius: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next Up")
                .font(.headline)

            if let event {
                NavigationLink {
                    EventDetailView(event: event)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title.isEmpty ? "Untitled Event" : event.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(timeText ?? "Upcoming")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        if !event.childName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(event.childName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                let trimmedLocation = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLocation.isEmpty {
                    Button {
                        onGetDirections(trimmedLocation)
                    } label: {
                        Label("Directions", systemImage: "mappin.and.ellipse")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Get directions to \(trimmedLocation)")
                }
            } else {
                Text("You're all clear")
                    .font(.headline)
                Text("No upcoming events")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct WeeklySummaryCard: View {
    let summary: WeeklySummarySnapshot
    let cornerRadius: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly Summary")
                .font(.headline)

            if !summary.hasEvents {
                Text("No events in the next 7 days.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    summaryItem(label: "Events", value: "\(summary.totalEvents)")
                    Spacer()
                    summaryItem(label: "Conflicted Events", value: "\(summary.conflictCount)")
                }

                if summary.warningCount > 0 {
                    Text("\(summary.warningCount) schedule warning\(summary.warningCount == 1 ? "" : "s") this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Next")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(nextEventLine)
                        .font(.body.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Busiest Day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.busiestDayText ?? "N/A")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var nextEventLine: String {
        guard let title = summary.nextEventTitle else { return "No upcoming event" }
        guard let time = summary.nextEventTimeText else { return title }
        return "\(title) • \(time)"
    }

    private func summaryItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
        }
    }
}
