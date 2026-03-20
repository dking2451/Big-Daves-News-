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
                if acceptedIncompleteCount > 0 {
                    Section {
                        Label(
                            "\(acceptedIncompleteCount) accepted event\(acceptedIncompleteCount == 1 ? "" : "s") need required date/time fields.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                    }
                }

                if acceptedMissingLocationCount > 0 {
                    Section {
                        Label(
                            "\(acceptedMissingLocationCount) accepted event\(acceptedMissingLocationCount == 1 ? "" : "s") have no location. Add location to enable Maps directions.",
                            systemImage: "mappin.slash"
                        )
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    }
                }

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

                        quickFillButtons(candidate: $candidate)

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
                        if candidate.isAccepted {
                            let missing = missingRequiredFields(for: candidate)
                            if !missing.isEmpty {
                                Text("Missing required: \(missing.joined(separator: ", ")).")
                                    .foregroundStyle(.orange)
                            }
                            if candidate.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Location is optional, but needed for Get Directions.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if candidate.ambiguityFlag {
                            Text("Ambiguous date/time. Please verify before saving.")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Button {
                        saveAcceptedEvents()
                    } label: {
                        Text("Save Accepted Events")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .disabled(acceptedCount == 0 || acceptedIncompleteCount > 0)
                    .buttonStyle(.borderedProminent)
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
        if accepted.isEmpty {
            saveMessage = "No accepted events to save."
            return
        }

        if accepted.contains(where: { !missingRequiredFields(for: $0).isEmpty }) {
            saveMessage = "Please fill required date and time fields for accepted events."
            return
        }

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

    private func quickFillButtons(candidate: Binding<ExtractedEventCandidate>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickFillChip("Set Today", systemImage: "calendar") {
                    candidate.wrappedValue.date = DateParsing.isoDateFormatter.string(from: Date())
                }

                quickFillChip("Start Now", systemImage: "clock") {
                    let now = Date()
                    candidate.wrappedValue.startTime = DateParsing.meridiemTimeFormatter.string(from: now)
                }

                quickFillChip("+1h End", systemImage: "plus.circle") {
                    let base = DateParsing.parseTime(candidate.wrappedValue.startTime) ?? Date()
                    let end = Calendar.current.date(byAdding: .hour, value: 1, to: base) ?? base
                    candidate.wrappedValue.endTime = DateParsing.meridiemTimeFormatter.string(from: end)
                }

                quickFillChip("Use Category Time", systemImage: "tag") {
                    let preset = categoryTimePreset(for: candidate.wrappedValue.category)
                    candidate.wrappedValue.startTime = preset.start
                    candidate.wrappedValue.endTime = preset.end
                    if candidate.wrappedValue.date == nil {
                        candidate.wrappedValue.date = DateParsing.isoDateFormatter.string(from: Date())
                    }
                }
            }
        }
        .font(.footnote)
    }

    private func quickFillChip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var acceptedCount: Int {
        candidates.filter(\.isAccepted).count
    }

    private var acceptedIncompleteCount: Int {
        candidates
            .filter(\.isAccepted)
            .filter { !missingRequiredFields(for: $0).isEmpty }
            .count
    }

    private var acceptedMissingLocationCount: Int {
        candidates
            .filter(\.isAccepted)
            .filter { $0.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    private func missingRequiredFields(for candidate: ExtractedEventCandidate) -> [String] {
        var missing: [String] = []
        if DateParsing.parseDate(candidate.date) == nil {
            missing.append("date")
        }
        if DateParsing.parseTime(candidate.startTime) == nil {
            missing.append("start time")
        }
        if DateParsing.parseTime(candidate.endTime) == nil {
            missing.append("end time")
        }
        return missing
    }

    private func categoryTimePreset(for rawCategory: String) -> (start: String, end: String) {
        switch rawCategory.lowercased() {
        case "school":
            return ("8:00 AM", "9:00 AM")
        case "sports":
            return ("5:30 PM", "6:30 PM")
        case "medical":
            return ("2:00 PM", "2:30 PM")
        case "social":
            return ("6:00 PM", "8:00 PM")
        default:
            return ("9:00 AM", "10:00 AM")
        }
    }
}
