import SwiftUI

struct ReviewExtractedEventsView: View {
    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @State var candidates: [ExtractedEventCandidate]
    @State private var saveMessage: String?

    var body: some View {
        List {
            if candidates.isEmpty {
                ContentUnavailableView(
                    "No extracted events",
                    systemImage: "text.magnifyingglass",
                    description: Text("Try a clearer schedule image or add events manually.")
                )
            } else {
                ForEach($candidates) { $candidate in
                    Section {
                        Toggle("Accept", isOn: $candidate.isAccepted)
                        TextField("Title", text: $candidate.title)
                        TextField("Child Name", text: $candidate.childName)
                        TextField("Category (school/sports/medical/social/other)", text: $candidate.category)

                        Toggle("Set Date", isOn: hasDateBinding($candidate))
                        if candidate.date != nil {
                            DatePicker(
                                "Date",
                                selection: selectedDateBinding($candidate),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                        }

                        Toggle("Set Start Time", isOn: hasStartTimeBinding($candidate))
                        if candidate.startTime != nil {
                            DatePicker(
                                "Start Time",
                                selection: selectedStartTimeBinding($candidate),
                                displayedComponents: .hourAndMinute
                            )
                            .environment(\.locale, Locale(identifier: "en_US"))
                        }

                        Toggle("Set End Time", isOn: hasEndTimeBinding($candidate))
                        if candidate.endTime != nil {
                            DatePicker(
                                "End Time",
                                selection: selectedEndTimeBinding($candidate),
                                displayedComponents: .hourAndMinute
                            )
                            .environment(\.locale, Locale(identifier: "en_US"))
                        }

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

    private func hasDateBinding(_ candidate: Binding<ExtractedEventCandidate>) -> Binding<Bool> {
        Binding(
            get: { candidate.wrappedValue.date != nil },
            set: { enabled in
                candidate.wrappedValue.date = enabled ? (candidate.wrappedValue.date ?? DateParsing.isoDateFormatter.string(from: Date())) : nil
            }
        )
    }

    private func hasStartTimeBinding(_ candidate: Binding<ExtractedEventCandidate>) -> Binding<Bool> {
        Binding(
            get: { candidate.wrappedValue.startTime != nil },
            set: { enabled in
                candidate.wrappedValue.startTime = enabled ? (candidate.wrappedValue.startTime ?? DateParsing.meridiemTimeFormatter.string(from: Date())) : nil
            }
        )
    }

    private func hasEndTimeBinding(_ candidate: Binding<ExtractedEventCandidate>) -> Binding<Bool> {
        Binding(
            get: { candidate.wrappedValue.endTime != nil },
            set: { enabled in
                let defaultEnd = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
                candidate.wrappedValue.endTime = enabled ? (candidate.wrappedValue.endTime ?? DateParsing.meridiemTimeFormatter.string(from: defaultEnd)) : nil
            }
        )
    }

    private func selectedDateBinding(_ candidate: Binding<ExtractedEventCandidate>) -> Binding<Date> {
        Binding(
            get: {
                DateParsing.parseDate(candidate.wrappedValue.date) ?? Date()
            },
            set: { newDate in
                candidate.wrappedValue.date = DateParsing.isoDateFormatter.string(from: newDate)
            }
        )
    }

    private func selectedStartTimeBinding(_ candidate: Binding<ExtractedEventCandidate>) -> Binding<Date> {
        Binding(
            get: {
                DateParsing.parseTime(candidate.wrappedValue.startTime) ?? Date()
            },
            set: { newTime in
                candidate.wrappedValue.startTime = DateParsing.meridiemTimeFormatter.string(from: newTime)
            }
        )
    }

    private func selectedEndTimeBinding(_ candidate: Binding<ExtractedEventCandidate>) -> Binding<Date> {
        Binding(
            get: {
                DateParsing.parseTime(candidate.wrappedValue.endTime) ??
                    Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ??
                    Date()
            },
            set: { newTime in
                candidate.wrappedValue.endTime = DateParsing.meridiemTimeFormatter.string(from: newTime)
            }
        )
    }
}
