import SwiftUI

extension EventAssignment {
    /// Icon for compact assignment chips (lists/cards). Only used when assignment is not `.unassigned`.
    var chipIconSystemName: String {
        switch self {
        case .unassigned:
            return "questionmark.circle"
        case .mom:
            return "figure.dress.line.vertical.figure"
        case .dad:
            return "figure"
        case .either:
            return "person.2.fill"
        }
    }

    /// Tint for compact assignment chips (lists/cards).
    var chipTint: Color {
        switch self {
        case .unassigned:
            return .secondary
        case .mom:
            return .pink
        case .dad:
            return .blue
        case .either:
            return .teal
        }
    }
}
