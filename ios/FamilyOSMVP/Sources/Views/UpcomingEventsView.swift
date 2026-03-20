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
                let conflictDetails = conflictDetailsByKey
                let conflicts = Set(conflictDetails.keys)
                ForEach(Array(filteredEvents.enumerated()), id: \.offset) { _, event in
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            EventCard(
                                event: event,
                                showsConflictBadge: conflicts.contains(eventKey(event)),
                                childAccentColor: childColor(for: event),
                                onGetDirections: event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? nil
                                    : { openDirections(for: event.location) }
                            )
                            if let summary = conflictSummary(for: event, from: conflictDetails) {
                                Label(summary, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
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

    private var filteredEvents: [FamilyEvent] {
        let conflicts = Set(conflictDetailsByKey.keys)
        return baseEvents.filter { event in
            let matchesChild = selectedChild == "All Children" || event.childName == selectedChild
            let matchesCategory = selectedCategory.eventCategory == nil || event.category == selectedCategory.eventCategory
            let matchesRecurrence: Bool
            switch selectedRecurrence {
            case .all:
                matchesRecurrence = true
            case .recurringOnly:
                matchesRecurrence = event.recurrenceRule != .none
            case .oneTimeOnly:
                matchesRecurrence = event.recurrenceRule == .none
            case .conflictsOnly:
                matchesRecurrence = conflicts.contains(eventKey(event))
            }
            return matchesChild && matchesCategory && matchesRecurrence
        }
    }

    private var availableChildren: [String] {
        let names = Set(baseEvents.map(\.childName).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return ["All Children"] + names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var conflictDetailsByKey: [String: [FamilyEvent]] {
        let groupedByChild = Dictionary(grouping: baseEvents) { event in
            event.childName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        var conflicts: [String: [FamilyEvent]] = [:]
        for (child, childEvents) in groupedByChild where !child.isEmpty {
            let sorted = childEvents.sorted { $0.startDateTime < $1.startDateTime }
            for i in sorted.indices {
                var j = i + 1
                while j < sorted.count {
                    let left = sorted[i]
                    let right = sorted[j]
                    if right.startDateTime >= left.endDateTime {
                        break
                    }
                    if left.startDateTime < right.endDateTime {
                        let leftKey = eventKey(left)
                        let rightKey = eventKey(right)
                        appendConflict(right, to: leftKey, in: &conflicts)
                        appendConflict(left, to: rightKey, in: &conflicts)
                    }
                    j += 1
                }
            }
        }
        return conflicts
    }

    private func eventKey(_ event: FamilyEvent) -> String {
        "\(event.id.uuidString)-\(Int(event.startDateTime.timeIntervalSince1970))"
    }

    private func childColor(for event: FamilyEvent) -> Color {
        let child = event.childName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !child.isEmpty else { return .primary }
        let token = store.childColorToken(for: child)
        return ChildColorPalette.color(for: token)
    }

    private func appendConflict(_ counterpart: FamilyEvent, to key: String, in map: inout [String: [FamilyEvent]]) {
        var items = map[key, default: []]
        if !items.contains(where: { eventKey($0) == eventKey(counterpart) }) {
            items.append(counterpart)
        }
        map[key] = items
    }

    private func conflictSummary(for event: FamilyEvent, from map: [String: [FamilyEvent]]) -> String? {
        let counterparts = map[eventKey(event), default: []]
        guard let first = counterparts.first else { return nil }
        let firstTime = first.startDateTime.formatted(date: .omitted, time: .shortened)
        if counterparts.count == 1 {
            return "Conflicts with \(first.title) at \(firstTime)"
        }
        return "Conflicts with \(first.title) and \(counterparts.count - 1) more"
    }

    private func openDirections(for destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let url = URL(string: "http://maps.apple.com/?daddr=\(encoded)&dirflg=d") else { return }
        openURL(url)
    }
}
