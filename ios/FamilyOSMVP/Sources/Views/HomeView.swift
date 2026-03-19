import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: EventStore
    @State private var showingManualAdd = false

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

                Text("Upcoming")
                    .font(.title3.weight(.semibold))

                if store.upcomingEvents().isEmpty {
                    ContentUnavailableView("No upcoming events", systemImage: "calendar")
                } else {
                    ForEach(store.upcomingEvents()) { event in
                        NavigationLink {
                            EventDetailView(event: event)
                        } label: {
                            EventCard(event: event)
                        }
                        .buttonStyle(.plain)
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

    private var summaryCard: some View {
        let weekEvents = store.thisWeekEvents()
        return VStack(alignment: .leading, spacing: 8) {
            Text("This Week")
                .font(.headline)
            Text("\(weekEvents.count) upcoming event\(weekEvents.count == 1 ? "" : "s")")
                .font(.title2.weight(.bold))
            Text("Stay calm and keep the family schedule in one place.")
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
