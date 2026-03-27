import EventKit
import SwiftUI

struct EventDetailView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss

    let event: FamilyEvent
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var integrationMessage: String?
    @State private var isRunningIntegration = false

    var body: some View {
        List {
            Section("Title") {
                HStack {
                    Text(currentEvent.title)
                    Spacer()
                    HStack(spacing: 6) {
                        if currentEvent.recurrenceRule != .none {
                            detailIconBadge(
                                systemName: "repeat",
                                fill: .indigo,
                                accessibilityLabel: currentEvent.recurrenceSummaryText
                            )
                        }
                        detailIconBadge(
                            systemName: categoryIconName,
                            fill: categoryBadgeColor,
                            accessibilityLabel: currentEvent.category.displayName
                        )
                    }
                }
            }
            Section("Details") {
                LabeledContent("Child", value: currentEvent.childName.isEmpty ? "Family" : currentEvent.childName)
                LabeledContent("Date", value: currentEvent.startDateTime.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Start", value: currentEvent.startDateTime.formatted(date: .omitted, time: .shortened))
                LabeledContent("End", value: currentEvent.endDateTime.formatted(date: .omitted, time: .shortened))
                LabeledContent("Repeats", value: currentEvent.recurrenceSummaryText)
                Picker("Assigned To", selection: assignmentBinding) {
                    ForEach(EventAssignment.assignmentPickerOrder, id: \.self) { choice in
                        Text(choice.rowLabel).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityHint("Changes who is responsible for this event")
                LabeledContent("Location", value: currentEvent.location.isEmpty ? "-" : currentEvent.location)
                LabeledContent("Source", value: currentEvent.sourceType == .manual ? "Manual" : "AI Extracted")
            }

            if !currentEvent.notes.isEmpty {
                Section("Notes") {
                    Text(currentEvent.notes)
                }
            }

            if !currentEvent.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Location") {
                    Button {
                        if let url = currentEvent.mapsDirectionsURL() {
                            openURL(url)
                        }
                    } label: {
                        Label("Get Directions", systemImage: "location.north.line")
                    }
                    .accessibilityLabel("Get directions to \(currentEvent.location)")
                }
            }

            Section("Apple Integrations") {
                Button {
                    Task { await addToCalendar() }
                } label: {
                    if isRunningIntegration {
                        ProgressView()
                    } else {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }
                }
                .disabled(isRunningIntegration)

                Button {
                    Task { await addReminder() }
                } label: {
                    if isRunningIntegration {
                        ProgressView()
                    } else {
                        Label("Create Reminder", systemImage: "checklist")
                    }
                }
                .disabled(isRunningIntegration)
            }

            Section {
                Button {
                    showingEdit = true
                } label: {
                    Label("Edit event details", systemImage: "square.and.pencil")
                }
                .accessibilityHint("Change child, title, times, location, recurrence, and assignment.")
                Button("Delete Event", role: .destructive) {
                    showingDeleteConfirm = true
                }
            }
        }
        .navigationTitle("Event Detail")
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                ManualAddEventView(existingEvent: currentEvent)
            }
        }
        .alert("Delete this event?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.deleteEvent(id: event.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Integration Status", isPresented: Binding(
            get: { integrationMessage != nil },
            set: { if !$0 { integrationMessage = nil } }
        )) {
            Button("OK", role: .cancel) { integrationMessage = nil }
        } message: {
            Text(integrationMessage ?? "")
        }
    }

    /// Prefer the store copy so inline edits (e.g. assignment) reflect immediately for all event types.
    private var currentEvent: FamilyEvent {
        store.events.first(where: { $0.id == event.id }) ?? event
    }

    private var assignmentBinding: Binding<EventAssignment> {
        Binding(
            get: { currentEvent.assignment },
            set: { newValue in
                var updated = currentEvent
                updated.assignment = newValue
                store.updateEvent(updated)
            }
        )
    }

    private func addToCalendar() async {
        isRunningIntegration = true
        defer { isRunningIntegration = false }
        do {
            let message = try await AppleIntegrationService.addEventToCalendar(currentEvent)
            integrationMessage = message
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    private func addReminder() async {
        isRunningIntegration = true
        defer { isRunningIntegration = false }
        do {
            let message = try await AppleIntegrationService.addReminder(for: currentEvent)
            integrationMessage = message
        } catch {
            integrationMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func detailIconBadge(systemName: String, fill: Color, accessibilityLabel: String) -> some View {
        Image(systemName: systemName)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(fill))
            .accessibilityLabel(accessibilityLabel)
    }

    private var categoryIconName: String {
        switch currentEvent.category {
        case .school:
            return "graduationcap.fill"
        case .sports:
            return "figure.run"
        case .medical:
            return "cross.case.fill"
        case .social:
            return "person.2.fill"
        case .other:
            return "sparkles"
        }
    }

    private var categoryBadgeColor: Color {
        switch currentEvent.category {
        case .school:
            return .blue
        case .sports:
            return .green
        case .medical:
            return .red
        case .social:
            return .purple
        case .other:
            return .gray
        }
    }
}

enum AppleIntegrationError: LocalizedError {
    case calendarUnavailable
    case remindersUnavailable
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .calendarUnavailable:
            return "Calendar is unavailable on this device."
        case .remindersUnavailable:
            return "Reminders are unavailable on this device."
        case .permissionDenied(let product):
            return "\(product) permission was denied. Enable access in Settings."
        }
    }
}

