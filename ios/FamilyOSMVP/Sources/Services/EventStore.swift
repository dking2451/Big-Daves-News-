import Foundation

@MainActor
final class EventStore: ObservableObject {
    struct ChildDefaults: Codable, Equatable {
        var defaultCategory: EventCategory?
        var defaultRecurrence: EventRecurrenceRule?
        var favoriteLocations: [String]

        init(
            defaultCategory: EventCategory? = nil,
            defaultRecurrence: EventRecurrenceRule? = nil,
            favoriteLocations: [String] = []
        ) {
            self.defaultCategory = defaultCategory
            self.defaultRecurrence = defaultRecurrence
            self.favoriteLocations = favoriteLocations
        }
    }

    struct ManualEntrySuggestion: Identifiable {
        let title: String
        let childName: String
        let category: EventCategory
        let weekday: Int
        let startTime: String
        let endTime: String
        let location: String
        let frequency: Int

        var id: String {
            "\(title.lowercased())|\(childName.lowercased())|\(category.rawValue)|\(weekday)|\(startTime)|\(endTime)|\(location.lowercased())"
        }
    }

    @Published private(set) var events: [FamilyEvent] = []
    @Published private(set) var managedChildNames: [String] = []
    @Published private(set) var childColorTokensByNameKey: [String: String] = [:]
    @Published private(set) var childDefaultsByNameKey: [String: ChildDefaults] = [:]

