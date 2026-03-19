import SwiftUI

struct HomeView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: EventStore
    @State private var showingManualAdd = false
    @State private var expandedOccurrenceKey: String?
    @State private var isLaterExpanded = false
    private let homeHorizonDays = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard

                Button {
                    showingManualAdd = true
                } label: {
                    Label("Add Event", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text("Today")
                    .font(.title3.weight(.semibold))

                if todayEvents.isEmpty {
                    ContentUnavailableView {
                        Label("No events today", systemImage: "calendar")
                    } description: {
                        Text("You're clear for now. Add an event or check Later/Upcoming.")
                    } actions: {
                        Button("Add Event") {
                            showingManualAdd = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(Array(todayEvents.enumerated()), id: \.offset) { _, event in
                        compactEventRow(for: event)
                    }
                }

                DisclosureGroup(isExpanded: $isLaterExpanded) {
                    if laterEvents.isEmpty {
                        Text("Nothing later in the next \(homeHorizonDays) days.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    } else {
                        ForEach(Array(laterEvents.enumerated()), id: \.offset) { _, event in
                            compactEventRow(for: event)
                        }
                    }
                } label: {
                    HStack {
                        Text("Later")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(laterEvents.count)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Family OS MVP")
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

    private var todayEvents: [FamilyEvent] {
        homeEvents.filter { Calendar.current.isDateInToday($0.startDateTime) }
    }

    private var laterEvents: [FamilyEvent] {
        homeEvents.filter { !Calendar.current.isDateInToday($0.startDateTime) }
    }

    private func compactEventRow(for event: FamilyEvent) -> some View {
        let key = occurrenceKey(for: event)
        let isExpanded = expandedOccurrenceKey == key
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedOccurrenceKey = isExpanded ? nil : key
                }
            } label: {
                HStack(spacing: 8) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(event.startDateTime.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(event.title), \(event.startDateTime.formatted(date: .omitted, time: .shortened))")

            if isExpanded {
                HStack(spacing: 6) {
                    if event.recurrenceRule != .none {
                        Image(systemName: "repeat")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                    Image(systemName: categoryIcon(for: event.category))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(categoryColor(for: event.category))
                    Text(event.childName.isEmpty ? "Family" : event.childName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 8) {
                        Label(event.location, systemImage: "mappin.and.ellipse")
                            .font(.footnote)
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
                    Text("View details")
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func occurrenceKey(for event: FamilyEvent) -> String {
        "\(event.id.uuidString)-\(Int(event.startDateTime.timeIntervalSince1970))"
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

    private var summaryCard: some View {
        let weekEvents = homeEvents
        return VStack(alignment: .leading, spacing: 8) {
            Text("Next \(homeHorizonDays) Days")
                .font(.headline)
            Text("\(weekEvents.count) upcoming event\(weekEvents.count == 1 ? "" : "s")")
                .font(.title2.weight(.bold))
            Text("Focused view for critical and timely family events.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.12))
        )
    }
}
