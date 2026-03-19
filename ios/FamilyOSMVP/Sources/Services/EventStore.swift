import Foundation

@MainActor
final class EventStore: ObservableObject {
    @Published private(set) var events: [FamilyEvent] = []

    private let fileURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documents.appendingPathComponent("family_os_events.json")
        let hasExistingFile = FileManager.default.fileExists(atPath: fileURL.path)
        load()
        if !hasExistingFile && events.isEmpty {
            seedSampleData()
        }
    }

    func addEvent(_ event: FamilyEvent) {
        var newEvent = event
        newEvent.updatedAt = Date()
        events.append(newEvent)
        normalizeAndSave()
    }

    func addEvents(_ newEvents: [FamilyEvent]) {
        let now = Date()
        let stamped = newEvents.map { event -> FamilyEvent in
            var mutable = event
            mutable.updatedAt = now
            return mutable
        }
        events.append(contentsOf: stamped)
        normalizeAndSave()
    }

    func updateEvent(_ event: FamilyEvent) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        var updated = event
        updated.updatedAt = Date()
        events[index] = updated
        normalizeAndSave()
    }

    func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
        normalizeAndSave()
    }

    func replaceAll(_ replacement: [FamilyEvent]) {
        events = replacement
        normalizeAndSave()
    }

    func clearAll() {
        events = []
        save()
    }

    func upcomingEvents() -> [FamilyEvent] {
        let now = Date()
        return events.filter { $0.endDateTime >= now }.sorted { $0.startDateTime < $1.startDateTime }
    }

    func thisWeekEvents() -> [FamilyEvent] {
        let calendar = Calendar.current
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: Date()) else { return [] }
        return events
            .filter { $0.startDateTime >= Date() && $0.startDateTime <= weekEnd }
            .sorted { $0.startDateTime < $1.startDateTime }
    }

    private func normalizeAndSave() {
        events = dedupeEvents(events).sorted { $0.startDateTime < $1.startDateTime }
        save()
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

    private func seedSampleData() {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let schoolNight = Calendar.current.date(byAdding: .day, value: 2, to: now) ?? now

        let sample: [FamilyEvent] = [
            FamilyEvent(
                title: "Soccer Practice",
                childName: "Mia",
                category: .sports,
                date: tomorrow,
                startTime: DateParsing.shortTimeFormatter.date(from: "17:30") ?? now,
                endTime: DateParsing.shortTimeFormatter.date(from: "18:30") ?? now,
                location: "Lincoln Field",
                notes: "Bring shin guards",
                sourceType: .manual,
                isApproved: true,
                updatedAt: now
            ),
            FamilyEvent(
                title: "Science Fair Night",
                childName: "Noah",
                category: .school,
                date: schoolNight,
                startTime: DateParsing.shortTimeFormatter.date(from: "18:00") ?? now,
                endTime: DateParsing.shortTimeFormatter.date(from: "19:30") ?? now,
                location: "Roosevelt Elementary",
                notes: "Poster board due",
                sourceType: .aiExtracted,
                isApproved: true,
                updatedAt: now
            ),
        ]

        events = dedupeEvents(sample).sorted { $0.startDateTime < $1.startDateTime }
        save()
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
}
