import SwiftUI

struct EventDetailView: View {
    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss

    let event: FamilyEvent
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        List {
            Section("Title") {
                Text(currentEvent.title)
            }
            Section("Details") {
                LabeledContent("Child", value: currentEvent.childName.isEmpty ? "Family" : currentEvent.childName)
                LabeledContent("Category", value: currentEvent.category.displayName)
                LabeledContent("Date", value: currentEvent.startDateTime.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Start", value: currentEvent.startDateTime.formatted(date: .omitted, time: .shortened))
                LabeledContent("End", value: currentEvent.endDateTime.formatted(date: .omitted, time: .shortened))
                LabeledContent("Location", value: currentEvent.location.isEmpty ? "-" : currentEvent.location)
                LabeledContent("Source", value: currentEvent.sourceType == .manual ? "Manual" : "AI Extracted")
            }

            if !currentEvent.notes.isEmpty {
                Section("Notes") {
                    Text(currentEvent.notes)
                }
            }

            Section {
                Button("Edit Event") {
                    showingEdit = true
                }
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
    }

    private var currentEvent: FamilyEvent {
        store.events.first(where: { $0.id == event.id }) ?? event
    }
}
