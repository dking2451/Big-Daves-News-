import SwiftUI

struct ReviewExtractedEventsView: View {
    enum DuplicateHandlingMode: String, CaseIterable, Identifiable {
        case keepBoth
        case updateExisting

        var id: String { rawValue }

        var label: String {
            switch self {
            case .keepBoth: return "Keep Both"
            case .updateExisting: return "Update Existing"
            }
        }
    }

    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @State var candidates: [ExtractedEventCandidate]
    @State private var saveMessage: String?
    @State private var duplicateHandlingMode: DuplicateHandlingMode = .updateExisting
    @State private var expandedNotesCandidateIDs: Set<UUID> = []
    @State private var expandedDateTimeCandidateIDs: Set<UUID> = []
    @State private var rowHandlingOverrideByCandidateID: [UUID: DuplicateHandlingMode] = [:]
    @State private var locationPickerCandidateID: UUID?

    let onSaveCompleted: (() -> Void)?

    init(
        candidates: [ExtractedEventCandidate],
        onSaveCompleted: (() -> Void)? = nil
    ) {
        self.onSaveCompleted = onSaveCompleted
        _candidates = State(initialValue: candidates)
    }

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
                            "\(acceptedIncompleteCount) accepted event\(acceptedIncompleteCount == 1 ? "" : "s") need a date and start time.",
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

                if acceptedNeedChildAssignmentCount > 0 {
                    Section {
                        Label(
                            "\(acceptedNeedChildAssignmentCount) event\(acceptedNeedChildAssignmentCount == 1 ? "" : "s") need a child (or Family-wide). Team or event titles are not a child’s name.",
                            systemImage: "person.crop.circle.badge.questionmark"
                        )
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                    }
                }

