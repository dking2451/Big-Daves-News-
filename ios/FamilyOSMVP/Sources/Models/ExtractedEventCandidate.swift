import Foundation

struct ExtractedEventCandidate: Identifiable, Codable {
    var id: UUID
    var title: String
    var childName: String
    var category: String
    var date: String?
    var startTime: String?
    var endTime: String?
    var location: String
    var notes: String
    var confidence: Double
    var ambiguityFlag: Bool
    /// Backend + heuristics: flyer did not name a specific child; show assign-child UI in review.
    var childNeedsAssignment: Bool
    var isAccepted: Bool

    /// Keys the **backend** sends (`/v1/extract-events`). No `id` / `isAccepted` — those are client-only.
    enum CodingKeys: String, CodingKey {
        case title, childName, category, date, startTime, endTime, location, notes, confidence, ambiguityFlag
        case childNeedsAssignment
    }

    init(
        id: UUID = UUID(),
        title: String,
        childName: String,
        category: String,
        date: String?,
        startTime: String?,
        endTime: String?,
        location: String,
        notes: String,
        confidence: Double,
        ambiguityFlag: Bool,
        childNeedsAssignment: Bool = false,
        isAccepted: Bool = true
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
        self.confidence = confidence
        self.ambiguityFlag = ambiguityFlag
        self.childNeedsAssignment = childNeedsAssignment
        self.isAccepted = isAccepted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        title = try c.decode(String.self, forKey: .title)
        childName = try c.decodeIfPresent(String.self, forKey: .childName) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "other"
        date = try c.decodeIfPresent(String.self, forKey: .date)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        ambiguityFlag = try c.decodeIfPresent(Bool.self, forKey: .ambiguityFlag) ?? false
        childNeedsAssignment = try c.decodeIfPresent(Bool.self, forKey: .childNeedsAssignment) ?? false
        isAccepted = true
    }

    /// Display confidence: uses the server value when present; otherwise mirrors `backend/family-os-mvp-api/app/extractor.py`
    /// `_heuristic_confidence` so the UI is not stuck at 0% when the API omits `confidence` or returns a placeholder 0.
    var effectiveConfidence: Double {
        var c = confidence
        if c > 1, c <= 100 { c /= 100 }
        c = min(1, max(0, c))
        if c > 0.001 { return c }
        return Self.heuristicConfidenceFallback(for: self)
    }

    private static func heuristicConfidenceFallback(for e: ExtractedEventCandidate) -> Double {
        let titleClean = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var score = 0.22
        if !titleClean.isEmpty, titleClean != "Untitled Event" { score += 0.14 }
        if DateParsing.parseDate(e.date) != nil { score += 0.28 }
        if DateParsing.parseTime(e.startTime) != nil { score += 0.22 }
        if DateParsing.parseTime(e.endTime) != nil { score += 0.08 }
        let ambiguity = e.ambiguityFlag || (DateParsing.parseTime(e.startTime) == nil)
        if ambiguity { score -= 0.18 }
        return max(0.12, min(0.92, score))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(childName, forKey: .childName)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encodeIfPresent(startTime, forKey: .startTime)
        try c.encodeIfPresent(endTime, forKey: .endTime)
        try c.encode(location, forKey: .location)
        try c.encode(notes, forKey: .notes)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(ambiguityFlag, forKey: .ambiguityFlag)
        try c.encode(childNeedsAssignment, forKey: .childNeedsAssignment)
    }
}

struct ExtractEventsResponse: Codable {
    var candidates: [ExtractedEventCandidate]
}