    private let fileURL: URL
    private let childNamesURL: URL
    private let childColorsURL: URL
    private let childDefaultsURL: URL
    private let notificationService = LocalNotificationService()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documents.appendingPathComponent("family_os_events.json")
        childNamesURL = documents.appendingPathComponent("family_os_children.json")
        childColorsURL = documents.appendingPathComponent("family_os_child_colors.json")
        childDefaultsURL = documents.appendingPathComponent("family_os_child_defaults.json")
        load()
        loadChildNames()
        loadChildColors()
        loadChildDefaults()
        if managedChildNames.isEmpty {
            bootstrapChildNamesFromEvents()
        }
        ensureChildColorsForKnownNames()
        ensureChildDefaultsForKnownNames()
        syncEventNotifications()
    }

    func addEvent(_ event: FamilyEvent) {
        var newEvent = event
        newEvent.updatedAt = Date()
        events.append(newEvent)
        learnChildName(newEvent.childName)
        normalizeAndSave()
        syncEventNotifications()
    }

    func addEvents(_ newEvents: [FamilyEvent]) {
        let now = Date()
        let stamped = newEvents.map { event -> FamilyEvent in
            var mutable = event
            mutable.updatedAt = now
            return mutable
        }
        events.append(contentsOf: stamped)
        stamped.forEach { learnChildName($0.childName) }
        normalizeAndSave()
        syncEventNotifications()
    }

    func updateEvent(_ event: FamilyEvent) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        var updated = event
        updated.updatedAt = Date()
        events[index] = updated
        learnChildName(updated.childName)
        normalizeAndSave()
        syncEventNotifications()
    }

    func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
        normalizeAndSave()
        syncEventNotifications()
    }

    func replaceAll(_ replacement: [FamilyEvent]) {
        events = replacement
        bootstrapChildNamesFromEvents()
        normalizeAndSave()
        syncEventNotifications()
    }

    func clearAll() {
        events = []
        managedChildNames = []
        childColorTokensByNameKey = [:]
        childDefaultsByNameKey = [:]
        save()
        saveChildNames()
        saveChildColors()
        saveChildDefaults()
        syncEventNotifications()
    }

    func loadDemoEvents() {
        let calendar = Calendar.current
        let now = Date()

        func makeTime(_ value: String) -> Date {
            DateParsing.meridiemTimeFormatter.date(from: value)
                ?? DateParsing.shortTimeFormatter.date(from: value)
                ?? now
        }

        func dayOffset(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: now) ?? now
        }

        let demoEvents: [FamilyEvent] = [
            FamilyEvent(
                title: "Soccer Practice",
                childName: "Tim",
                category: .sports,
                date: dayOffset(0),
                startTime: makeTime("5:30 PM"),
                endTime: makeTime("6:30 PM"),
                location: "Lincoln Field",
                notes: "Bring water and shin guards.",
                sourceType: .manual,
                isApproved: true,
                recurrenceRule: .weekly
            ),
            FamilyEvent(
                title: "Piano Lesson",
                childName: "Ava",
                category: .other,
                date: dayOffset(1),
                startTime: makeTime("4:00 PM"),
                endTime: makeTime("4:45 PM"),
                location: "Downtown Music Studio",
                notes: "Practice scales before class.",
                sourceType: .manual,
                isApproved: true,
                recurrenceRule: .weekly
            ),
            FamilyEvent(
                title: "Math Tutoring",
                childName: "Tim",
                category: .school,
                date: dayOffset(1),
                startTime: makeTime("4:00 PM"),
                endTime: makeTime("5:00 PM"),
                location: "Library Study Room 2",
                notes: "Bring worksheet packet.",
                sourceType: .manual,
                isApproved: true,
                recurrenceRule: .none
            ),
            FamilyEvent(
                title: "Pediatric Checkup",
                childName: "Ava",
                category: .medical,
                date: dayOffset(2),
                startTime: makeTime("2:00 PM"),
                endTime: makeTime("2:30 PM"),
                location: "Kids Health Clinic",
                notes: "Insurance card and shot records.",
                sourceType: .manual,
                isApproved: true,
                recurrenceRule: .none
            ),
            FamilyEvent(
                title: "School Drop-off",
                childName: "Tim",
                category: .school,
                date: dayOffset(0),
                startTime: makeTime("8:00 AM"),
                endTime: makeTime("8:20 AM"),
                location: "Roosevelt Elementary",
                notes: "",
                sourceType: .manual,
                isApproved: true,
                recurrenceRule: .daily
            ),
            FamilyEvent(
                title: "School Drop-off",
                childName: "Ava",
                category: .school,
                date: dayOffset(0),
                startTime: makeTime("8:00 AM"),
                endTime: makeTime("8:20 AM"),
                location: "Roosevelt Elementary",
                notes: "",
                sourceType: .manual,
                isApproved: true,
                recurrenceRule: .daily
            ),
            FamilyEvent(
                title: "Family Dinner",
                childName: "",
                category: .social,
                date: dayOffset(3),
                startTime: makeTime("6:30 PM"),
                endTime: makeTime("8:00 PM"),
                location: "Home",
                notes: "Grandparents visiting.",
                sourceType: .manual,
                isApproved: true,
                recurrenceRule: .weekly
            ),
            FamilyEvent(
                title: "Birthday Party",
                childName: "Ava",
                category: .social,
                date: dayOffset(4),
                startTime: makeTime("1:00 PM"),
                endTime: makeTime("3:00 PM"),
                location: "City Park Pavilion",
                notes: "Bring gift and snack.",
                sourceType: .aiExtracted,
                isApproved: true,
                recurrenceRule: .none
            ),
            FamilyEvent(
                title: "Orthodontist Follow-up",
                childName: "Tim",
                category: .medical,
                date: dayOffset(10),
                startTime: makeTime("3:15 PM"),
                endTime: makeTime("3:45 PM"),
                location: "Smile Orthodontics",
                notes: "",
                sourceType: .manual,
                isApproved: true,
                recurrenceRule: .monthly
            ),
        ]

        addEvents(demoEvents)
    }

    func upcomingEvents() -> [FamilyEvent] {
        let now = Date()
        guard let rangeEnd = Calendar.current.date(byAdding: .day, value: 30, to: now) else {
            return []
        }
        return events
            .flatMap { expandedOccurrences(for: $0, from: now, to: rangeEnd) }
            .filter { $0.endDateTime >= now }
            .sorted { $0.startDateTime < $1.startDateTime }
    }

    func eventsInNextDays(_ days: Int) -> [FamilyEvent] {
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: now) else {
            return []
        }
        return upcomingEvents()
            .filter { $0.startDateTime <= end }
            .sorted { $0.startDateTime < $1.startDateTime }
    }

    func thisWeekEvents() -> [FamilyEvent] {
        let calendar = Calendar.current
        let now = Date()
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) else { return [] }
        return events
            .flatMap { expandedOccurrences(for: $0, from: now, to: weekEnd) }
            .filter { $0.startDateTime >= now && $0.startDateTime <= weekEnd }
            .sorted { $0.startDateTime < $1.startDateTime }
    }

    func locationSuggestions(for category: EventCategory, limit: Int = 6) -> [String] {
        let learned = learnedLocations(for: category, limit: limit)
        let defaults = defaultLocations[category, default: []]
        let merged = learned + defaults

        var seen = Set<String>()
        var result: [String] = []
        for item in merged {
            let normalized = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty { continue }
            if seen.insert(normalized.lowercased()).inserted {
                result.append(normalized)
            }
            if result.count >= limit { break }
        }
        return result
    }

    func childNameSuggestions(prefix: String = "", limit: Int = 6) -> [String] {
        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = managedChildNames.filter {
            normalizedPrefix.isEmpty ? true : $0.lowercased().contains(normalizedPrefix)
        }
        return Array(filtered.prefix(limit))
    }

    func childNameList() -> [String] {
        managedChildNames
    }

    func manualEntrySuggestions(
        childName: String,
        title: String,
        category: EventCategory,
        limit: Int = 3
    ) -> [ManualEntrySuggestion] {
        let normalizedChild = childName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        typealias Key = String
        var counts: [Key: Int] = [:]
        var representatives: [Key: ManualEntrySuggestion] = [:]

        for event in events where event.category == category {
            let eventChild = event.childName.trimmingCharacters(in: .whitespacesAndNewlines)
            let eventTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let eventLocation = event.location.trimmingCharacters(in: .whitespacesAndNewlines)

            if !normalizedChild.isEmpty && eventChild.lowercased() != normalizedChild { continue }
            if !normalizedTitle.isEmpty && eventTitle.lowercased() != normalizedTitle { continue }

            let weekday = Calendar.current.component(.weekday, from: event.date)
            let startText = DateParsing.meridiemTimeFormatter.string(from: event.startTime)
            let endText = DateParsing.meridiemTimeFormatter.string(from: event.endTime)

            let key = [
                eventTitle.lowercased(),
                eventChild.lowercased(),
                category.rawValue,
                "\(weekday)",
                startText,
                endText,
                eventLocation.lowercased(),
            ].joined(separator: "|")

            counts[key, default: 0] += 1
            if representatives[key] == nil {
                representatives[key] = ManualEntrySuggestion(
                    title: eventTitle,
                    childName: eventChild,
                    category: category,
                    weekday: weekday,
                    startTime: startText,
                    endTime: endText,
                    location: eventLocation,
                    frequency: 1
                )
            }
        }

        let ranked = counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .compactMap { key, count -> ManualEntrySuggestion? in
                guard count >= 2, var rep = representatives[key] else { return nil }
                rep = ManualEntrySuggestion(
                    title: rep.title,
                    childName: rep.childName,
                    category: rep.category,
                    weekday: rep.weekday,
                    startTime: rep.startTime,
                    endTime: rep.endTime,
                    location: rep.location,
                    frequency: count
                )
                return rep
            }

        return Array(ranked.prefix(limit))
    }

    func addChildName(_ rawName: String) {
        learnChildName(rawName)
    }

    func childColorToken(for childName: String) -> String? {
        let key = childNameKey(childName)
        guard !key.isEmpty else { return nil }
        return childColorTokensByNameKey[key]
    }

    func setChildColorToken(_ token: String, for childName: String) {
        let key = childNameKey(childName)
        guard !key.isEmpty else { return }
        childColorTokensByNameKey[key] = token
        saveChildColors()
    }

    func childDefaults(for childName: String) -> ChildDefaults {
        let key = childNameKey(childName)
        guard !key.isEmpty else { return ChildDefaults() }
        return childDefaultsByNameKey[key] ?? ChildDefaults()
    }

    func setChildDefaultCategory(_ category: EventCategory?, for childName: String) {
        let key = childNameKey(childName)
        guard !key.isEmpty else { return }
        var defaults = childDefaultsByNameKey[key] ?? ChildDefaults()
        defaults.defaultCategory = category
        childDefaultsByNameKey[key] = normalizedDefaults(defaults)
        saveChildDefaults()
    }

    func setChildDefaultRecurrence(_ recurrence: EventRecurrenceRule?, for childName: String) {
        let key = childNameKey(childName)
        guard !key.isEmpty else { return }
        var defaults = childDefaultsByNameKey[key] ?? ChildDefaults()
        defaults.defaultRecurrence = recurrence
        childDefaultsByNameKey[key] = normalizedDefaults(defaults)
        saveChildDefaults()
    }

    func addChildFavoriteLocation(_ rawLocation: String, for childName: String) {
        let key = childNameKey(childName)
        let location = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !location.isEmpty else { return }
        var defaults = childDefaultsByNameKey[key] ?? ChildDefaults()
        if defaults.favoriteLocations.contains(where: { $0.caseInsensitiveCompare(location) == .orderedSame }) {
            return
        }
        defaults.favoriteLocations.append(location)
        childDefaultsByNameKey[key] = normalizedDefaults(defaults)
        saveChildDefaults()
    }

    func removeChildFavoriteLocation(_ rawLocation: String, for childName: String) {
        let key = childNameKey(childName)
        let location = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !location.isEmpty else { return }
        var defaults = childDefaultsByNameKey[key] ?? ChildDefaults()
        defaults.favoriteLocations.removeAll { $0.caseInsensitiveCompare(location) == .orderedSame }
        childDefaultsByNameKey[key] = normalizedDefaults(defaults)
        saveChildDefaults()
    }

    func renameChildName(from oldName: String, to newName: String) {
        let oldTrimmed = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldTrimmed.isEmpty, !newTrimmed.isEmpty else { return }

        managedChildNames = managedChildNames.map { existing in
            existing.caseInsensitiveCompare(oldTrimmed) == .orderedSame ? newTrimmed : existing
        }
        managedChildNames = normalizedUniqueNames(managedChildNames)
        let oldKey = childNameKey(oldTrimmed)
        let newKey = childNameKey(newTrimmed)
        if let token = childColorTokensByNameKey[oldKey], !newKey.isEmpty {
            childColorTokensByNameKey[newKey] = token
        }
        childColorTokensByNameKey.removeValue(forKey: oldKey)
        if childColorTokensByNameKey[newKey] == nil {
            childColorTokensByNameKey[newKey] = defaultColorToken(for: newKey)
        }
        if let defaults = childDefaultsByNameKey[oldKey], !newKey.isEmpty {
            childDefaultsByNameKey[newKey] = defaults
        }
        childDefaultsByNameKey.removeValue(forKey: oldKey)
        if childDefaultsByNameKey[newKey] == nil {
            childDefaultsByNameKey[newKey] = ChildDefaults()
        }

        var changed = false
        for index in events.indices {
            if events[index].childName.caseInsensitiveCompare(oldTrimmed) == .orderedSame {
                events[index].childName = newTrimmed
                events[index].updatedAt = Date()
                changed = true
            }
        }

        saveChildNames()
        saveChildColors()
        saveChildDefaults()
        if changed {
            normalizeAndSave()
        }
    }

    func removeChildName(_ rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        managedChildNames.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        childColorTokensByNameKey.removeValue(forKey: childNameKey(trimmed))
        childDefaultsByNameKey.removeValue(forKey: childNameKey(trimmed))

        var changed = false
        for index in events.indices {
            if events[index].childName.caseInsensitiveCompare(trimmed) == .orderedSame {
                events[index].childName = ""
                events[index].updatedAt = Date()
                changed = true
            }
        }

        saveChildNames()
        saveChildColors()
        saveChildDefaults()
        if changed {
            normalizeAndSave()
        }
    }

    func likelyDuplicate(for candidate: FamilyEvent, excludingID: UUID? = nil) -> FamilyEvent? {
        events.first { existing in
            if let excludingID, existing.id == excludingID {
                return false
            }
            return isLikelyDuplicate(existing, candidate)
        }
    }

    /// Broader match used during import review to update an existing event when key details changed
    /// (for example corrected date/time/location) but title/category still point to the same event.
    func likelyUpdateTarget(for candidate: FamilyEvent, excludingID: UUID? = nil) -> FamilyEvent? {
        let ranked = events.compactMap { existing -> (FamilyEvent, Double)? in
            if let excludingID, existing.id == excludingID { return nil }
            if isLikelyDuplicate(existing, candidate) { return (existing, 1.0) }

            let score = updateSimilarityScore(existing: existing, candidate: candidate)
            return score >= 0.60 ? (existing, score) : nil
        }
        return ranked.max(by: { $0.1 < $1.1 })?.0
    }

    private func normalizeAndSave() {
        events = dedupeEvents(events).sorted { $0.startDateTime < $1.startDateTime }
        save()
    }

    private func syncEventNotifications() {
        let upcoming = upcomingEvents()
        Task {
            await notificationService.syncNotifications(for: upcoming)
        }
    }

    private func isLikelyDuplicate(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        lhsTitle(lhs) == lhsTitle(rhs) &&
            sameMinute(lhs.startDateTime, rhs.startDateTime) &&
            sameMinute(lhs.endDateTime, rhs.endDateTime) &&
            normalizedLocation(lhs.location) == normalizedLocation(rhs.location)
    }

    private func lhsTitle(_ event: FamilyEvent) -> String {
        event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedLocation(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sameMinute(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 60
    }

    private func updateSimilarityScore(existing: FamilyEvent, candidate: FamilyEvent) -> Double {
        guard existing.category == candidate.category else { return 0 }
        let title = titleSimilarity(existing.title, candidate.title)
        guard title >= 0.60 else { return 0 }

        let childScore = childMatchScore(existing: existing.childName, candidate: candidate.childName)
        if childScore == 0 { return 0 }

        let dateScore = dateProximityScore(existing.date, candidate.date)
        let startScore = timeProximityScore(existing.startDateTime, candidate.startDateTime)
        let locationScore = locationSimilarity(existing.location, candidate.location)

        return (title * 0.42) + (childScore * 0.20) + (dateScore * 0.18) + (startScore * 0.12) + (locationScore * 0.08)
    }

    private func childMatchScore(existing: String, candidate: String) -> Double {
        let lhs = existing.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhs = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lhs.isEmpty || rhs.isEmpty { return 0.65 } // family-wide/unknown child can still be same event
        return lhs == rhs ? 1.0 : 0.0
    }

    private func dateProximityScore(_ lhs: Date, _ rhs: Date) -> Double {
        let calendar = Calendar.current
        let lDay = calendar.startOfDay(for: lhs)
        let rDay = calendar.startOfDay(for: rhs)
        let diff = abs(calendar.dateComponents([.day], from: lDay, to: rDay).day ?? 999)
        switch diff {
        case 0: return 1.0
        case 1...2: return 0.9
        case 3...7: return 0.7
        case 8...21: return 0.45
        default: return 0.0
        }
    }

    private func timeProximityScore(_ lhs: Date, _ rhs: Date) -> Double {
        let minutes = abs(lhs.timeIntervalSince(rhs)) / 60
        switch minutes {
        case ..<30: return 1.0
        case ..<90: return 0.8
        case ..<180: return 0.55
        case ..<360: return 0.3
        default: return 0.0
        }
    }

    private func locationSimilarity(_ lhsRaw: String, _ rhsRaw: String) -> Double {
        let lhs = lhsRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhs = rhsRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lhs.isEmpty || rhs.isEmpty { return 0.5 }
        if lhs == rhs { return 1.0 }
        let lhsTokens = Set(lhs.split { !$0.isLetter && !$0.isNumber }.map { String($0) })
        let rhsTokens = Set(rhs.split { !$0.isLetter && !$0.isNumber }.map { String($0) })
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0.0 }
        let overlap = Double(lhsTokens.intersection(rhsTokens).count) / Double(lhsTokens.union(rhsTokens).count)
        return overlap
    }

    private func titleSimilarity(_ lhsRaw: String, _ rhsRaw: String) -> Double {
        let lhs = lhsRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhs = rhsRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lhs.isEmpty || rhs.isEmpty { return 0 }
        if lhs == rhs { return 1.0 }
        if lhs.contains(rhs) || rhs.contains(lhs) { return 0.85 }

        let lhsTokens = Set(lhs.split { !$0.isLetter && !$0.isNumber }.map { String($0) }.filter { $0.count >= 2 })
        let rhsTokens = Set(rhs.split { !$0.isLetter && !$0.isNumber }.map { String($0) }.filter { $0.count >= 2 })
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0.0 }
        return Double(lhsTokens.intersection(rhsTokens).count) / Double(lhsTokens.union(rhsTokens).count)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([FamilyEvent].self, from: data)
            events = dedupeEvents(decoded)
        } catch {
            recoverCorruptedFile()
            events = []
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        let tempURL = fileURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            let manager = FileManager.default
            if manager.fileExists(atPath: fileURL.path) {
                _ = try manager.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try manager.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func loadChildNames() {
        guard let data = try? Data(contentsOf: childNamesURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        managedChildNames = normalizedUniqueNames(decoded)
    }

    private func saveChildNames() {
        guard let data = try? JSONEncoder().encode(managedChildNames) else { return }
        try? data.write(to: childNamesURL, options: .atomic)
    }

    private func loadChildColors() {
        guard let data = try? Data(contentsOf: childColorsURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        childColorTokensByNameKey = decoded
    }

    private func saveChildColors() {
        guard let data = try? JSONEncoder().encode(childColorTokensByNameKey) else { return }
        try? data.write(to: childColorsURL, options: .atomic)
    }

    private func loadChildDefaults() {
        guard let data = try? Data(contentsOf: childDefaultsURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: ChildDefaults].self, from: data) else { return }
        childDefaultsByNameKey = decoded.mapValues { normalizedDefaults($0) }
    }

    private func saveChildDefaults() {
        guard let data = try? JSONEncoder().encode(childDefaultsByNameKey) else { return }
        try? data.write(to: childDefaultsURL, options: .atomic)
    }

    private func dedupeEvents(_ input: [FamilyEvent]) -> [FamilyEvent] {
        var byID: [UUID: FamilyEvent] = [:]
        for event in input {
            if let existing = byID[event.id] {
                byID[event.id] = event.updatedAt >= existing.updatedAt ? event : existing
            } else {
                byID[event.id] = event
            }
        }
        return Array(byID.values)
    }

    private func recoverCorruptedFile() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt.\(stamp).json")
        try? manager.moveItem(at: fileURL, to: backupURL)
    }

    private func bootstrapChildNamesFromEvents() {
        let namesFromEvents = events.map(\.childName)
        managedChildNames = normalizedUniqueNames(namesFromEvents)
        saveChildNames()
        ensureChildColorsForKnownNames()
        ensureChildDefaultsForKnownNames()
    }

    private func learnedLocations(for category: EventCategory, limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for event in events where event.category == category {
            let key = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty { continue }
            counts[key, default: 0] += 1
        }
        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .prefix(limit)
            .map(\.key)
    }

    private var defaultLocations: [EventCategory: [String]] {
        [
            .school: ["School Campus", "Main School Office", "Elementary Gym"],
            .sports: ["Lincoln Field", "Community Sports Complex", "YMCA Gym"],
            .medical: ["Pediatric Clinic", "Family Dental Center", "Urgent Care"],
            .social: ["Friend's House", "Community Center", "City Park"],
            .other: ["Home", "Downtown", "Local Library"],
        ]
    }

    private func learnChildName(_ rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if managedChildNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            ensureColorToken(for: trimmed)
            ensureDefaults(for: trimmed)
            return
        }
        managedChildNames.append(trimmed)
        managedChildNames = normalizedUniqueNames(managedChildNames)
        saveChildNames()
        ensureColorToken(for: trimmed)
        ensureDefaults(for: trimmed)
    }

    private func normalizedUniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func childNameKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func ensureChildColorsForKnownNames() {
        var changed = false
        for name in managedChildNames {
            let key = childNameKey(name)
            guard !key.isEmpty else { continue }
            if childColorTokensByNameKey[key] == nil {
                childColorTokensByNameKey[key] = defaultColorToken(for: key)
                changed = true
            }
        }
        if changed {
            saveChildColors()
        }
    }

    private func ensureColorToken(for childName: String) {
        let key = childNameKey(childName)
        guard !key.isEmpty else { return }
        if childColorTokensByNameKey[key] == nil {
            childColorTokensByNameKey[key] = defaultColorToken(for: key)
            saveChildColors()
        }
    }

    private func ensureChildDefaultsForKnownNames() {
        var changed = false
        for name in managedChildNames {
            let key = childNameKey(name)
            guard !key.isEmpty else { continue }
            if childDefaultsByNameKey[key] == nil {
                childDefaultsByNameKey[key] = ChildDefaults()
                changed = true
            }
        }
        if changed {
            saveChildDefaults()
        }
    }

    private func ensureDefaults(for childName: String) {
        let key = childNameKey(childName)
        guard !key.isEmpty else { return }
        if childDefaultsByNameKey[key] == nil {
            childDefaultsByNameKey[key] = ChildDefaults()
            saveChildDefaults()
        }
    }

    private func defaultColorToken(for key: String) -> String {
        let tokens = ["blue", "green", "orange", "purple", "pink", "teal", "indigo", "red"]
        var hash = 0
        for byte in key.utf8 {
            hash = (hash * 31 + Int(byte)) % 65_537
        }
        return tokens[abs(hash) % tokens.count]
    }

    private func normalizedDefaults(_ defaults: ChildDefaults) -> ChildDefaults {
        var seen = Set<String>()
        let favorites = defaults.favoriteLocations.compactMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
        return ChildDefaults(
            defaultCategory: defaults.defaultCategory,
            defaultRecurrence: defaults.defaultRecurrence,
            favoriteLocations: favorites
        )
    }

    private func expandedOccurrences(for event: FamilyEvent, from start: Date, to end: Date) -> [FamilyEvent] {
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEndRaw = calendar.startOfDay(for: end)

        switch event.recurrenceRule {
        case .none:
            return event.endDateTime >= start ? [event] : []
        case .daily, .weekly, .monthly:
            var rangeEnd = rangeEndRaw
            if let seriesEnd = event.recurrenceEndDate {
                rangeEnd = min(rangeEnd, calendar.startOfDay(for: seriesEnd))
            }
            guard rangeStart <= rangeEnd else { return [] }

            if event.recurrenceRule == .daily {
                return generateSeries(event: event, from: rangeStart, to: rangeEnd, step: .day, value: 1, cap: 60)
            }
            if event.recurrenceRule == .monthly {
                return generateSeries(event: event, from: rangeStart, to: rangeEnd, step: .month, value: 1, cap: 24)
            }
            // weekly
            if event.recurrenceDaysOfWeek.isEmpty {
                return generateSeries(event: event, from: rangeStart, to: rangeEnd, step: .day, value: 7, cap: 24)
            }
            return expandedWeeklyByWeekdays(event: event, rangeStart: rangeStart, rangeEnd: rangeEnd)
        }
    }

    /// Weekly with explicit calendar days (any combination of Sun–Sat). Occurrences are every matching day from the event anchor through `rangeEnd`.
    private func expandedWeeklyByWeekdays(event: FamilyEvent, rangeStart: Date, rangeEnd: Date) -> [FamilyEvent] {
        let calendar = Calendar.current
        let weekdaySet = Set(event.recurrenceDaysOfWeek.filter { (1...7).contains($0) })
        guard !weekdaySet.isEmpty else {
            return generateSeries(event: event, from: rangeStart, to: rangeEnd, step: .day, value: 7, cap: 24)
        }

        let seriesStart = calendar.startOfDay(for: event.date)
        let windowStart = max(rangeStart, seriesStart)
        var day = windowStart
        var generated: [FamilyEvent] = []
        let cap = 200

        while day <= rangeEnd, generated.count < cap {
            let wd = calendar.component(.weekday, from: day)
            if weekdaySet.contains(wd) {
                var adjusted = event
                adjusted.date = day
                generated.append(adjusted)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return generated
    }

    private func generateSeries(
        event: FamilyEvent,
        from rangeStart: Date,
        to rangeEnd: Date,
        step: Calendar.Component,
        value: Int,
        cap: Int
    ) -> [FamilyEvent] {
        guard let firstDate = nextOccurrenceDate(for: event, onOrAfter: rangeStart) else { return [] }
        let calendar = Calendar.current
        var occurrenceDate = firstDate
        var generated: [FamilyEvent] = []
        var count = 0

        while occurrenceDate <= rangeEnd, count < cap {
            var adjusted = event
            adjusted.date = occurrenceDate
            generated.append(adjusted)
            occurrenceDate = calendar.date(byAdding: step, value: value, to: occurrenceDate) ?? occurrenceDate
            count += 1
            if count > 0 && generated.last?.date == occurrenceDate { break }
        }
        return generated
    }

    private func nextOccurrenceDate(for event: FamilyEvent, onOrAfter reference: Date) -> Date? {
        let calendar = Calendar.current
        let baseDay = calendar.startOfDay(for: event.date)
        let refDay = calendar.startOfDay(for: reference)
        if baseDay >= refDay { return baseDay }

        switch event.recurrenceRule {
        case .none:
            return baseDay
        case .daily:
            let dayDiff = calendar.dateComponents([.day], from: baseDay, to: refDay).day ?? 0
            return calendar.date(byAdding: .day, value: dayDiff, to: baseDay)
        case .weekly:
            let dayDiff = calendar.dateComponents([.day], from: baseDay, to: refDay).day ?? 0
            let weekJump = (dayDiff / 7) * 7
            var candidate = calendar.date(byAdding: .day, value: weekJump, to: baseDay) ?? baseDay
            if candidate < refDay {
                candidate = calendar.date(byAdding: .day, value: 7, to: candidate) ?? candidate
            }
            return candidate
        case .monthly:
            var candidate = baseDay
            var guardCount = 0
            while candidate < refDay && guardCount < 240 {
                candidate = calendar.date(byAdding: .month, value: 1, to: candidate) ?? candidate
                guardCount += 1
            }
            return candidate
        }
    }
}