                if duplicateHandlingMode == .updateExisting, acceptedPotentialUpdateCount > 0 {
                    Section {
                        Label(
                            "\(acceptedPotentialUpdateCount) accepted event\(acceptedPotentialUpdateCount == 1 ? "" : "s") match existing events. You can choose update vs new per event.",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                    }
                }

                ForEach($candidates) { $candidate in
                    Section {
                        if let matchedEvent = potentialUpdateMatch(for: candidate) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Update existing event", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.blue)
                                Text("We matched this to a calendar event you already have—updating keeps one entry instead of a duplicate.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(matchedEvent.title) · \(matchedEvent.startDateTime.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                Toggle(
                                    "Update this existing event",
                                    isOn: rowUpdateToggleBinding(candidateID: candidate.id)
                                )
                                .tint(.blue)
                                .accessibilityHint("When on, saving replaces the matched event with these details.")
                            }
                            .padding(.vertical, 4)
                        }

                        Toggle("Accept", isOn: $candidate.isAccepted)
                        TextField("Title", text: $candidate.title)
                        childAssignmentSection(candidate: $candidate)
                        TextField("Category (school/sports/medical/social/other)", text: $candidate.category)

                        Text(dateTimeSummary(for: candidate))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        DisclosureGroup("Edit date & time", isExpanded: dateTimeExpansionBinding(for: candidate)) {
                            Toggle("Set Date", isOn: hasDateBinding($candidate))
                            if candidate.date != nil {
                                DatePicker(
                                    "Date",
                                    selection: selectedDateBinding($candidate),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.wheel)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                            }

                            Toggle("Set Start Time", isOn: hasStartTimeBinding($candidate))
                            if candidate.startTime != nil {
                                DatePicker(
                                    "Start Time",
                                    selection: selectedStartTimeBinding($candidate),
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.wheel)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                                .environment(\.locale, Locale(identifier: "en_US"))
                            }

                            Toggle("Set End Time", isOn: hasEndTimeBinding($candidate))
                            if candidate.endTime != nil {
                                DatePicker(
                                    "End Time",
                                    selection: selectedEndTimeBinding($candidate),
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.wheel)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                                .environment(\.locale, Locale(identifier: "en_US"))
                            }

                            quickFillButtons(candidate: $candidate)
                        }

                        TextField("Location", text: $candidate.location)

                        let placeSuggestions = suggestedLocations(for: candidate)
                        if !placeSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Suggested for child & category")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(placeSuggestions, id: \.self) { place in
                                            Button(place) {
                                                $candidate.location.wrappedValue = place
                                            }
                                            .buttonStyle(.bordered)
                                            .font(.caption.weight(.semibold))
                                            .accessibilityLabel("Use location \(place)")
                                        }
                                    }
                                }
                            }
                        }

                        Button {
                            locationPickerCandidateID = candidate.id
                        } label: {
                            Label("Search for a place", systemImage: "mappin.and.ellipse")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Search MapKit and pick a place to fill the location field.")

                        DisclosureGroup("Notes", isExpanded: notesExpansionBinding(for: candidate.id)) {
                            TextField("Keep extra flyer details here", text: $candidate.notes, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(.top, 4)
                        }
                    } header: {
                        HStack {
                            Text(candidate.title.isEmpty ? "Untitled" : candidate.title)
                            Spacer()
                            Text("Conf: \(Int((candidate.effectiveConfidence * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        if candidate.isAccepted {
                            let missing = missingRequiredFields(for: candidate)
                            if !missing.isEmpty {
                                Text("Missing required: \(missing.joined(separator: ", ")).")
                                    .foregroundStyle(.orange)
                            }
                            if missing.isEmpty,
                               DateParsing.parseTime(candidate.endTime) == nil
                            {
                                Text("End time will default to 1 hour after start when you save.")
                                    .foregroundStyle(.secondary)
                            }
                            if candidate.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Location is optional, but needed for Get Directions.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if candidate.isAccepted, candidate.childNeedsAssignment {
                            Text("Choose who this is for using the child chips or the field above, or tap Family-wide if it applies to everyone.")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                        if candidate.ambiguityFlag {
                            Text("Ambiguous date/time. Please verify before saving.")
                                .foregroundStyle(.orange)
                        }
                        if potentialUpdateMatch(for: candidate) != nil, effectiveHandlingMode(for: candidate.id) == .updateExisting {
                            Text("Saving will update the matched event on your calendar.")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                    }
                    .onAppear {
                        // Keep "Edit date & time" open after required fields are filled; otherwise expansion was only
                        // forced via `missingRequiredFields` and the group collapses as soon as date/time becomes valid.
                        if !missingRequiredFields(for: candidate).isEmpty {
                            expandedDateTimeCandidateIDs.insert(candidate.id)
                        }
                    }
                }

                Section {
                    Picker("Duplicate handling", selection: $duplicateHandlingMode) {
                        ForEach(DuplicateHandlingMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

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
        .sheet(isPresented: Binding(
            get: { locationPickerCandidateID != nil },
            set: { if !$0 { locationPickerCandidateID = nil } }
        )) {
            if let id = locationPickerCandidateID,
               let idx = candidates.firstIndex(where: { $0.id == id }) {
                LocationPickerSheet(
                    selectedAddress: Binding(
                        get: { candidates[idx].location },
                        set: { candidates[idx].location = $0 }
                    )
                )
            }
        }
    }

    private func suggestedLocations(for candidate: ExtractedEventCandidate) -> [String] {
        let cat = EventCategory(rawValue: candidate.category.lowercased()) ?? .other
        return store.locationSuggestions(for: cat, childName: candidate.childName, limit: 8)
    }

    @ViewBuilder
    private func childAssignmentSection(candidate: Binding<ExtractedEventCandidate>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Child (who this is for)", text: childNameBinding(candidate))
                .textContentType(.name)
                .accessibilityHint("Optional. Use a child name, not the team or schedule title.")
            if !store.childNameList().isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("Family-wide") {
                            var c = candidate.wrappedValue
                            c.childName = ""
                            c.childNeedsAssignment = false
                            candidate.wrappedValue = c
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("No specific child, family-wide event")
                        ForEach(store.childNameList(), id: \.self) { name in
                            Button(name) {
                                var c = candidate.wrappedValue
                                c.childName = name
                                c.childNeedsAssignment = false
                                candidate.wrappedValue = c
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func childNameBinding(_ candidate: Binding<ExtractedEventCandidate>) -> Binding<String> {
        Binding(
            get: { candidate.wrappedValue.childName },
            set: { newValue in
                var c = candidate.wrappedValue
                c.childName = newValue
                c.childNeedsAssignment = false
                candidate.wrappedValue = c
            }
        )
    }

    private func notesExpansionBinding(for candidateID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedNotesCandidateIDs.contains(candidateID) },
            set: { expanded in
                if expanded {
                    expandedNotesCandidateIDs.insert(candidateID)
                } else {
                    expandedNotesCandidateIDs.remove(candidateID)
                }
            }
        )
    }



    private func dateTimeExpansionBinding(for candidate: ExtractedEventCandidate) -> Binding<Bool> {
        Binding(
            get: { expandedDateTimeCandidateIDs.contains(candidate.id) || !missingRequiredFields(for: candidate).isEmpty },
            set: { expanded in
                if expanded {
                    expandedDateTimeCandidateIDs.insert(candidate.id)
                } else {
                    expandedDateTimeCandidateIDs.remove(candidate.id)
                }
            }
        )
    }

    private func rowUpdateToggleBinding(candidateID: UUID) -> Binding<Bool> {
        Binding(
            get: { effectiveHandlingMode(for: candidateID) == .updateExisting },
            set: { shouldUpdate in
                rowHandlingOverrideByCandidateID[candidateID] = shouldUpdate ? .updateExisting : .keepBoth
            }
        )
    }

    private func effectiveHandlingMode(for candidateID: UUID) -> DuplicateHandlingMode {
        rowHandlingOverrideByCandidateID[candidateID] ?? duplicateHandlingMode
    }

    private func saveAcceptedEvents() {
        let accepted = candidates.filter(\.isAccepted)
        if accepted.isEmpty {
            saveMessage = "No accepted events to save."
            return
        }

        if accepted.contains(where: { !missingRequiredFields(for: $0).isEmpty }) {
            saveMessage = "Please set a date and start time for each accepted event."
            return
        }

        var skippedCount = 0

        let mapped: [(UUID, FamilyEvent)] = accepted.compactMap { candidate in
            guard
                let parsedDate = DateParsing.parseDate(candidate.date),
                let parsedStart = DateParsing.parseTime(candidate.startTime)
            else {
                skippedCount += 1
                return nil
            }

            let parsedEnd = DateParsing.parseTime(candidate.endTime)
                ?? Calendar.current.date(byAdding: .hour, value: 1, to: parsedStart)
                ?? parsedStart

            let event = FamilyEvent(
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
            return (candidate.id, event)
        }

        var eventsToAdd: [FamilyEvent] = []
        var updatedCount = 0
        var duplicateCount = 0
        var potentialUpdateCount = 0

        for (candidateID, event) in mapped {
            let handlingMode = effectiveHandlingMode(for: candidateID)
            if let duplicate = store.likelyDuplicate(for: event) {
                duplicateCount += 1
                switch handlingMode {
                case .keepBoth:
                    eventsToAdd.append(event)
                case .updateExisting:
                    var replacement = event
                    replacement.id = duplicate.id
                    store.updateEvent(replacement)
                    updatedCount += 1
                }
            } else if let match = store.likelyUpdateTarget(for: event) {
                switch handlingMode {
                case .keepBoth:
                    eventsToAdd.append(event)
                case .updateExisting:
                    var replacement = event
                    replacement.id = match.id
                    store.updateEvent(replacement)
                    updatedCount += 1
                    potentialUpdateCount += 1
                }
            } else {
                eventsToAdd.append(event)
            }
        }

        if !eventsToAdd.isEmpty {
            store.addEvents(eventsToAdd)
        }

        let savedCount = eventsToAdd.count + updatedCount
        if skippedCount > 0 {
            saveMessage = "Saved \(savedCount). Skipped \(skippedCount) with ambiguous or missing date/time."
        } else if duplicateCount > 0 && duplicateHandlingMode == .updateExisting {
            saveMessage = "Saved \(savedCount) events (\(updatedCount) updated existing, including \(potentialUpdateCount) probable matches)."
        } else if duplicateCount > 0 {
            saveMessage = "Saved \(savedCount) events (including \(duplicateCount) duplicates kept)."
        } else if potentialUpdateCount > 0 && duplicateHandlingMode == .updateExisting {
            saveMessage = "Saved \(savedCount) events (\(potentialUpdateCount) updated probable existing matches)."
        } else {
            saveMessage = "Saved \(savedCount) event\(savedCount == 1 ? "" : "s")."
        }
        if savedCount > 0 {
            NotificationCenter.default.post(name: .familyOSNavigateToHome, object: nil)
            onSaveCompleted?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                dismiss()
            }
        }
    }

    private func hasDateBinding(_ candidate: Binding<ExtractedEventCandidate>) -> Binding<Bool> {
        Binding(
            get: { candidate.wrappedValue.date != nil },
            set: { enabled in
                if enabled {
                    expandedDateTimeCandidateIDs.insert(candidate.wrappedValue.id)
                }
                candidate.wrappedValue.date = enabled ? (candidate.wrappedValue.date ?? DateParsing.isoDateFormatter.string(from: Date())) : nil
            }
        )
    }

    private func hasStartTimeBinding(_ candidate: Binding<ExtractedEventCandidate>) -> Binding<Bool> {
        Binding(
            get: { candidate.wrappedValue.startTime != nil },
            set: { enabled in
                if enabled {
                    expandedDateTimeCandidateIDs.insert(candidate.wrappedValue.id)
                }
                candidate.wrappedValue.startTime = enabled ? (candidate.wrappedValue.startTime ?? DateParsing.meridiemTimeFormatter.string(from: Date())) : nil
            }
        )
    }

    private func hasEndTimeBinding(_ candidate: Binding<ExtractedEventCandidate>) -> Binding<Bool> {
        Binding(
            get: { candidate.wrappedValue.endTime != nil },
            set: { enabled in
                if !enabled {
                    candidate.wrappedValue.endTime = nil
                    return
                }
                if candidate.wrappedValue.endTime == nil {
                    let defaultEnd = defaultEndTimeAnchoredToStart(for: candidate.wrappedValue)
                    candidate.wrappedValue.endTime = DateParsing.meridiemTimeFormatter.string(from: defaultEnd)
                }
            }
        )
    }

    /// Default when turning on “Set End Time”: one hour after start time when start is set; otherwise one hour from now.
    private func defaultEndTimeAnchoredToStart(for candidate: ExtractedEventCandidate) -> Date {
        if let start = DateParsing.parseTime(candidate.startTime) {
            return Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
        }
        return Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
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
                if let end = DateParsing.parseTime(candidate.wrappedValue.endTime) {
                    return end
                }
                return defaultEndTimeAnchoredToStart(for: candidate.wrappedValue)
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

    private var acceptedNeedChildAssignmentCount: Int {
        candidates.filter { $0.isAccepted && $0.childNeedsAssignment }.count
    }

    private var acceptedPotentialUpdateCount: Int {
        candidates
            .filter(\.isAccepted)
            .filter { potentialUpdateMatch(for: $0) != nil }
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
        // End time is optional here: if omitted or unparsed, save uses start + 1 hour (see `saveAcceptedEvents`).
        return missing
    }

    private func dateTimeSummary(for candidate: ExtractedEventCandidate) -> String {
        let dateText: String = {
            if let parsed = DateParsing.parseDate(candidate.date) {
                return parsed.formatted(date: .abbreviated, time: .omitted)
            }
            return "Date needed"
        }()
        let startText: String = {
            if let parsed = DateParsing.parseTime(candidate.startTime) {
                return parsed.formatted(date: .omitted, time: .shortened)
            }
            return "Start time needed"
        }()
        let endText: String = {
            if let parsed = DateParsing.parseTime(candidate.endTime) {
                return parsed.formatted(date: .omitted, time: .shortened)
            }
            return "+1h default on save"
        }()
        return "\(dateText) • \(startText) - \(endText)"
    }

    private func potentialUpdateMatch(for candidate: ExtractedEventCandidate) -> FamilyEvent? {
        guard
            let parsedDate = DateParsing.parseDate(candidate.date),
            let parsedStart = DateParsing.parseTime(candidate.startTime)
        else { return nil }

        let parsedEnd = DateParsing.parseTime(candidate.endTime)
            ?? Calendar.current.date(byAdding: .hour, value: 1, to: parsedStart)
            ?? parsedStart

        let event = FamilyEvent(
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

        // Exact duplicate is handled separately; this helper focuses on probable updates.
        if store.likelyDuplicate(for: event) != nil { return nil }
        return store.likelyUpdateTarget(for: event)
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
