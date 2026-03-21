import Foundation

/// Display-only grouping: same-child duplicates **or** multiple children at the same real-world moment.
struct GroupedEvent: Identifiable {
    let primary: FamilyEvent
    let events: [FamilyEvent]

    var id: String {
        EventDisplayGrouping.key(for: primary)
    }

    var combinedCount: Int {
        events.count
    }

    /// Unique child names in this group (trimmed, sorted).
    var uniqueChildNames: [String] {
        let raw = events.map { $0.childName.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Array(Set(raw)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// True when more than one distinct child appears (family moment row).
    var isCrossChildFamilyMoment: Bool {
        uniqueChildNames.count > 1
    }

    /// e.g. `"Emma, Jack"` or `"Emma, Jack +2 more"` when more than `maxLeading` children.
    func childNamesDisplayLine(maxLeading: Int = 2) -> String {
        let names = uniqueChildNames
        guard names.count > 1 else { return names.first ?? "" }
        if names.count <= maxLeading {
            return names.joined(separator: ", ")
        }
        let leading = names.prefix(maxLeading).joined(separator: ", ")
        let more = names.count - maxLeading
        return "\(leading) +\(more) more"
    }
}

enum EventDisplayGrouping {
    /// Groups events for list display (same-child duplicates + cross-child same moment).
    static func groupedDisplayEvents(events: [FamilyEvent]) -> [GroupedEvent] {
        groupedFamilyEvents(events: events)
    }

    /// Same as `groupedDisplayEvents` — explicit name for “family moment” aware grouping.
    static func groupedFamilyEvents(events: [FamilyEvent]) -> [GroupedEvent] {
        let sorted = events.sorted {
            if $0.startDateTime == $1.startDateTime {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.startDateTime < $1.startDateTime
        }

        var groups: [[FamilyEvent]] = []

        for event in sorted {
            var placed = false
            for index in groups.indices {
                if groups[index].contains(where: { isSameFamilyEvent($0, event) }) {
                    groups[index].append(event)
                    placed = true
                    break
                }
            }
            if !placed {
                groups.append([event])
            }
        }

        return groups.map { group in
            let ordered = group.sorted {
                if $0.startDateTime == $1.startDateTime {
                    if $0.updatedAt == $1.updatedAt {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.startDateTime < $1.startDateTime
            }
            return GroupedEvent(primary: ordered[0], events: ordered)
        }
        .sorted { lhs, rhs in
            if lhs.primary.startDateTime == rhs.primary.startDateTime {
                return lhs.primary.id.uuidString < rhs.primary.id.uuidString
            }
            return lhs.primary.startDateTime < rhs.primary.startDateTime
        }
    }

    /// True if two events should show as one row (same-child duplicate **or** cross-child same moment).
    static func isSameFamilyEvent(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        if sameChild(lhs, rhs) {
            return isDuplicateLikeSameChild(lhs, rhs)
        }
        if distinctChildren(lhs, rhs) {
            return isSameFamilyMomentAcrossChildren(lhs, rhs)
        }
        return false
    }

    /// Legacy name: same-child duplicate-like only (subset of `isSameFamilyEvent`).
    static func isLikelySameEvent(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        guard sameChild(lhs, rhs) else { return false }
        return isDuplicateLikeSameChild(lhs, rhs)
    }

    static func key(for event: FamilyEvent) -> String {
        "\(event.id.uuidString)-\(Int(event.startDateTime.timeIntervalSince1970))"
    }

    // MARK: - Same child (duplicate-like)

    private static func isDuplicateLikeSameChild(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        guard Calendar.current.isDate(lhs.startDateTime, inSameDayAs: rhs.startDateTime) else { return false }
        guard withinMinutes(lhs.startDateTime, rhs.startDateTime, threshold: 15) else { return false }
        guard withinMinutes(lhs.endDateTime, rhs.endDateTime, threshold: 15) else { return false }
        guard lhs.category == rhs.category else { return false }
        guard similarTitle(lhs.title, rhs.title) else { return false }
        guard similarLocation(lhs.location, rhs.location) else { return false }
        return true
    }

    // MARK: - Different children, same moment

    private static func isSameFamilyMomentAcrossChildren(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        guard Calendar.current.isDate(lhs.startDateTime, inSameDayAs: rhs.startDateTime) else { return false }
        guard withinMinutes(lhs.startDateTime, rhs.startDateTime, threshold: 15) else { return false }
        guard withinMinutes(lhs.endDateTime, rhs.endDateTime, threshold: 15) else { return false }
        guard lhs.category == rhs.category else { return false }
        guard similarTitle(lhs.title, rhs.title) else { return false }
        let lLoc = normalized(lhs.location)
        let rLoc = normalized(rhs.location)
        guard !lLoc.isEmpty, !rLoc.isEmpty else { return false }
        guard similarLocation(lhs.location, rhs.location) else { return false }
        return true
    }

    private static func sameChild(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        let left = normalized(lhs.childName)
        let right = normalized(rhs.childName)
        return !left.isEmpty && left == right
    }

    private static func distinctChildren(_ lhs: FamilyEvent, _ rhs: FamilyEvent) -> Bool {
        let left = normalized(lhs.childName)
        let right = normalized(rhs.childName)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left != right
    }

    private static func withinMinutes(_ lhs: Date, _ rhs: Date, threshold: Int) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) <= Double(threshold * 60)
    }

    private static func similarLocation(_ lhsRaw: String, _ rhsRaw: String) -> Bool {
        let lhs = normalized(lhsRaw)
        let rhs = normalized(rhsRaw)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs { return true }
        return tokenOverlap(lhs, rhs) >= 0.7
    }

    private static func similarTitle(_ lhsRaw: String, _ rhsRaw: String) -> Bool {
        let lhs = normalized(lhsRaw)
        let rhs = normalized(rhsRaw)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs { return true }
        if lhs.contains(rhs) || rhs.contains(lhs) { return true }
        return tokenOverlap(lhs, rhs) >= 0.55
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
}
