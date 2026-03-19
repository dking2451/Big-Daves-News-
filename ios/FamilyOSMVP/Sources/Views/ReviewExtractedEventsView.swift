import SwiftUI

struct ReviewExtractedEventsView: View {
    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @State var candidates: [ExtractedEventCandidate]
    @State private var saveMessage: String?

    var body: some View {
        List {
            ForEach($candidates) { $candidate in
                Section {
                    Toggle("Accept", isOn: $candidate.isAccepted)
                    TextField("Title", text: $candidate.title)
                    TextField("Child Name", text: $candidate.childName)
                    TextField("Category (school/sports/medical/social/other)", text: $candidate.category)
                    TextField("Date (YYYY-MM-DD)", text: Binding($candidate.date, replacingNilWith: ""))
                    TextField("Start (HH:mm)", text: Binding($candidate.startTime, replacingNilWith: ""))
                    TextField("End (HH:mm)", text: Binding($candidate.endTime, replacingNilWith: ""))
                    TextField("Location", text: $candidate.location)
                    TextField("Notes", text: $candidate.notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    HStack {
                        Text(candidate.title.isEmpty ? "Untitled" : candidate.title)
                        Spacer()
                        Text("Conf: \(Int(candidate.confidence * 100))%")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if candidate.ambiguityFlag {
                        Text("Ambiguous date/time. Please verify before saving.")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button("Save Accepted Events") {
                    saveAcceptedEvents()
                }
            }

            if let saveMessage {
                Section {
                    Text(saveMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Review Extracted")
    }

    private func saveAcceptedEvents() {
        let accepted = candidates.filter(\.isAccepted)
        var skippedCount = 0

        let mapped: [FamilyEvent] = accepted.compactMap { candidate in
            guard
                let parsedDate = DateParsing.parseDate(candidate.date),
                let parsedStart = DateParsing.parseTime(candidate.startTime),
                let parsedEnd = DateParsing.parseTime(candidate.endTime)
            else {
                skippedCount += 1
                return nil
            }

            return FamilyEvent(
                title: candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Event" : candidate.title,
                childName: candidate.childName.trimmingCharacters(in: .whitespacesAndNewlines),
                category: EventCategory(rawValue: candidate.category.lowercased()) ?? .other,
                date: parsedDate,
                startTime: parsedStart,
                endTime: parsedEnd,
                location: candidate.location.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: candidate.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceType: .aiExtracted,
                isApproved: true,
                updatedAt: Date()
            )
        }

        store.addEvents(mapped)
        if skippedCount > 0 {
            saveMessage = "Saved \(mapped.count). Skipped \(skippedCount) with ambiguous or missing date/time."
        } else {
            saveMessage = "Saved \(mapped.count) event\(mapped.count == 1 ? "" : "s")."
        }
        if !mapped.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                dismiss()
            }
        }
    }
}

private extension Binding where Value == String? {
    init(_ source: Binding<String?>, replacingNilWith fallback: String) {
        self.init(
            get: { source.wrappedValue ?? fallback },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
