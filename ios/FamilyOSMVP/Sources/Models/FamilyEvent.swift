import Foundation

enum EventCategory: String, Codable, CaseIterable, Identifiable {
    case school
    case sports
    case medical
    case social
    case other

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum EventSourceType: String, Codable {
    case manual
    case aiExtracted = "ai_extracted"
}

/// Local-only: who is responsible for getting the child to the event (no accounts / sync).
enum EventAssignment: String, Codable, CaseIterable, Identifiable {
    case unassigned
    case mom
    case dad
    case either

    var id: String { rawValue }

    /// Short label for chips and pickers.
    var displayName: String {
        switch self {
        case .unassigned: return "Unassigned"
        case .mom: return "Mom"
        case .dad: return "Dad"
        case .either: return "Either"
        }
    }
}

enum EventRecurrenceRule: String, Codable, CaseIterable, Identifiable {
    case none
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Does not repeat"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var iconName: String {
        switch self {
        case .none: return "calendar"
        case .daily, .weekly, .monthly: return "repeat"
        }
    }
}

struct FamilyEvent: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var childName: String
    var category: EventCategory
    var date: Date
    var startTime: Date
    var endTime: Date
    var location: String
    var notes: String
    var sourceType: EventSourceType
    var isApproved: Bool
    var recurrenceRule: EventRecurrenceRule = .none
    var assignment: EventAssignment = .unassigned
    var updatedAt: Date = Date()

    var startDateTime: Date {
        DateParsing.combine(date: date, time: startTime)
    }

    var endDateTime: Date {
        DateParsing.combine(date: date, time: endTime)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case childName
        case category
        case date
        case startTime
        case endTime
        case location
        case notes
        case sourceType
        case isApproved
        case recurrenceRule
        case assignment
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        childName: String,
        category: EventCategory,
        date: Date,
        startTime: Date,
        endTime: Date,
        location: String,
        notes: String,
        sourceType: EventSourceType,
        isApproved: Bool,
        recurrenceRule: EventRecurrenceRule = .none,
        assignment: EventAssignment = .unassigned,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.childName = childName
        self.category = category
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.notes = notes
        self.sourceType = sourceType
        self.isApproved = isApproved
        self.recurrenceRule = recurrenceRule
        self.assignment = assignment
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        childName = try container.decode(String.self, forKey: .childName)
        category = try container.decode(EventCategory.self, forKey: .category)
        date = try container.decode(Date.self, forKey: .date)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        location = try container.decode(String.self, forKey: .location)
        notes = try container.decode(String.self, forKey: .notes)
        sourceType = try container.decode(EventSourceType.self, forKey: .sourceType)
        isApproved = try container.decode(Bool.self, forKey: .isApproved)
        recurrenceRule = try container.decodeIfPresent(EventRecurrenceRule.self, forKey: .recurrenceRule) ?? .none
        assignment = try container.decodeIfPresent(EventAssignment.self, forKey: .assignment) ?? .unassigned
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(childName, forKey: .childName)
        try container.encode(category, forKey: .category)
        try container.encode(date, forKey: .date)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(location, forKey: .location)
        try container.encode(notes, forKey: .notes)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encode(isApproved, forKey: .isApproved)
        try container.encode(recurrenceRule, forKey: .recurrenceRule)
        try container.encode(assignment, forKey: .assignment)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
