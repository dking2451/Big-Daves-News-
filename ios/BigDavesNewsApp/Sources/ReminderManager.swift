import Foundation
import UserNotifications

@MainActor
final class SportsAlertsManager: ObservableObject {
    static let shared = SportsAlertsManager()

    @Published var alertsEnabled: Bool
    @Published var startAlertsEnabled: Bool
    @Published var closeGameAlertsEnabled: Bool
    @Published var digestModeEnabled: Bool
    @Published var quietHoursEnabled: Bool
    @Published var quietHoursStartHour: Int
    @Published var quietHoursStartMinute: Int
    @Published var quietHoursEndHour: Int
    @Published var quietHoursEndMinute: Int
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let deviceID = WatchDeviceIdentity.current
    private let alertsEnabledKey = "bdn-sports-alerts-enabled-ios"
    private let startAlertsEnabledKey = "bdn-sports-alerts-start-enabled-ios"
    private let closeAlertsEnabledKey = "bdn-sports-alerts-close-enabled-ios"
    private let digestEnabledKey = "bdn-sports-alerts-digest-enabled-ios"
    private let quietHoursEnabledKey = "bdn-sports-alerts-quiet-enabled-ios"
    private let quietStartHourKey = "bdn-sports-alerts-quiet-start-hour-ios"
    private let quietStartMinuteKey = "bdn-sports-alerts-quiet-start-minute-ios"
    private let quietEndHourKey = "bdn-sports-alerts-quiet-end-hour-ios"
    private let quietEndMinuteKey = "bdn-sports-alerts-quiet-end-minute-ios"
    private let historyKey = "bdn-sports-alerts-history-ios"
    private let lastRefreshEpochKey = "bdn-sports-alerts-last-refresh-epoch-ios"
    private let notificationPrefix = "bdn-sports-alert-"

    private init() {
        let defaults = UserDefaults.standard
        alertsEnabled = defaults.bool(forKey: alertsEnabledKey)
        if defaults.object(forKey: startAlertsEnabledKey) == nil {
            defaults.set(true, forKey: startAlertsEnabledKey)
        }
        if defaults.object(forKey: closeAlertsEnabledKey) == nil {
            defaults.set(true, forKey: closeAlertsEnabledKey)
        }
        startAlertsEnabled = defaults.bool(forKey: startAlertsEnabledKey)
        closeGameAlertsEnabled = defaults.bool(forKey: closeAlertsEnabledKey)
        digestModeEnabled = defaults.bool(forKey: digestEnabledKey)
        quietHoursEnabled = defaults.object(forKey: quietHoursEnabledKey) as? Bool ?? true
        quietHoursStartHour = defaults.object(forKey: quietStartHourKey) as? Int ?? 22
        quietHoursStartMinute = defaults.object(forKey: quietStartMinuteKey) as? Int ?? 0
        quietHoursEndHour = defaults.object(forKey: quietEndHourKey) as? Int ?? 7
        quietHoursEndMinute = defaults.object(forKey: quietEndMinuteKey) as? Int ?? 0
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func updateAlertsEnabled(_ enabled: Bool) async {
        if enabled {
            let center = UNUserNotificationCenter.current()
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            guard granted == true else {
                alertsEnabled = false
                persist()
                return
            }
            alertsEnabled = true
            persist()
            await trackSettingsEvent("sports_alerts_enabled", props: ["enabled": "true"])
            await refreshScheduledAlerts(force: true)
            return
        }
        alertsEnabled = false
        persist()
        await removePendingSportsNotifications()
        await trackSettingsEvent("sports_alerts_enabled", props: ["enabled": "false"])
    }

    func updateStartAlertsEnabled(_ enabled: Bool) async {
        startAlertsEnabled = enabled
        persist()
        await trackSettingsEvent("sports_alerts_start_toggle", props: ["enabled": enabled ? "true" : "false"])
        await refreshScheduledAlerts(force: true)
    }

    func updateCloseGameAlertsEnabled(_ enabled: Bool) async {
        closeGameAlertsEnabled = enabled
        persist()
        await trackSettingsEvent("sports_alerts_close_toggle", props: ["enabled": enabled ? "true" : "false"])
        await refreshScheduledAlerts(force: true)
    }

    func updateDigestModeEnabled(_ enabled: Bool) async {
        digestModeEnabled = enabled
        persist()
        await trackSettingsEvent("sports_alerts_digest_toggle", props: ["enabled": enabled ? "true" : "false"])
        await refreshScheduledAlerts(force: true)
    }

    func updateQuietHoursEnabled(_ enabled: Bool) async {
        quietHoursEnabled = enabled
        persist()
        await trackSettingsEvent("sports_alerts_quiet_hours_toggle", props: ["enabled": enabled ? "true" : "false"])
        await refreshScheduledAlerts(force: true)
    }

    func updateQuietHours(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) async {
        quietHoursStartHour = max(0, min(23, startHour))
        quietHoursStartMinute = max(0, min(59, startMinute))
        quietHoursEndHour = max(0, min(23, endHour))
        quietHoursEndMinute = max(0, min(59, endMinute))
        persist()
        await trackSettingsEvent(
            "sports_alerts_quiet_hours_time",
            props: [
                "start": "\(quietHoursStartHour):\(quietHoursStartMinute)",
                "end": "\(quietHoursEndHour):\(quietHoursEndMinute)"
            ]
        )
        await refreshScheduledAlerts(force: true)
    }

    func refreshScheduledAlerts(force: Bool = false) async {
        await refreshAuthorizationStatus()
        guard alertsEnabled else {
            await removePendingSportsNotifications()
            return
        }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            return
        }
        let now = Date().timeIntervalSince1970
        let lastRefresh = UserDefaults.standard.double(forKey: lastRefreshEpochKey)
        if !force, lastRefresh > 0, now - lastRefresh < 600 {
            return
        }
        UserDefaults.standard.set(now, forKey: lastRefreshEpochKey)

        do {
            let effectiveProvider = SportsProviderPreferences.backendEffectiveProviderKeyFromDefaults
            let availabilityOnly = UserDefaults.standard.bool(
                forKey: SportsProviderPreferences.availabilityOnlyStorageKey
            ) && effectiveProvider != SportsProviderPreferences.allProviderKey
            let backendProvider = effectiveProvider == SportsProviderPreferences.allProviderKey ? "" : effectiveProvider
            let result = try await APIClient.shared.fetchSportsNow(
                windowHours: 8,
                timezoneName: TimeZone.current.identifier,
                providerKey: backendProvider,
                availabilityOnly: availabilityOnly,
                deviceID: deviceID,
                includeOcho: false
            )
            await scheduleNotifications(from: result.items)
        } catch {
            // Keep existing scheduled alerts on fetch failures.
        }
    }

