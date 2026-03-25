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

    /// Order for pickers: Mom, Dad, Either, then None.
    static let assignmentPickerOrder: [EventAssignment] = [.mom, .dad, .either, .unassigned]

    /// Short label for chips and pickers.
    var displayName: String {
        switch self {
        case .unassigned: return "Unassigned"
        case .mom: return "Mom"
        case .dad: return "Dad"
        case .either: return "Either"
        }
    }

    /// Compact label for detail rows and menus (uses "None" instead of "Unassigned").
    var rowLabel: String {
        switch self {
        case .unassigned: return "None"
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
    /// For `.weekly` only: which **calendar** days repeat — all seven (Sun–Sat), not Mon–Fri only. Uses `Calendar` weekday `1...7` (Sunday = 1). Empty means legacy weekly (same weekday as `date`, 7-day step).
    var recurrenceDaysOfWeek: [Int] = []
    /// Last calendar day included in the series (start of day). Applies when non-`nil` for any repeating rule.
    var recurrenceEndDate: Date? = nil
    var assignment: EventAssignment = .unassigned
    var updatedAt: Date = Date()

    var startDateTime: Date {
        DateParsing.combine(date: date, time: startTime)
    }

    var endDateTime: Date {
        DateParsing.combine(date: date, time: endTime)
    }

    /// User-facing summary for detail screens and accessibility.
    var recurrenceSummaryText: String {
        var parts: [String] = []
        switch recurrenceRule {
        case .none:
            return EventRecurrenceRule.none.displayName
        case .weekly:
            if recurrenceDaysOfWeek.isEmpty {
                parts.append(EventRecurrenceRule.weekly.displayName)
            } else {
                let labels = recurrenceDaysOfWeek.sorted().map { Self.shortDayOfWeekLabel(for: $0) }
                parts.append("Weekly · \(labels.joined(separator: ", "))")
            }
        case .daily, .monthly:
            parts.append(recurrenceRule.displayName)
        }
        if let end = recurrenceEndDate {
            parts.append("ends \(Self.formatRecurrenceEndDate(end))")
        }
        return parts.joined(separator: " · ")
    }

    /// Short label for list chips (may omit end date to save space).
    var recurrenceChipLabel: String {
        guard recurrenceRule != .none else { return "" }
        if recurrenceRule == .weekly, !recurrenceDaysOfWeek.isEmpty {
            return recurrenceDaysOfWeek.sorted().map { Self.shortDayOfWeekLabel(for: $0) }.joined(separator: ", ")
        }
        return recurrenceRule.displayName
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
        case recurrenceDaysOfWeek = "recurrenceWeekdays"
        case recurrenceEndDate
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
        recurrenceDaysOfWeek: [Int] = [],
        recurrenceEndDate: Date? = nil,
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
        self.recurrenceDaysOfWeek = Self.normalizedDaysOfWeek(recurrenceDaysOfWeek)
        self.recurrenceEndDate = recurrenceEndDate
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
        recurrenceDaysOfWeek = Self.normalizedDaysOfWeek(try container.decodeIfPresent([Int].self, forKey: .recurrenceDaysOfWeek) ?? [])
        recurrenceEndDate = try container.decodeIfPresent(Date.self, forKey: .recurrenceEndDate)
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
        try container.encode(recurrenceDaysOfWeek, forKey: .recurrenceDaysOfWeek)
        try container.encodeIfPresent(recurrenceEndDate, forKey: .recurrenceEndDate)
        try container.encode(assignment, forKey: .assignment)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func normalizedDaysOfWeek(_ raw: [Int]) -> [Int] {
        let valid = raw.filter { (1...7).contains($0) }
        return Array(Set(valid)).sorted()
    }

    /// Gregorian weekday `1...7` (Sun = 1 … Sat = 7), ordered from `calendar.firstWeekday` for a full week of UI chips.
    static func calendarWeekdaysInDisplayOrder(calendar: Calendar = .current) -> [Int] {
        let cal = calendar
        return (0..<7).map { offset in
            ((cal.firstWeekday - 1 + offset) % 7) + 1
        }
    }

    /// Short label for a `Calendar` weekday value (`1` = Sunday … `7` = Saturday); respects locale week start.
    static func shortDayOfWeekLabel(for calendarWeekday: Int, calendar: Calendar = .current) -> String {
        let cal = calendar
        let symbols = cal.shortWeekdaySymbols
        let idx = (max(1, min(7, calendarWeekday)) - cal.firstWeekday + 7) % 7
        guard idx < symbols.count else { return "\(calendarWeekday)" }
        return symbols[idx]
    }

    /// Full weekday name for accessibility (same ordering as `shortDayOfWeekLabel`).
    static func fullDayOfWeekLabel(for calendarWeekday: Int, calendar: Calendar = .current) -> String {
        let cal = calendar
        let symbols = cal.weekdaySymbols
        let idx = (max(1, min(7, calendarWeekday)) - cal.firstWeekday + 7) % 7
        guard idx < symbols.count else { return "Day \(calendarWeekday)" }
        return symbols[idx]
    }

    private static func formatRecurrenceEndDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
