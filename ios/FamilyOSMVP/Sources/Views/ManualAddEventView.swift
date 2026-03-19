import MapKit
import SwiftUI

struct ManualAddEventView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EventStore

    let existingEvent: FamilyEvent?

    @State private var title = ""
    @State private var childName = ""
    @State private var category: EventCategory = .school
    @State private var recurrenceRule: EventRecurrenceRule = .none
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var endTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var location = ""
    @State private var notes = ""
    @State private var timeError: String?
    @State private var locationValidationMessage: String?
    @State private var showSaveWithUnverifiedLocationAlert = false
    @State private var showSaveWithoutLocationPrompt = false
    @State private var pendingSaveEvent: FamilyEvent?
    @State private var isValidatingLocation = false
    @State private var showSuggestions = true

    init(existingEvent: FamilyEvent? = nil) {
        self.existingEvent = existingEvent
    }

    var body: some View {
        Form {
            Section("Event") {
                TextField("Title", text: $title)
                TextField("Child Name", text: $childName)
                Picker("Category", selection: $category) {
                    ForEach(EventCategory.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                Picker("Repeats", selection: $recurrenceRule) {
                    ForEach(EventRecurrenceRule.allCases) { rule in
                        Text(rule.displayName).tag(rule)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                TextField("Location", text: $location)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            let patternSuggestions = store.manualEntrySuggestions(
                childName: childName,
                title: title,
                category: category
            )
            if !patternSuggestions.isEmpty {
                Section {
                    Toggle("Show smart recurring suggestions", isOn: $showSuggestions)
                }
                if showSuggestions {
                    Section("Smart Suggestions") {
                        ForEach(patternSuggestions) { suggestion in
                            Button {
                                applySuggestion(suggestion)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestionLabel(suggestion))
                                        .font(.subheadline.weight(.semibold))
                                    Text("Seen \(suggestion.frequency)x • \(weekdayName(suggestion.weekday))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            let childSuggestions = store.childNameSuggestions(prefix: childName)
            if !childSuggestions.isEmpty {
                Section("Quick Child Select") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(childSuggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    childName = suggestion
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            let suggestions = store.locationSuggestions(for: category)
            if !suggestions.isEmpty {
                Section("Suggested Locations") {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            location = suggestion
                        }
                    }
                }
            }

            Section("Location Check") {
                Button {
                    Task { await validateLocationOnly() }
                } label: {
                    if isValidatingLocation {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Validating...")
                        }
                    } else {
                        Text("Validate Location")
                    }
                }
                .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingLocation)

                if let locationValidationMessage {
                    Text(locationValidationMessage)
                        .font(.footnote)
                        .foregroundStyle(locationValidationMessage.hasPrefix("Validated:") ? .green : .orange)
                }
            }

            Section {
                Button("Save Event") {
                    Task { await save() }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let timeError {
                    Text(timeError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(existingEvent == nil ? "Add Event" : "Edit Event")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear(perform: populateIfEditing)
        .alert("Save with unverified location?", isPresented: $showSaveWithUnverifiedLocationAlert) {
            Button("Save Anyway", role: .destructive) {
                if let pendingSaveEvent {
                    persist(pendingSaveEvent)
                    self.pendingSaveEvent = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingSaveEvent = nil
            }
        } message: {
            Text(locationValidationMessage ?? "Location could not be verified.")
        }
        .alert("No location set", isPresented: $showSaveWithoutLocationPrompt) {
            Button("Save Without Location", role: .destructive) {
                if let pendingSaveEvent {
                    persist(pendingSaveEvent)
                    self.pendingSaveEvent = nil
                }
            }
            Button("Add Location", role: .cancel) {
                pendingSaveEvent = nil
            }
        } message: {
            Text("Location is optional, but required for Get Directions later.")
        }
    }

    private func save() async {
        if endTime <= startTime {
            timeError = "End time must be after start time."
            return
        }
        timeError = nil

        let event = buildEvent()
        let trimmedLocation = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else {
            pendingSaveEvent = event
            showSaveWithoutLocationPrompt = true
            return
        }

        isValidatingLocation = true
        let validation = await validateLocation(trimmedLocation)
        isValidatingLocation = false
        locationValidationMessage = validation.message

        if validation.isValid {
            persist(event)
        } else {
            pendingSaveEvent = event
            showSaveWithUnverifiedLocationAlert = true
        }
    }

    private func buildEvent() -> FamilyEvent {
        if let existingEvent {
            return FamilyEvent(
                id: existingEvent.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                childName: childName.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                date: date,
                startTime: startTime,
                endTime: endTime,
                location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceType: existingEvent.sourceType,
                isApproved: true,
                recurrenceRule: recurrenceRule,
                updatedAt: Date()
            )
        } else {
            return FamilyEvent(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                childName: childName.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                date: date,
                startTime: startTime,
                endTime: endTime,
                location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceType: .manual,
                isApproved: true,
                recurrenceRule: recurrenceRule,
                updatedAt: Date()
            )
        }
    }

    private func persist(_ event: FamilyEvent) {
        if existingEvent != nil {
            store.updateEvent(event)
        } else {
            store.addEvent(event)
        }
        dismiss()
    }

    private func populateIfEditing() {
        guard let existingEvent else { return }
        title = existingEvent.title
        childName = existingEvent.childName
        category = existingEvent.category
        recurrenceRule = existingEvent.recurrenceRule
        date = existingEvent.date
        startTime = existingEvent.startTime
        endTime = existingEvent.endTime
        location = existingEvent.location
        notes = existingEvent.notes
    }

    private func validateLocationOnly() async {
        isValidatingLocation = true
        let result = await validateLocation(location)
        isValidatingLocation = false
        locationValidationMessage = result.message
    }

    private func validateLocation(_ rawLocation: String) async -> (isValid: Bool, message: String) {
        let normalized = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return (true, "No location provided.")
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = normalized
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            if let first = response.mapItems.first {
                let resolved = first.name ?? first.placemark.title ?? normalized
                return (true, "Validated: \(resolved)")
            }
            return (false, "Couldn't verify this location. Check spelling or add more detail.")
        } catch {
            return (false, "Location verification unavailable right now. You can still save.")
        }
    }

    private func applySuggestion(_ suggestion: EventStore.ManualEntrySuggestion) {
        title = suggestion.title
        if !suggestion.childName.isEmpty {
            childName = suggestion.childName
        }
        category = suggestion.category
        location = suggestion.location

        if let start = DateParsing.parseTime(suggestion.startTime) {
            startTime = start
        }
        if let end = DateParsing.parseTime(suggestion.endTime) {
            endTime = end
        }
        date = nextDate(forWeekday: suggestion.weekday, from: date)
    }

    private func nextDate(forWeekday weekday: Int, from base: Date) -> Date {
        let calendar = Calendar.current
        var candidate = calendar.startOfDay(for: base)
        let currentWeekday = calendar.component(.weekday, from: candidate)
        let delta = (weekday - currentWeekday + 7) % 7
        candidate = calendar.date(byAdding: .day, value: delta, to: candidate) ?? candidate
        return candidate
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(1, min(7, weekday)) - 1
        return symbols[index]
    }

    private func suggestionLabel(_ suggestion: EventStore.ManualEntrySuggestion) -> String {
        let child = suggestion.childName.isEmpty ? "Family" : suggestion.childName
        let locationText = suggestion.location.isEmpty ? "" : " @ \(suggestion.location)"
        return "\(child): \(suggestion.title) • \(suggestion.startTime)-\(suggestion.endTime)\(locationText)"
    }
}
