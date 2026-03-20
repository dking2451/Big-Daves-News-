import Foundation
import UserNotifications

struct LocalNotificationService {
    private let center = UNUserNotificationCenter.current()
    private let notificationPrefix = "familyos.event."
    private let leadTimes: [(seconds: TimeInterval, label: String)] = [
        (3600, "in 1 hour"),
        (1800, "in 30 minutes"),
    ]

    func syncNotifications(for events: [FamilyEvent]) async {
        guard await ensureAuthorization() else { return }

        await clearManagedNotifications()

        let now = Date()
        for event in events {
            for leadTime in leadTimes {
                let fireDate = event.startDateTime.addingTimeInterval(-leadTime.seconds)
                guard fireDate > now else { continue }
                await schedule(event: event, fireDate: fireDate, leadLabel: leadTime.label, leadSeconds: leadTime.seconds)
            }
        }
    }

    private func ensureAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func clearManagedNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(notificationPrefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private func schedule(
        event: FamilyEvent,
        fireDate: Date,
        leadLabel: String,
        leadSeconds: TimeInterval
    ) async {
        let content = UNMutableNotificationContent()
        content.title = event.title.isEmpty ? "Upcoming event" : event.title
        content.body = "Starts at \(formattedTime(event.startDateTime)) \(leadLabel)."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let occurrence = Int(event.startDateTime.timeIntervalSince1970)
        let identifier = "\(notificationPrefix)\(event.id.uuidString).\(occurrence).\(Int(leadSeconds))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Ignore individual scheduling failures to avoid blocking other notifications.
        }
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
