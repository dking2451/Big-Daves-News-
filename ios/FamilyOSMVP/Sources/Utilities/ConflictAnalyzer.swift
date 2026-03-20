import Foundation

struct ConflictAnalysis {
    let conflictsByEventKey: [String: [FamilyEvent]]
    let warningsByEventKey: [String: [FamilyEvent]]

    var conflictedEventCount: Int {
        conflictsByEventKey.count
    }

    var warningEventCount: Int {
        warningsByEventKey.count
    }

    func hasConflict(_ event: FamilyEvent) -> Bool {
        conflictsByEventKey[ConflictAnalyzer.key(for: event)] != nil
    }

    func conflicts(for event: FamilyEvent) -> [FamilyEvent] {
        conflictsByEventKey[ConflictAnalyzer.key(for: event), default: []]
    }

    func hasWarning(_ event: FamilyEvent) -> Bool {
        warningsByEventKey[ConflictAnalyzer.key(for: event)] != nil
    }

    func warnings(for event: FamilyEvent) -> [FamilyEvent] {
        warningsByEventKey[ConflictAnalyzer.key(for: event), default: []]
    }
}

enum ConflictAnalyzer {
    static func analyze(events: [FamilyEvent]) -> ConflictAnalysis {
        let groupedByChild = Dictionary(grouping: events) { event in
            normalized(event.childName)
        }

        var rawConflicts: [String: [FamilyEvent]] = [:]
        var rawWarnings: [String: [FamilyEvent]] = [:]

        for (child, childEvents) in groupedByChild where !child.isEmpty {
            let sorted = childEvents.sorted {
                if $0.startDateTime == $1.startDateTime {
                    return normalized($0.title) < normalized($1.title)
                }
                return $0.startDateTime < $1.startDateTime
            }

            for i in sorted.indices {
                var j = i + 1
                while j < sorted.count {
                    let left = sorted[i]
                    let right = sorted[j]

                    if right.startDateTime >= left.endDateTime {
                        break
                    }

                    if overlapsMeaningfully(left, right) {
                        appendRelation(right, to: key(for: left), in: &rawConflicts)
                        appendRelation(left, to: key(for: right), in: &rawConflicts)
                    } else if hasTightTurnWarning(left, right) {
                        appendRelation(right, to: key(for: left), in: &rawWarnings)
                        appendRelation(left, to: key(for: right), in: &rawWarnings)
                    }
                    j += 1
                }
            }
        }

        let conflictMap = rawConflicts.mapValues { counterparts in
            counterparts.sorted {
                if $0.startDateTime == $1.startDateTime {
                    return normalized($0.title) < normalized($1.title)
                }
                return $0.startDateTime < $1.startDateTime
            }
        }
        let warningMap = rawWarnings.mapValues { counterparts in
            counterparts.sorted {
                if $0.startDateTime == $1.startDateTime {
                    return normalized($0.title) < normalized($1.title)
                }
                return $0.startDateTime < $1.startDateTime
            }
        }

        // If an event has true conflicts, do not also present warning-tier issues for it.
        let conflictKeys = Set(conflictMap.keys)
        let filteredWarningMap = warningMap.filter { key, _ in
            !conflictKeys.contains(key)
        }

        return ConflictAnalysis(
            conflictsByEventKey: conflictMap,
            warningsByEventKey: filteredWarningMap
        )
    }

    static func key(for event: FamilyEvent) -> String {
        "\(event.id.uuidString)-\(Int(event.startDateTime.timeIntervalSince1970))"
    }

    private static func appendRelation(_ counterpart: FamilyEvent, to key: String, in map: inout [String: [FamilyEvent]]) {
        var items = map[key, default: []]
        if !items.contains(where: { self.key(for: $0) == self.key(for: counterpart) }) {
            items.append(counterpart)
        }
        map[key] = items
    }

    static func isLikelySameEvent(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        guard sameChild(lhs, rhs) else { return false }
        guard isSameDay(lhs.startDateTime, rhs.startDateTime) else { return false }
        guard withinMinutes(lhs.startDateTime, rhs.startDateTime, threshold: 15) else { return false }
        guard withinMinutes(lhs.endDateTime, rhs.endDateTime, threshold: 15) else { return false }

        var confidenceSignals = 0
        if similarLocation(lhs.location, rhs.location) {
            confidenceSignals += 1
        }
        if similarTitle(lhs.title, rhs.title) {
            confidenceSignals += 1
        }
        if lhs.category == rhs.category {
            confidenceSignals += 1
        }

        return confidenceSignals >= 2
    }

