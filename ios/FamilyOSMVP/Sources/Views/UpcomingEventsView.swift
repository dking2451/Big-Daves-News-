import SwiftUI

struct UpcomingEventsView: View {
    enum CategoryFilter: String, CaseIterable, Identifiable {
        case all
        case school
        case sports
        case medical
        case social
        case other

        var id: String { rawValue }

        var label: String {
            rawValue == "all" ? "All Categories" : rawValue.capitalized
        }

        var iconName: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .school: return "graduationcap.fill"
            case .sports: return "figure.run"
            case .medical: return "cross.case.fill"
            case .social: return "person.2.fill"
            case .other: return "sparkles"
            }
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

        var label: String {
            switch self {
            case .all: return "All assignments"
            case .mom: return "Mom"
            case .dad: return "Dad"
            case .either: return "Either"
            case .unassigned: return "Unassigned"
            }
        }

        var iconName: String {
            switch self {
            case .all: return "person.3.fill"
            case .mom: return "figure.dress.line.vertical.figure"
            case .dad: return "figure"
            case .either: return "person.2.fill"
            case .unassigned: return "questionmark.circle"
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

        var label: String {
            switch self {
            case .all: return "All Events"
            case .recurringOnly: return "Recurring Only"
            case .oneTimeOnly: return "One-Time Only"
            case .conflictsOnly: return "Conflicts Only"
            }
        }

        var iconName: String {
            switch self {
            case .all: return "line.3.horizontal.decrease.circle"
            case .recurringOnly: return "repeat"
            case .oneTimeOnly: return "calendar"
            case .conflictsOnly: return "exclamationmark.triangle.fill"
            }
        }
    }

    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: EventStore

    @State private var selectedChild: String = "All Children"
    @State private var selectedCategory: CategoryFilter = .all
    @State private var selectedAssignment: AssignmentFilter = .all
    @State private var selectedRecurrence: RecurrenceFilter = .all

    var body: some View {
        List {
            filterSection

            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    "No upcoming events",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Try adjusting filters or add new events.")
                )
            } else {
                let analysis = conflictAnalysis
                ForEach(Array(filteredEvents.enumerated()), id: \.offset) { _, grouped in
                    let event = grouped.primary
                    let hasConflict = analysis.hasConflict(event)
                    let hasWarning = !hasConflict && analysis.hasWarning(event)
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            EventCard(
                                event: event,
                                showsConflictBadge: hasConflict,
                                showsWarningBadge: hasWarning,
                                combinedCount: grouped.isCrossChildFamilyMoment ? 1 : grouped.combinedCount,
                                childNamesDisplayLine: grouped.isCrossChildFamilyMoment ? grouped.childNamesDisplayLine() : nil,
                                childAccentColor: grouped.isCrossChildFamilyMoment ? Color.accentColor : childColor(for: event),
                                onGetDirections: event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? nil
                                    : { openDirections(for: event.location) }
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
            }
        }
        .navigationTitle("Upcoming")
    }

    private var filterSection: some View {
        Section("Filters") {
            Picker("Child", selection: $selectedChild) {
                ForEach(availableChildren, id: \.self) { child in
                    Text(child).tag(child)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AssignmentFilter.allCases) { filter in
                        Button {
                            selectedAssignment = filter
                        } label: {
                            Image(systemName: filter.iconName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selectedAssignment == filter ? .white : .primary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(selectedAssignment == filter ? Color.accentColor : Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(filter.label)
                    }
                }
                .padding(.vertical, 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CategoryFilter.allCases) { filter in
                        Button {
                            selectedCategory = filter
                        } label: {
                            Image(systemName: filter.iconName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selectedCategory == filter ? .white : .primary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(selectedCategory == filter ? Color.accentColor : Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(filter.label)
                    }
                }
                .padding(.vertical, 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RecurrenceFilter.allCases) { filter in
                        Button {
                            selectedRecurrence = filter
                        } label: {
                            Image(systemName: filter.iconName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selectedRecurrence == filter ? .white : .primary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(selectedRecurrence == filter ? Color.accentColor : Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(filter.label)
                    }
                }
                .padding(.vertical, 2)
            }
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

    private func eventKey(_ event: FamilyEvent) -> String {
        ConflictAnalyzer.key(for: event)
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
            return "Warning: tight transition after \(first.title)"
        }
        return "Warning: tight transition after \(first.title) and \(counterparts.count - 1) more"
    }

    private func openDirections(for destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let url = URL(string: "http://maps.apple.com/?daddr=\(encoded)&dirflg=d") else { return }
        openURL(url)
    }
}