enum AppleIntegrationService {
    static func addEventToCalendar(_ event: FamilyEvent) async throws -> String {
        let store = EKEventStore()
        try await requestCalendarPermission(store)

        guard let calendar = store.defaultCalendarForNewEvents else {
            throw AppleIntegrationError.calendarUnavailable
        }

        let newEvent = EKEvent(eventStore: store)
        newEvent.calendar = calendar
        newEvent.title = event.title
        newEvent.location = event.location
        newEvent.notes = event.notes
        newEvent.startDate = event.startDateTime
        let endDate = event.endDateTime > event.startDateTime
            ? event.endDateTime
            : Calendar.current.date(byAdding: .hour, value: 1, to: event.startDateTime) ?? event.startDateTime
        newEvent.endDate = endDate

        try store.save(newEvent, span: .thisEvent)
        return "Added to Calendar."
    }

    static func addReminder(for event: FamilyEvent) async throws -> String {
        let store = EKEventStore()
        try await requestReminderPermission(store)

        guard let remindersCalendar = store.defaultCalendarForNewReminders() else {
            throw AppleIntegrationError.remindersUnavailable
        }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = remindersCalendar
        reminder.title = "Prep: \(event.title)"
        let noteParts = [event.childName.isEmpty ? nil : "Child: \(event.childName)", event.location.isEmpty ? nil : "Location: \(event.location)", event.notes.isEmpty ? nil : event.notes]
        reminder.notes = noteParts.compactMap { $0 }.joined(separator: "\n")

        let dueDate = event.startDateTime
        let dueComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        reminder.dueDateComponents = dueComponents

        if let oneHourBefore = Calendar.current.date(byAdding: .hour, value: -1, to: dueDate) {
            reminder.addAlarm(EKAlarm(absoluteDate: oneHourBefore))
        }

        try store.save(reminder, commit: true)
        return "Reminder created."
    }

    private static func requestCalendarPermission(_ store: EKEventStore) async throws {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .event) { allowed, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: allowed)
                    }
                }
            }
        }
        if !granted {
            throw AppleIntegrationError.permissionDenied("Calendar")
        }
    }

    private static func requestReminderPermission(_ store: EKEventStore) async throws {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .reminder) { allowed, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: allowed)
                    }
                }
            }
        }
        if !granted {
            throw AppleIntegrationError.permissionDenied("Reminders")
        }
    }
}
