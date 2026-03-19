import SwiftUI

struct ManualAddEventView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EventStore

    let existingEvent: FamilyEvent?

    @State private var title = ""
    @State private var childName = ""
    @State private var category: EventCategory = .school
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var endTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var location = ""
    @State private var notes = ""

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
                DatePicker("Date", selection: $date, displayedComponents: .date)
                DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                TextField("Location", text: $location)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button("Save Event") {
                    save()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(existingEvent == nil ? "Add Event" : "Edit Event")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear(perform: populateIfEditing)
    }

    private func save() {
        if let existingEvent {
            let updated = FamilyEvent(
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
                updatedAt: Date()
            )
            store.updateEvent(updated)
        } else {
            let event = FamilyEvent(
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
                updatedAt: Date()
            )
            store.addEvent(event)
        }
        dismiss()
    }

    private func populateIfEditing() {
        guard let existingEvent else { return }
        title = existingEvent.title
        childName = existingEvent.childName
        category = existingEvent.category
        date = existingEvent.date
        startTime = existingEvent.startTime
        endTime = existingEvent.endTime
        location = existingEvent.location
        notes = existingEvent.notes
    }
}
