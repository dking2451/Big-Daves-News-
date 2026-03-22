import Combine
import Foundation
import SwiftUI

// MARK: - Environment

private struct TonightModeActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// True during local “evening” hours (~6pm–5:59am) for a subtle entertainment-focused treatment.
    var tonightModeActive: Bool {
        get { self[TonightModeActiveKey.self] }
        set { self[TonightModeActiveKey.self] = newValue }
    }
}

// MARK: - Time-based state

/// Drives Tonight Mode: automatic after ~6pm local through early morning (entertainment / “what’s on” window).
@MainActor
final class TonightModeManager: ObservableObject {
    static let shared = TonightModeManager()

    /// 6:00 PM inclusive through 5:59 AM next day (local calendar).
    @Published private(set) var isActive: Bool = false

    private var minuteTicker: AnyCancellable?

    private init() {
        refresh()
        minuteTicker = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    /// Call when app becomes active to catch boundary crossings without waiting for the next minute tick.
    func refresh() {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let next = (hour >= 18) || (hour < 6)
        if next != isActive {
            isActive = next
        }
    }

    /// Slightly warmer / entertainment-leaning accent for tab bar & key controls (subtle vs. daytime blue).
    var accentColor: Color {
        isActive
            ? Color(red: 0.45, green: 0.32, blue: 0.78)
            : AppTheme.primary
    }
}