    func ingestLatestSports(items: [SportsEventItem]) async {
        guard alertsEnabled else { return }
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            return
        }
        await scheduleNotifications(from: items)
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(alertsEnabled, forKey: alertsEnabledKey)
        defaults.set(startAlertsEnabled, forKey: startAlertsEnabledKey)
        defaults.set(closeGameAlertsEnabled, forKey: closeAlertsEnabledKey)
        defaults.set(digestModeEnabled, forKey: digestEnabledKey)
        defaults.set(quietHoursEnabled, forKey: quietHoursEnabledKey)
        defaults.set(quietHoursStartHour, forKey: quietStartHourKey)
        defaults.set(quietHoursStartMinute, forKey: quietStartMinuteKey)
        defaults.set(quietHoursEndHour, forKey: quietEndHourKey)
        defaults.set(quietHoursEndMinute, forKey: quietEndMinuteKey)
    }

    private func scheduleNotifications(from items: [SportsEventItem]) async {
        await removePendingSportsNotifications()
        guard startAlertsEnabled || closeGameAlertsEnabled else { return }

        let center = UNUserNotificationCenter.current()
        let now = Date()
        let startCount = await scheduleStartAlerts(items: items, center: center, now: now)
        let closeCount = await scheduleCloseGameAlerts(items: items, center: center, now: now)
        let scheduledCount = startCount + closeCount
        await trackSettingsEvent("sports_alerts_scheduled", props: ["count": String(scheduledCount)])
    }

    private func scheduleStartAlerts(items: [SportsEventItem], center: UNUserNotificationCenter, now: Date) async -> Int {
        guard startAlertsEnabled else { return 0 }
        let candidates = items
            .filter { !$0.isLive && !$0.isFinal && $0.startsInMinutes >= 10 && $0.startsInMinutes <= 150 }
            .sorted { $0.startsInMinutes < $1.startsInMinutes }

        if digestModeEnabled {
            guard !candidates.isEmpty else { return 0 }
            let soonest = max(60, (candidates[0].startsInMinutes - 5) * 60)
            let fireDate = now.addingTimeInterval(TimeInterval(soonest))
            if isDuringQuietHours(fireDate) { return 0 }
            let token = "start-digest-\(dayToken(from: fireDate))"
            guard !hasSeenAlertToken(token) else { return 0 }
            let content = UNMutableNotificationContent()
            content.title = "Sports Update"
            content.body = "\(candidates.count) games are starting soon."
            content.sound = .default
            content.userInfo = ["deep_link": "sports", "alert_type": "sports_start_digest"]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(soonest), repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(notificationPrefix)start-digest",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
            rememberAlertToken(token)
            return 1
        }

        var scheduled = 0
        for item in candidates.prefix(4) {
            let token = "start-\(item.id)"
            guard !hasSeenAlertToken(token) else { continue }
            let secondsUntilAlert = max(60, (item.startsInMinutes - 5) * 60)
            let fireDate = now.addingTimeInterval(TimeInterval(secondsUntilAlert))
            if isDuringQuietHours(fireDate) { continue }
            let content = UNMutableNotificationContent()
            content.title = "Starting Soon: \(item.league)"
            content.body = "\(item.awayTeam) vs \(item.homeTeam) starts in about \(max(1, item.startsInMinutes))m."
            content.sound = .default
            content.userInfo = [
                "deep_link": "sports",
                "alert_type": "sports_start",
                "event_id": item.id
            ]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(secondsUntilAlert), repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(notificationPrefix)start-\(item.id)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
            rememberAlertToken(token)
            scheduled += 1
        }
        return scheduled
    }

    private func scheduleCloseGameAlerts(items: [SportsEventItem], center: UNUserNotificationCenter, now: Date) async -> Int {
        guard closeGameAlertsEnabled else { return 0 }
        let candidates = items
            .filter { $0.isLive && !$0.isFinal && isCloseGame($0) }
            .sorted { scoreDelta($0) < scoreDelta($1) }

        if digestModeEnabled {
            guard !candidates.isEmpty else { return 0 }
            let fireDate = now.addingTimeInterval(90)
            if isDuringQuietHours(fireDate) { return 0 }
            let token = "close-digest-\(dayToken(from: fireDate))"
            guard !hasSeenAlertToken(token) else { return 0 }
            let content = UNMutableNotificationContent()
            content.title = "Close Games Live"
            content.body = "\(candidates.count) live games are close right now."
            content.sound = .default
            content.userInfo = ["deep_link": "sports", "alert_type": "sports_close_digest"]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 90, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(notificationPrefix)close-digest",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
            rememberAlertToken(token)
            return 1
        }

        var scheduled = 0
        for item in candidates.prefix(3) {
            let token = "close-\(item.id)"
            guard !hasSeenAlertToken(token) else { continue }
            let fireDate = now.addingTimeInterval(90)
            if isDuringQuietHours(fireDate) { continue }
            let diff = scoreDelta(item)
            let content = UNMutableNotificationContent()
            content.title = "Close Game: \(item.league)"
            content.body = "\(item.awayTeam) \(item.awayScore) - \(item.homeTeam) \(item.homeScore) (\(diff)-point game)."
            content.sound = .default
            content.userInfo = [
                "deep_link": "sports",
                "alert_type": "sports_close",
                "event_id": item.id
            ]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 90, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(notificationPrefix)close-\(item.id)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
            rememberAlertToken(token)
            scheduled += 1
        }
        return scheduled
    }

    private func isCloseGame(_ item: SportsEventItem) -> Bool {
        let threshold = closeGameThreshold(sport: item.sport, league: item.league)
        return scoreDelta(item) <= threshold
    }

    private func scoreDelta(_ item: SportsEventItem) -> Int {
        let home = Int(item.homeScore.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let away = Int(item.awayScore.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        if home == 0 && away == 0 { return Int.max }
        return abs(home - away)
    }

    private func closeGameThreshold(sport: String, league: String) -> Int {
        let normalizedSport = sport.lowercased()
        let normalizedLeague = league.lowercased()
        if normalizedSport.contains("basketball") || normalizedLeague.contains("nba") || normalizedLeague.contains("wnba") {
            return 6
        }
        if normalizedSport.contains("football") || normalizedLeague.contains("nfl") || normalizedLeague.contains("ncaa") {
            return 8
        }
        if normalizedSport.contains("baseball") || normalizedLeague.contains("mlb") {
            return 1
        }
        if normalizedSport.contains("hockey") || normalizedLeague.contains("nhl") || normalizedSport.contains("soccer") {
            return 1
        }
        return 3
    }

    private func isDuringQuietHours(_ date: Date) -> Bool {
        guard quietHoursEnabled else { return false }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let target = hour * 60 + minute
        let start = quietHoursStartHour * 60 + quietHoursStartMinute
        let end = quietHoursEndHour * 60 + quietHoursEndMinute
        if start == end { return false }
        if start < end {
            return target >= start && target < end
        }
        return target >= start || target < end
    }

    private func hasSeenAlertToken(_ token: String) -> Bool {
        let history = Set(UserDefaults.standard.stringArray(forKey: historyKey) ?? [])
        return history.contains(token)
    }

    private func rememberAlertToken(_ token: String) {
        var history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        if history.contains(token) { return }
        history.append(token)
        if history.count > 300 {
            history.removeFirst(history.count - 300)
        }
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    private func dayToken(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func removePendingSportsNotifications() async {
        let requests = await pendingRequests()
        let ids = requests.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) }
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func trackSettingsEvent(_ name: String, props: [String: String]) async {
        await APIClient.shared.trackEvent(
            deviceID: deviceID,
            eventName: name,
            eventProps: props
        )
    }
}
