import Foundation

/// First-launch routing, splash, and one-time “first value” hint after personalization onboarding.
enum FirstRunExperience {
    /// Shown once after user taps **Start Exploring** (saved prefs). Cleared when hint dismisses.
    static let firstValueTooltipPendingKey = "bdn-first-value-tooltip-pending"

    static var isFirstValueTooltipPending: Bool {
        UserDefaults.standard.bool(forKey: firstValueTooltipPendingKey)
    }

    static func markFirstValueTooltipPending() {
        UserDefaults.standard.set(true, forKey: firstValueTooltipPendingKey)
    }

    static func clearFirstValueTooltipPending() {
        UserDefaults.standard.set(false, forKey: firstValueTooltipPendingKey)
    }
}