    static func overlapsMeaningfully(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        guard sameChild(lhs, rhs) else { return false }
        guard isSameDay(lhs.startDateTime, rhs.startDateTime) else { return false }
        guard overlaps(lhs, rhs) else { return false }
        return !isLikelySameEvent(lhs, rhs)
    }

    static func hasTightTurnWarning(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        guard sameChild(lhs, rhs) else { return false }
        guard isSameDay(lhs.startDateTime, rhs.startDateTime) else { return false }
        guard !overlaps(lhs, rhs) else { return false }

        let first: FamilyEvent
        let second: FamilyEvent
        if lhs.startDateTime <= rhs.startDateTime {
            first = lhs
            second = rhs
        } else {
            first = rhs
            second = lhs
        }

        let gapMinutes = second.startDateTime.timeIntervalSince(first.endDateTime) / 60
        guard gapMinutes >= 15, gapMinutes <= 30 else { return false }

        let locationDiffers = !similarLocation(lhs.location, rhs.location)
        let categoryDiffers = lhs.category != rhs.category
        return locationDiffers || categoryDiffers
    }

    private static func overlaps(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        lhs.startDateTime < rhs.endDateTime && rhs.startDateTime < lhs.endDateTime
    }

    private static func similarLocation(_ lhsRaw: String, _ rhsRaw: String) -> Bool {
        let lhsLocation = normalized(lhsRaw)
        let rhsLocation = normalized(rhsRaw)
        if lhsLocation.isEmpty || rhsLocation.isEmpty { return false }
        if lhsLocation == rhsLocation { return true }
        return tokenOverlap(lhsLocation, rhsLocation) >= 0.6
    }

    private static func similarTitle(_ lhsRaw: String, _ rhsRaw: String) -> Bool {
        let lhsTitle = normalized(lhsRaw)
        let rhsTitle = normalized(rhsRaw)
        if lhsTitle.isEmpty || rhsTitle.isEmpty { return false }
        if lhsTitle == rhsTitle { return true }
        if lhsTitle.contains(rhsTitle) || rhsTitle.contains(lhsTitle) { return true }
        return tokenOverlap(lhsTitle, rhsTitle) >= 0.5
    }

    private static func sameChild(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        let lhsChild = normalized(lhs.childName)
        let rhsChild = normalized(rhs.childName)
        return !lhsChild.isEmpty && lhsChild == rhsChild
    }

    private static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }

    private static func withinMinutes(_ lhs: Date, _ rhs: Date, threshold: Int) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) <= Double(threshold * 60)
    }

    private static func tokenOverlap(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(tokens(lhs))
        let rhsTokens = Set(tokens(rhs))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let intersection = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private static func tokens(_ value: String) -> [String] {
        value
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
            .filter { $0.count >= 2 }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Legacy helper kept for compatibility with existing reference calls.
    @available(*, deprecated, message: "Use withinMinutes(_:_:threshold:) instead.")
    private static func sameMinute(_ lhs: Date, _ rhs: Date) -> Bool {
        withinMinutes(lhs, rhs, threshold: 1)
    }

    @available(*, deprecated, message: "Use isLikelySameEvent(_:_) instead.")
    private static func isDuplicateLikePair(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        let lhsLocation = normalized(lhs.location)
        let rhsLocation = normalized(rhs.location)
        let locationMatches = !lhsLocation.isEmpty && lhsLocation == rhsLocation

        let lhsTitle = normalized(lhs.title)
        let rhsTitle = normalized(rhs.title)
        let exactOrContainedTitle = lhsTitle == rhsTitle || lhsTitle.contains(rhsTitle) || rhsTitle.contains(lhsTitle)

        let titleSimilarity = tokenOverlap(lhsTitle, rhsTitle)

        return locationMatches || exactOrContainedTitle || titleSimilarity >= 0.6
    }
}
