import SwiftUI
import UIKit

// MARK: - Day grouping (timeline)

private struct UpcomingDaySection: Identifiable {
    let dayStart: Date
    let groups: [GroupedEvent]
    var id: Date { dayStart }
}

struct UpcomingEventsView: View {
    enum CategoryFilter: String, CaseIterable, Identifiable {
        case all
        case school
        case sports
        case medical
        case social
        case other

        var id: String { rawValue }

        var chipTitle: String {
            rawValue == "all" ? "All" : rawValue.capitalized
        }

        var eventCategory: EventCategory? {
            rawValue == "all" ? nil : EventCategory(rawValue: rawValue)
        }
    }

    enum AssignmentFilter: String, CaseIterable, Identifiable {
        case all
        case mom
        case dad
        case either
        case unassigned

        var id: String { rawValue }

        var chipTitle: String {
            switch self {
            case .all: return "All"
            case .mom: return "Mom"
            case .dad: return "Dad"
            case .either: return "Either"
            case .unassigned: return "None"
            }
        }

        func matches(_ event: FamilyEvent) -> Bool {
            switch self {
            case .all:
                return true
            case .mom:
                return event.assignment == .mom
            case .dad:
                return event.assignment == .dad
            case .either:
                return event.assignment == .either
            case .unassigned:
                return event.assignment == .unassigned
            }
        }
    }

    enum RecurrenceFilter: String, CaseIterable, Identifiable {
        case all
        case recurringOnly
        case oneTimeOnly
        case conflictsOnly

        var id: String { rawValue }

        var chipTitle: String {
            switch self {
            case .all: return "All"
            case .recurringOnly: return "Repeating"
            case .oneTimeOnly: return "One-time"
            case .conflictsOnly: return "Conflicts"
            }
        }
    }

    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: EventStore

    @State private var selectedChild: String = "All Children"
    @State private var selectedCategory: CategoryFilter = .all
    @State private var selectedAssignment: AssignmentFilter = .all
    @State private var selectedRecurrence: RecurrenceFilter = .all
    @State private var isFilterSheetPresented = false

