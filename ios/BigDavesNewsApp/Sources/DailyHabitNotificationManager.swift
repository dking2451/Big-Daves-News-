import Foundation
import UserNotifications

/// Local notifications for the daily habit loop: morning brief + evening Watch prompt.
/// Quiet hours nudge scheduled times to the nearest valid slot inside each window (7–9am, 6–8pm).
@MainActor
final class DailyHabitNotificationManager: ObservableObject {
    static let shared = DailyHabitNotificationManager()

    static let enabledStorageKey = "bdn-habit-enabled-ios"

    @Published var habitNotificationsEnabled: Bool
    @Published var morningEnabled: Bool
    @Published var eveningEnabled: Bool
    @Published var morningHour: Int
    @Published var morningMinute: Int
    @Published var eveningHour: Int
    @Published var eveningMinute: Int
    @Published var quietHoursEnabled: Bool
    @Published var quietStartHour: Int
    @Published var quietStartMinute: Int
    @Published var quietEndHour: Int
    @Published var quietEndMinute: Int
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let morningIdentifier = "bdn-habit-morning"
    private let eveningIdentifier = "bdn-habit-evening"
    private let legacyReminderIdentifier = "bdn-daily-reminder"
    private let legacyMigratedKey = "bdn-habit-legacy-reminder-migrated-v1"

    private let morningEnabledKey = "bdn-habit-morning-enabled-ios"
    private let eveningEnabledKey = "bdn-habit-evening-enabled-ios"
    private let morningHourKey = "bdn-habit-morning-hour-ios"
    private let morningMinuteKey = "bdn-habit-morning-minute-ios"
    private let eveningHourKey = "bdn-habit-evening-hour-ios"
    private let eveningMinuteKey = "bdn-habit-evening-minute-ios"
    private let quietEnabledKey = "bdn-habit-quiet-enabled-ios"
    private let quietStartHourKey = "bdn-habit-quiet-start-hour-ios"
    private let quietStartMinuteKey = "bdn-habit-quiet-start-minute-ios"
    private let quietEndHourKey = "bdn-habit-quiet-end-hour-ios"
    private let quietEndMinuteKey = "bdn-habit-quiet-end-minute-ios"

    private init() {
        let d = UserDefaults.standard
        habitNotificationsEnabled = d.bool(forKey: Self.enabledStorageKey)
        morningEnabled = d.object(forKey: morningEnabledKey) as? Bool ?? true
        eveningEnabled = d.object(forKey: eveningEnabledKey) as? Bool ?? true
        morningHour = d.object(forKey: morningHourKey) as? Int ?? 8
        morningMinute = d.object(forKey: morningMinuteKey) as? Int ?? 0
        eveningHour = d.object(forKey: eveningHourKey) as? Int ?? 19
        eveningMinute = d.object(forKey: eveningMinuteKey) as? Int ?? 0
        quietHoursEnabled = d.object(forKey: quietEnabledKey) as? Bool ?? true
        quietStartHour = d.object(forKey: quietStartHourKey) as? Int ?? 22
        quietStartMinute = d.object(forKey: quietStartMinuteKey) as? Int ?? 0
        quietEndHour = d.object(forKey: quietEndHourKey) as? Int ?? 7
        quietEndMinute = d.object(forKey: quietEndMinuteKey) as? Int ?? 0
        migrateLegacyReminderIfNeeded()
        clampStoredTimesToWindows()
        persist()
        Task { await refreshAuthorizationStatus() }
        Task { await rescheduleAll() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Requests permission, enables habit notifications, registers push (same as legacy brief flow), and schedules.
    func requestAndEnable() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorizationStatus()
        guard granted else { return }
        habitNotificationsEnabled = true
        persist()
        PushTokenManager.shared.requestSystemTokenRegistration()
        await PushTokenManager.shared.registerWithBackendIfPossible()
        await rescheduleAll()
    }

    func disable() async {
        habitNotificationsEnabled = false
        persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [morningIdentifier, eveningIdentifier])
        await PushTokenManager.shared.unregisterFromBackendIfPossible()
    }

    func setMorningEnabled(_ enabled: Bool) async {
        morningEnabled = enabled
        persist()
        await rescheduleAll()
    }

    func setEveningEnabled(_ enabled: Bool) async {
        eveningEnabled = enabled
        persist()
        await rescheduleAll()
    }

    func updateMorningTime(hour: Int, minute: Int) async {
        morningHour = clamp(hour, min: 7, max: 9)
        morningMinute = clamp(minute, min: 0, max: 59)
        persist()
        await rescheduleAll()
    }

    func updateEveningTime(hour: Int, minute: Int) async {
        eveningHour = clamp(hour, min: 18, max: 20)
        eveningMinute = clamp(minute, min: 0, max: 59)
        persist()
        await rescheduleAll()
    }

    func updateQuietHours(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) async {
        quietStartHour = clamp(startHour, min: 0, max: 23)
        quietStartMinute = clamp(startMinute, min: 0, max: 59)
        quietEndHour = clamp(endHour, min: 0, max: 23)
        quietEndMinute = clamp(endMinute, min: 0, max: 59)
        persist()
        await rescheduleAll()
    }

