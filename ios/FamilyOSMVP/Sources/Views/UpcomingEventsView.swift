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

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All Events"
            case .recurringOnly: return "Recurring Only"
            case .oneTimeOnly: return "One-Time Only"
            }
        }

        var iconName: String {
            switch self {
            case .all: return "line.3.horizontal.decrease.circle"
            case .recurringOnly: return "repeat"
            case .oneTimeOnly: return "calendar"
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
                ForEach(Array(filteredEvents.enumerated()), id: \.offset) { _, event in
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        EventCard(
                            event: event,
                            onGetDirections: event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? nil
                                : { openDirections(for: event.location) }
                        )
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
        baseEvents.filter { event in
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
            }
            return matchesChild && matchesCategory && matchesRecurrence
        }
    }

    private var availableChildren: [String] {
        let names = Set(baseEvents.map(\.childName).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return ["All Children"] + names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func openDirections(for destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let url = URL(string: "http://maps.apple.com/?daddr=\(encoded)&dirflg=d") else { return }
        openURL(url)
    }
}