    var body: some View {
        List {
            if hasActiveFilters {
                Section {
                    activeFiltersSummaryRow
                }
                .listSectionSpacing(8)
            }

            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    "No upcoming events",
                    systemImage: "calendar",
                    description: Text("Try different filters or add events from Home.")
                )
            } else {
                let analysis = conflictAnalysis
                ForEach(daySections) { section in
                    Section {
                        ForEach(section.groups) { grouped in
                            eventRow(grouped: grouped, analysis: analysis)
                        }
                    } header: {
                        daySectionHeader(
                            dayStart: section.dayStart,
                            groups: section.groups,
                            analysis: analysis
                        )
                    }
                }
            }
        }
        .listSectionSpacing(14)
        .navigationTitle("Upcoming")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    if pendingCount > 0 {
                        NavigationLink(destination: PendingImportsView()) {
                            pendingIcon(count: pendingCount)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(pendingCount) pending imports")
                    }

                    familyBrandIcon

                    Button {
                        isFilterSheetPresented = true
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityHint("Opens filters for child, category, assignment, and schedule")
                }
            }
        }
        .sheet(isPresented: $isFilterSheetPresented) {
            NavigationStack {
                filterSheetContent
                    .navigationTitle("Filters")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            if hasActiveFilters {
                                Button("Clear All") {
                                    clearAllFilters()
                                }
                                .accessibilityLabel("Clear all filters")
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                isFilterSheetPresented = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var pendingCount: Int {
        PendingImportQueue.load().count
    }

    @ViewBuilder
    private var familyBrandIcon: some View {
        if let image = resolvedIconImage {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityLabel("Family OS")
        } else {
            Image(systemName: "house.and.flag.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FamilyTheme.accent)
                .accessibilityLabel("Family OS")
        }
    }

    private var resolvedIconImage: UIImage? {
        UIImage(named: "AppIcon")
            ?? UIImage(named: "icon-60")
            ?? UIImage(named: "icon-120")
            ?? UIImage(named: "icon-180")
    }

    private func pendingIcon(count: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FamilyTheme.accent)
                .frame(width: 24, height: 24)

            Text("\(min(count, 99))")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Circle().fill(Color.red))
                .offset(x: 10, y: -8)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Active filters (compact)

    private func clearAllFilters() {
        selectedChild = "All Children"
        selectedCategory = .all
        selectedAssignment = .all
        selectedRecurrence = .all
    }

    private var hasActiveFilters: Bool {
        selectedChild != "All Children"
            || selectedCategory != .all
            || selectedAssignment != .all
            || selectedRecurrence != .all
    }

    private var activeFilterSummaryText: String {
        var parts: [String] = []
        if selectedChild != "All Children" {
            parts.append(selectedChild)
        }
        if selectedCategory != .all {
            parts.append(selectedCategory.chipTitle)
        }
        if selectedAssignment != .all {
            parts.append(selectedAssignment.chipTitle)
        }
        if selectedRecurrence != .all {
            parts.append(selectedRecurrence.chipTitle)
        }
        return parts.joined(separator: " • ")
    }

    private var activeFiltersSummaryRow: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(activeFilterSummaryText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active filters: \(activeFilterSummaryText)")
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
    }

    // MARK: - Filter sheet (same logic as before; presentation only)

    private var filterSheetContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                filterLabel("Child")
                chipScrollRow {
                    filterChip("All", isSelected: selectedChild == "All Children") {
                        selectedChild = "All Children"
                    }
                    ForEach(childNamesForChips, id: \.self) { name in
                        filterChip(name, isSelected: selectedChild == name) {
                            selectedChild = name
                        }
                    }
                }

                filterLabel("Category")
                chipScrollRow {
                    ForEach(CategoryFilter.allCases) { filter in
                        filterChip(filter.chipTitle, isSelected: selectedCategory == filter) {
                            selectedCategory = filter
                        }
                    }
                }

                filterLabel("Assigned")
                chipScrollRow {
                    ForEach(AssignmentFilter.allCases) { filter in
                        filterChip(filter.chipTitle, isSelected: selectedAssignment == filter) {
                            selectedAssignment = filter
                        }
                    }
                }

                filterLabel("Schedule")
                chipScrollRow {
                    ForEach(RecurrenceFilter.allCases) { filter in
                        filterChip(filter.chipTitle, isSelected: selectedRecurrence == filter) {
                            selectedRecurrence = filter
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func filterLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func chipScrollRow(@ViewBuilder content: () -> some View) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(isSelected ? FamilyTheme.accent : Color(.secondarySystemBackground)))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - Day headers & rows

    private func daySectionHeader(dayStart: Date, groups: [GroupedEvent], analysis: ConflictAnalysis) -> some View {
        let conflicts = groups.filter { analysis.hasConflict($0.primary) }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(daySectionTitle(dayStart))
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                Text("\(groups.count) event\(groups.count == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if conflicts > 0 {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(conflicts) conflict\(conflicts == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textCase(nil)
    }

    private func daySectionTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func eventRow(grouped: GroupedEvent, analysis: ConflictAnalysis) -> some View {
        let event = grouped.primary
        let hasConflict = analysis.hasConflict(event)
        let hasWarning = !hasConflict && analysis.hasWarning(event)
        return NavigationLink {
            EventDetailView(event: event)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                EventCard(
                    event: event,
                    showsConflictBadge: hasConflict,
                    showsWarningBadge: hasWarning,
                    combinedCount: grouped.isCrossChildFamilyMoment ? 1 : grouped.combinedCount,
                    childNamesDisplayLine: grouped.isCrossChildFamilyMoment ? grouped.childNamesDisplayLine() : nil,
                    childAccentColor: grouped.isCrossChildFamilyMoment ? FamilyTheme.accent : childColor(for: event),
                    onGetDirections: event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : { openDirections(for: event.location) },
                    nearTermHighlight: isNearTerm(event)
                )
                if hasConflict, let summary = conflictSummary(for: event, from: analysis) {
                    Label(summary, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if hasWarning, let summary = warningSummary(for: event, from: analysis) {
                    Label(summary, systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private var daySections: [UpcomingDaySection] {
        let cal = Calendar.current
        var buckets: [Date: [GroupedEvent]] = [:]
        for g in filteredEvents {
            let day = cal.startOfDay(for: g.primary.startDateTime)
            buckets[day, default: []].append(g)
        }
        let sortedDays = buckets.keys.sorted()
        return sortedDays.map { day in
            let sorted = buckets[day]!.sorted { $0.primary.startDateTime < $1.primary.startDateTime }
            return UpcomingDaySection(dayStart: day, groups: sorted)
        }
    }

    private var baseEvents: [FamilyEvent] {
        store.upcomingEvents()
    }

    private var groupedBaseEvents: [GroupedEvent] {
        EventDisplayGrouping.groupedDisplayEvents(events: baseEvents)
    }

    private var filteredEvents: [GroupedEvent] {
        let analysis = conflictAnalysis
        return groupedBaseEvents.filter { grouped in
            let event = grouped.primary
            let matchesChild: Bool
            if selectedChild == "All Children" {
                matchesChild = true
            } else {
                matchesChild = grouped.events.contains { $0.childName == selectedChild }
            }
            let matchesCategory = selectedCategory.eventCategory == nil || event.category == selectedCategory.eventCategory
            let matchesAssignment = selectedAssignment.matches(event)
            let matchesRecurrence: Bool
            switch selectedRecurrence {
            case .all:
                matchesRecurrence = true
            case .recurringOnly:
                matchesRecurrence = event.recurrenceRule != .none
            case .oneTimeOnly:
                matchesRecurrence = event.recurrenceRule == .none
            case .conflictsOnly:
                matchesRecurrence = analysis.hasConflict(event)
            }
            return matchesChild && matchesCategory && matchesAssignment && matchesRecurrence
        }
    }

    private var childNamesForChips: [String] {
        availableChildren.filter { $0 != "All Children" }
    }

    private var availableChildren: [String] {
        let names = Set(
            groupedBaseEvents
                .flatMap(\.events)
                .map(\.childName)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
        return ["All Children"] + names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var conflictAnalysis: ConflictAnalysis {
        ConflictAnalyzer.analyze(events: baseEvents)
    }

    private func isNearTerm(_ event: FamilyEvent) -> Bool {
        event.startDateTime <= Date().addingTimeInterval(24 * 60 * 60)
    }

    private func childColor(for event: FamilyEvent) -> Color {
        let child = event.childName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !child.isEmpty else { return .primary }
        let token = store.childColorToken(for: child)
        return ChildColorPalette.color(for: token)
    }

    private func conflictSummary(for event: FamilyEvent, from analysis: ConflictAnalysis) -> String? {
        let counterparts = analysis.conflicts(for: event)
        guard let first = counterparts.first else { return nil }
        let firstTime = first.startDateTime.formatted(date: .omitted, time: .shortened)
        if counterparts.count == 1 {
            return "Conflict with \(first.title) at \(firstTime)"
        }
        return "Conflicts with \(first.title) and \(counterparts.count - 1) more"
    }

    private func warningSummary(for event: FamilyEvent, from analysis: ConflictAnalysis) -> String? {
        let counterparts = analysis.warnings(for: event)
        guard let first = counterparts.first else { return nil }
        if counterparts.count == 1 {
            return "Tight transition after \(first.title)"
        }
        return "Tight transition after \(first.title) and \(counterparts.count - 1) more"
    }

    private func openDirections(for destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let url = URL(string: "http://maps.apple.com/?daddr=\(encoded)&dirflg=d") else { return }
        openURL(url)
    }
}