    func setQuietHoursEnabled(_ enabled: Bool) async {
        quietHoursEnabled = enabled
        persist()
        await rescheduleAll()
    }

    // MARK: - Scheduling

    func rescheduleAll() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningIdentifier, eveningIdentifier])
        await refreshAuthorizationStatus()
        guard habitNotificationsEnabled else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            return
        }

        if morningEnabled {
            if let (h, m) = resolveFireInWindow(
                windowStartHour: 7,
                windowEndHour: 9,
                preferredHour: morningHour,
                preferredMinute: morningMinute
            ) {
                let content = UNMutableNotificationContent()
                content.title = "Big Daves News"
                content.body = "Your Brief is ready"
                content.sound = .default
                content.userInfo = ["deep_link": "brief", "habit": "morning"]

                var components = DateComponents()
                components.hour = h
                components.minute = m
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(identifier: morningIdentifier, content: content, trigger: trigger)
                try? await center.add(request)
            }
        }

        if eveningEnabled {
            if let (h, m) = resolveFireInWindow(
                windowStartHour: 18,
                windowEndHour: 20,
                preferredHour: eveningHour,
                preferredMinute: eveningMinute
            ) {
                let content = UNMutableNotificationContent()
                content.title = "Big Daves News"
                content.body = "2 new episodes + tonight's top pick"
                content.sound = .default
                content.userInfo = ["deep_link": "watch", "habit": "evening"]

                var components = DateComponents()
                components.hour = h
                components.minute = m
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(identifier: eveningIdentifier, content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }

    // MARK: - Quiet hours + window resolution

    private func resolveFireInWindow(
        windowStartHour: Int,
        windowEndHour: Int,
        preferredHour: Int,
        preferredMinute: Int
    ) -> (Int, Int)? {
        let windowLo = windowStartHour * 60
        let windowHi = windowEndHour * 60 + 59
        var pref = totalMinutes(hour: preferredHour, minute: preferredMinute)
        pref = min(max(pref, windowLo), windowHi)

        if !quietHoursEnabled {
            return splitMinutes(pref)
        }

        let h = pref / 60
        let m = pref % 60
        if !isInQuietPeriod(hour: h, minute: m) {
            return (h, m)
        }

        for delta in 0 ... (windowHi - windowLo) {
            let forward = pref + delta
            let backward = pref - delta
            if forward <= windowHi {
                let fh = forward / 60
                let fm = forward % 60
                if !isInQuietPeriod(hour: fh, minute: fm) {
                    return (fh, fm)
                }
            }
            if backward >= windowLo && backward != forward {
                let bh = backward / 60
                let bm = backward % 60
                if !isInQuietPeriod(hour: bh, minute: bm) {
                    return (bh, bm)
                }
            }
        }
        return nil
    }

    private func isInQuietPeriod(hour: Int, minute: Int) -> Bool {
        let t = totalMinutes(hour: hour, minute: minute)
        let qs = totalMinutes(hour: quietStartHour, minute: quietStartMinute)
        let qe = totalMinutes(hour: quietEndHour, minute: quietEndMinute)
        if qs == qe { return false }
        if qs < qe {
            return t >= qs && t < qe
        }
        return t >= qs || t < qe
    }

    private func totalMinutes(hour: Int, minute: Int) -> Int {
        hour * 60 + minute
    }

    private func splitMinutes(_ total: Int) -> (Int, Int) {
        (total / 60, total % 60)
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.min(Swift.max(value, min), max)
    }

    private func clampStoredTimesToWindows() {
        morningHour = clamp(morningHour, min: 7, max: 9)
        morningMinute = clamp(morningMinute, min: 0, max: 59)
        eveningHour = clamp(eveningHour, min: 18, max: 20)
        eveningMinute = clamp(eveningMinute, min: 0, max: 59)
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(habitNotificationsEnabled, forKey: Self.enabledStorageKey)
        d.set(morningEnabled, forKey: morningEnabledKey)
        d.set(eveningEnabled, forKey: eveningEnabledKey)
        d.set(morningHour, forKey: morningHourKey)
        d.set(morningMinute, forKey: morningMinuteKey)
        d.set(eveningHour, forKey: eveningHourKey)
        d.set(eveningMinute, forKey: eveningMinuteKey)
        d.set(quietHoursEnabled, forKey: quietEnabledKey)
        d.set(quietStartHour, forKey: quietStartHourKey)
        d.set(quietStartMinute, forKey: quietStartMinuteKey)
        d.set(quietEndHour, forKey: quietEndHourKey)
        d.set(quietEndMinute, forKey: quietEndMinuteKey)
    }

    private func migrateLegacyReminderIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: legacyMigratedKey) else { return }
        d.set(true, forKey: legacyMigratedKey)

        guard d.bool(forKey: "bdn-reminder-enabled-ios") else { return }

        habitNotificationsEnabled = true
        morningEnabled = true
        if let h = d.object(forKey: "bdn-reminder-hour-ios") as? Int {
            morningHour = clamp(h, min: 7, max: 9)
        }
        if let m = d.object(forKey: "bdn-reminder-minute-ios") as? Int {
            morningMinute = clamp(m, min: 0, max: 59)
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [legacyReminderIdentifier])
        d.set(false, forKey: "bdn-reminder-enabled-ios")
    }
}
