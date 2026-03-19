import Foundation

struct ExtractedEventCandidate: Identifiable, Codable {
    var id: UUID = UUID()
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
    var isAccepted: Bool = true
}

struct ExtractEventsResponse: Codable {
    var candidates: [ExtractedEventCandidate]
}
