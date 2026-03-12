import Foundation
import UserNotifications

@MainActor
final class ReminderManager: ObservableObject {
    @Published var remindersEnabled: Bool = UserDefaults.standard.bool(forKey: "bdn-reminder-enabled-ios")
    @Published var reminderHour: Int = UserDefaults.standard.object(forKey: "bdn-reminder-hour-ios") as? Int ?? 8
    @Published var reminderMinute: Int = UserDefaults.standard.object(forKey: "bdn-reminder-minute-ios") as? Int ?? 0
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAndEnableReminder() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorizationStatus()
        guard granted else { return }
        remindersEnabled = true
        persist()
        PushTokenManager.shared.requestSystemTokenRegistration()
        await PushTokenManager.shared.registerWithBackendIfPossible()
        try await scheduleReminder()
    }

    func disableReminder() async {
        remindersEnabled = false
        persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["bdn-daily-reminder"])
        await PushTokenManager.shared.unregisterFromBackendIfPossible()
    }

    func updateReminderTime(hour: Int, minute: Int) async throws {
        reminderHour = hour
        reminderMinute = minute
        persist()
        if remindersEnabled {
            try await scheduleReminder()
        }
    }

    private func persist() {
        UserDefaults.standard.set(remindersEnabled, forKey: "bdn-reminder-enabled-ios")
        UserDefaults.standard.set(reminderHour, forKey: "bdn-reminder-hour-ios")
        UserDefaults.standard.set(reminderMinute, forKey: "bdn-reminder-minute-ios")
    }

    private func scheduleReminder() async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["bdn-daily-reminder"])

        var components = DateComponents()
        components.hour = reminderHour
        components.minute = reminderMinute

        let content = UNMutableNotificationContent()
        content.title = "Big Daves News"
        content.body = "Your daily brief is ready. Open the app for the latest headlines."
        content.sound = .default
        content.userInfo = ["deep_link": "brief"]

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "bdn-daily-reminder",
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }
}
