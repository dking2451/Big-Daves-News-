import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: EventStore

    private enum PendingAddDestination {
        case quickAdd
        case pasteBlank
        case pasteClipboard
        case upload
    }

    @State private var showingAddOptions = false
    @State private var pendingAddDestination: PendingAddDestination?
    @State private var showingQuickAdd = false
    @State private var showingPasteText = false
    @State private var pasteTextInitialText = ""
    @State private var pasteTextAutoExtract = false
    @State private var pasteTextSessionID = UUID()
    @State private var showingUploadSchedule = false
    @State private var expandedOccurrenceKey: String?
    @State private var isTodayExpanded = true
    @State private var isLaterExpanded = false
    private let homeHorizonDays = 5
    private let horizontalPadding: CGFloat = 16
    /// Spacing between the three top cards (and section rhythm).
    private let sectionSpacing: CGFloat = 16
    /// Shared system for Next 5 Days, Weekly Summary, Today rows, etc.
    private let homeCardCornerRadius: CGFloat = 16
    /// Slightly tighter for hero to feel intentional.
    private let homeCardPadding: CGFloat = 18

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                    NextUpView(
                        event: nextUpEvent,
                        heroSubtitle: nextUpEvent.map(nextUpHeroSubtitle(for:)),
                        onGetDirections: { destination in
                            openDirections(for: destination)
                        },
                        cornerRadius: homeCardCornerRadius,
                        contentPadding: homeCardPadding
                    )

                    DisclosureGroup(isExpanded: $isTodayExpanded) {
                        todayExpandedContent
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Today")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if !isTodayExpanded {
                                    Text(todayCollapsedPrimaryLine)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(todayCollapsedSecondaryLine)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(todayCollapsedBadgeCount)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                        }
                    }
                    .tint(.primary)

                    summaryCard
                    WeeklySummaryCard(summary: weeklySummary, cornerRadius: homeCardCornerRadius, contentPadding: homeCardPadding)

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
            .padding(.bottom, 28)
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddOptions = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Add event")
            }
        }
        .sheet(isPresented: $showingAddOptions, onDismiss: {
            guard let next = pendingAddDestination else { return }
            pendingAddDestination = nil
            switch next {
            case .quickAdd:
                showingQuickAdd = true
            case .pasteBlank:
                pasteTextInitialText = ""
                pasteTextAutoExtract = false
                pasteTextSessionID = UUID()
                showingPasteText = true
            case .pasteClipboard:
                pasteTextInitialText = UIPasteboard.general.string ?? ""
                pasteTextAutoExtract = true
                pasteTextSessionID = UUID()
                showingPasteText = true
            case .upload:
                showingUploadSchedule = true
            }
        }) {
            AddEventOptionsSheet(
                onQuickAdd: {
                    pendingAddDestination = .quickAdd
                    showingAddOptions = false
                },
                onPasteText: {
                    pendingAddDestination = .pasteBlank
                    showingAddOptions = false
                },
                onUploadImage: {
                    pendingAddDestination = .upload
                    showingAddOptions = false
                },
                onPasteFromClipboard: {
                    pendingAddDestination = .pasteClipboard
                    showingAddOptions = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddView()
        }
        .sheet(isPresented: $showingPasteText) {
            NavigationStack {
                PasteTextImportView(initialText: pasteTextInitialText, autoRunExtractionOnAppear: pasteTextAutoExtract)
                    .environmentObject(store)
                    .id(pasteTextSessionID)
            }
        }
        .sheet(isPresented: $showingUploadSchedule) {
            NavigationStack {
                UploadScheduleView()
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

    /// Flat events starting today (for conflict summary on the Today header).
    private var todayEventsFlat: [FamilyEvent] {
        let cal = Calendar.current
        return homeEvents.filter { cal.isDateInToday($0.startDateTime) }
    }

    private var todayConflictAnalysis: ConflictAnalysis {
        ConflictAnalyzer.analyze(events: todayEventsFlat)
    }

    /// Chronological grouped rows for today’s agenda.
    private var todayGroupedSorted: [GroupedEvent] {
        todayGroupedEvents.sorted { $0.primary.startDateTime < $1.primary.startDateTime }
    }

    private var todayCollapsedPrimaryLine: String {
        if todayGroupedEvents.isEmpty {
            return "You're all clear today"
        }
        let n = todayEventsFlat.count
        return "\(n) event\(n == 1 ? "" : "s") today"
    }

    private var todayCollapsedSecondaryLine: String {
        if todayGroupedEvents.isEmpty {
            return "Nothing scheduled"
        }
        let a = todayConflictAnalysis
        var parts: [String] = []
        if a.conflictedEventCount > 0 {
            parts.append("\(a.conflictedEventCount) conflict\(a.conflictedEventCount == 1 ? "" : "s")")
        }
        if a.warningEventCount > 0 {
            parts.append("\(a.warningEventCount) warning\(a.warningEventCount == 1 ? "" : "s")")
        }
        if parts.isEmpty {
            return "No conflicts"
        }
        return parts.joined(separator: " • ")
    }

    /// Badge: grouped rows when events exist (matches list), else 0.
    private var todayCollapsedBadgeCount: String {
        "\(todayGroupedEvents.isEmpty ? 0 : todayGroupedEvents.count)"
    }

    /// Next event today for insight / highlight (upcoming start, else in-progress).
    private var nextTodayEventForHighlight: FamilyEvent? {
        let now = Date()
        let events = todayGroupedSorted.map(\.primary)
        if let upcoming = events.first(where: { $0.startDateTime >= now }) {
            return upcoming
        }
        return events.first(where: { $0.endDateTime >= now })
    }

    private var nextTodayHighlightedGroupedID: GroupedEvent.ID? {
        guard let target = nextTodayEventForHighlight else { return nil }
        return todayGroupedSorted.first(where: { $0.primary.id == target.id })?.id
    }

    /// Deterministic one-line insight when Today is expanded.
    private var todayDailyInsightLine: String? {
        guard !todayGroupedEvents.isEmpty else { return nil }
        let analysis = todayConflictAnalysis
        let primaries = todayGroupedSorted.map(\.primary)

        if let next = nextTodayEventForHighlight {
            let t = next.startDateTime.formatted(date: .omitted, time: .shortened)
            let title = next.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Event" : next.title
            return "Next: \(title) at \(t)"
        }
        if analysis.conflictedEventCount > 0 {
            return "Overlapping times today"
        }
        if analysis.warningEventCount > 0 {
            return "Tight turns between events"
        }
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let afternoonStarts = primaries.filter { $0.startDateTime >= noon }.count
        if primaries.count >= 3, afternoonStarts >= 2 {
            return "Busy afternoon ahead"
        }
        return "No conflicts today"
    }

    @ViewBuilder
    private var todayExpandedContent: some View {
        if todayGroupedEvents.isEmpty {
            todayEmptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let line = todayDailyInsightLine {
                    Text(line)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if todayConflictAnalysis.conflictedEventCount > 0 || todayConflictAnalysis.warningEventCount > 0 {
                    todayScheduleIssuesRow
                }

                ForEach(todayGroupedSorted) { grouped in
                    compactEventRow(
                        for: grouped,
                        showsDayContext: false,
                        isNextToday: grouped.id == nextTodayHighlightedGroupedID
                    )
                }
            }
        }
    }

    private var todayScheduleIssuesRow: some View {
        let a = todayConflictAnalysis
        return HStack(spacing: 10) {
            if a.conflictedEventCount > 0 {
                Label(
                    "\(a.conflictedEventCount) conflict\(a.conflictedEventCount == 1 ? "" : "s")",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }
            if a.warningEventCount > 0 {
                Label(
                    "\(a.warningEventCount) warning\(a.warningEventCount == 1 ? "" : "s")",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.yellow)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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

    private func compactEventRow(for grouped: GroupedEvent, showsDayContext: Bool, isNextToday: Bool = false) -> some View {
        let event = grouped.primary
        let key = occurrenceKey(for: event)
        let isExpanded = expandedOccurrenceKey == key
        let accent = familyRowAccent(for: grouped)
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(0.85))
                .frame(width: isNextToday ? 4 : 3)

            VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedOccurrenceKey = isExpanded ? nil : key
                }
            } label: {
                HStack(spacing: 8) {
                    Text(event.title)
                        .font(isNextToday ? .body.weight(.bold) : .body.weight(.semibold))
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
                            text: event.assignment.rowLabel,
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
        .background(
            RoundedRectangle(cornerRadius: homeCardCornerRadius, style: .continuous)
                .fill(isNextToday ? Color(.tertiarySystemFill) : Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: homeCardCornerRadius, style: .continuous)
                .stroke(accent.opacity(isNextToday ? 0.4 : 0.24), lineWidth: isNextToday ? 1.5 : 1)
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

    /// e.g. `Tomorrow • 8:00 AM` — scannable, no “at”.
    private func nextUpHeroSubtitle(for event: FamilyEvent) -> String {
        let relative = formatRelativeDate(event.startDateTime)
        let time = event.startDateTime.formatted(date: .omitted, time: .shortened)
        return "\(relative) • \(time)"
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
            nextEventStartsAtLine: nextEvent.map { $0.startDateTime.formatted(date: .abbreviated, time: .shortened) },
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
        let n = busiest.value
        return "\(dayText) • \(n) event\(n == 1 ? "" : "s")"
    }

    private var summaryCard: some View {
        let count = homeEvents.count
        return VStack(alignment: .leading, spacing: 10) {
            homeCardSectionTitle("Next \(homeHorizonDays) Days")
            Text(horizonCalmHeadline(eventCount: count))
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if count > 0 {
                Text("\(count) event\(count == 1 ? "" : "s") in this window")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(homeCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(homeCardBackground(cornerRadius: homeCardCornerRadius))
    }

    private func horizonCalmHeadline(eventCount: Int) -> String {
        switch eventCount {
        case 0:
            return "Nothing scheduled in this window yet."
        case 1...3:
            return "A lighter stretch ahead."
        case 4...9:
            return "A few things on the radar."
        default:
            return "Busy week ahead."
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var todayEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You're all clear today")
                .font(.headline)
            Text("No events scheduled. Enjoy the calm—or add something with the + button.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showingAddOptions = true
            } label: {
                Label("Add event", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(homeCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(homeCardBackground(cornerRadius: homeCardCornerRadius))
    }

    @ViewBuilder
    private func homeCardSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
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
    let nextEventStartsAtLine: String?
    let busiestDayText: String?

    var hasEvents: Bool { totalEvents > 0 }
}

private struct NextUpView: View {
    let event: FamilyEvent?
    let heroSubtitle: String?
    let onGetDirections: (String) -> Void
    let cornerRadius: CGFloat
    let contentPadding: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Next Up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let event {
                NavigationLink {
                    EventDetailView(event: event)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(event.title.isEmpty ? "Untitled Event" : event.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)

                        Text(heroSubtitle ?? "Upcoming")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        if !event.childName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("For \(event.childName)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
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
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Get directions to \(trimmedLocation)")
                }
            } else {
                Text("You're all clear")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Nothing coming up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct WeeklySummaryCard: View {
    let summary: WeeklySummarySnapshot
    let cornerRadius: CGFloat
    let contentPadding: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weekly Summary")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if !summary.hasEvents {
                Text("No events in the next 7 days.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    summaryItem(label: "Events", value: "\(summary.totalEvents)")
                    summaryItem(label: "Conflicted Events", value: "\(summary.conflictCount)")
                }

                if summary.warningCount > 0 {
                    Text("\(summary.warningCount) schedule warning\(summary.warningCount == 1 ? "" : "s") this week")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next Event")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                        if let title = summary.nextEventTitle {
                            Text(title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            if let line = summary.nextEventStartsAtLine {
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("None")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Busiest Day")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                        Text(summary.busiestDayText ?? "—")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func summaryItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
