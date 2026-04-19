import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var watchEpisodeAlertsEnabled = false
    @Published var upcomingReleaseRemindersEnabled = false
    @Published var watchPrefsStatus = ""
    @Published var watchPrefsSyncing = false
    private let watchDeviceID = WatchDeviceIdentity.current

    func loadWatchPreferences() async {
        do {
            let prefs = try await APIClient.shared.fetchWatchPreferences(deviceID: watchDeviceID)
            watchEpisodeAlertsEnabled = prefs.watchEpisodeAlerts
            upcomingReleaseRemindersEnabled = prefs.upcomingReleaseReminders
            watchPrefsStatus = ""
        } catch {
            watchPrefsStatus = "Could not load watch alert settings."
        }
    }

    func updateWatchPreferences(watchEpisodeAlerts: Bool? = nil, upcomingReleaseReminders: Bool? = nil) async {
        let newEpisodeAlerts = watchEpisodeAlerts ?? watchEpisodeAlertsEnabled
        let newUpcomingReminders = upcomingReleaseReminders ?? upcomingReleaseRemindersEnabled
        watchPrefsSyncing = true
        defer { watchPrefsSyncing = false }
        do {
            try await APIClient.shared.setWatchPreferences(
                deviceID: watchDeviceID,
                watchEpisodeAlerts: newEpisodeAlerts,
                upcomingReleaseReminders: newUpcomingReminders
            )
            watchEpisodeAlertsEnabled = newEpisodeAlerts
            upcomingReleaseRemindersEnabled = newUpcomingReminders
            watchPrefsStatus = "Saved."
        } catch {
            watchPrefsStatus = "Could not save watch alert settings."
        }
    }
}

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @ObservedObject private var habitNotifications = DailyHabitNotificationManager.shared
    @StateObject private var sportsAlertsManager = SportsAlertsManager.shared
    @StateObject private var breakingNewsManager = BreakingNewsNotificationManager.shared
    @StateObject private var pushTokenManager = PushTokenManager.shared
    @State private var morningHabitTime = Date()
    @State private var eveningHabitTime = Date()
    @State private var habitQuietStartTime = Date()
    @State private var habitQuietEndTime = Date()
    @State private var sportsQuietStartTime = Date()
    @State private var sportsQuietEndTime = Date()
    @State private var showHelp = false
    @Environment(\.dismiss) private var dismissSettings
    @Environment(\.openURL) private var openURL
    @AppStorage(SportsProviderPreferences.providerKeyStorageKey) private var sportsProviderKey = SportsProviderPreferences.allProviderKey
    @AppStorage(SportsProviderPreferences.availabilityOnlyStorageKey) private var sportsAvailabilityOnly = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily habit notifications") {
                    Toggle("Enable notifications", isOn: Binding(
                        get: { habitNotifications.habitNotificationsEnabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    try? await habitNotifications.requestAndEnable()
                                } else {
                                    await habitNotifications.disable()
                                }
                            }
                        }
                    ))

                    Toggle("Morning — Brief", isOn: Binding(
                        get: { habitNotifications.morningEnabled },
                        set: { newValue in
                            Task { await habitNotifications.setMorningEnabled(newValue) }
                        }
                    ))
                    .disabled(!habitNotifications.habitNotificationsEnabled)

                    DatePicker(
                        "Morning time",
                        selection: $morningHabitTime,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!habitNotifications.habitNotificationsEnabled || !habitNotifications.morningEnabled)
                    .onChange(of: morningHabitTime) { newValue in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        let hour = comps.hour ?? 8
                        let minute = comps.minute ?? 0
                        Task {
                            await habitNotifications.updateMorningTime(hour: hour, minute: minute)
                            morningHabitTime = dateForTime(hour: habitNotifications.morningHour, minute: habitNotifications.morningMinute)
                        }
                    }

                    Toggle("Evening — Watch", isOn: Binding(
                        get: { habitNotifications.eveningEnabled },
                        set: { newValue in
                            Task { await habitNotifications.setEveningEnabled(newValue) }
                        }
                    ))
                    .disabled(!habitNotifications.habitNotificationsEnabled)

                    DatePicker(
                        "Evening time",
                        selection: $eveningHabitTime,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!habitNotifications.habitNotificationsEnabled || !habitNotifications.eveningEnabled)
                    .onChange(of: eveningHabitTime) { newValue in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        let hour = comps.hour ?? 19
                        let minute = comps.minute ?? 0
                        Task {
                            await habitNotifications.updateEveningTime(hour: hour, minute: minute)
                            eveningHabitTime = dateForTime(hour: habitNotifications.eveningHour, minute: habitNotifications.eveningMinute)
                        }
                    }

                    Toggle("Quiet hours", isOn: Binding(
                        get: { habitNotifications.quietHoursEnabled },
                        set: { newValue in
                            Task { await habitNotifications.setQuietHoursEnabled(newValue) }
                        }
                    ))
                    .disabled(!habitNotifications.habitNotificationsEnabled)

                    if habitNotifications.habitNotificationsEnabled && habitNotifications.quietHoursEnabled {
                        DatePicker(
                            "Quiet hours start",
                            selection: $habitQuietStartTime,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: habitQuietStartTime) { _ in
                            Task {
                                await habitNotifications.updateQuietHours(
                                    startHour: hourOf(habitQuietStartTime),
                                    startMinute: minuteOf(habitQuietStartTime),
                                    endHour: hourOf(habitQuietEndTime),
                                    endMinute: minuteOf(habitQuietEndTime)
                                )
                                habitQuietStartTime = dateForTime(hour: habitNotifications.quietStartHour, minute: habitNotifications.quietStartMinute)
                                habitQuietEndTime = dateForTime(hour: habitNotifications.quietEndHour, minute: habitNotifications.quietEndMinute)
                            }
                        }

                        DatePicker(
                            "Quiet hours end",
                            selection: $habitQuietEndTime,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: habitQuietEndTime) { _ in
                            Task {
                                await habitNotifications.updateQuietHours(
                                    startHour: hourOf(habitQuietStartTime),
                                    startMinute: minuteOf(habitQuietStartTime),
                                    endHour: hourOf(habitQuietEndTime),
                                    endMinute: minuteOf(habitQuietEndTime)
                                )
                                habitQuietStartTime = dateForTime(hour: habitNotifications.quietStartHour, minute: habitNotifications.quietStartMinute)
                                habitQuietEndTime = dateForTime(hour: habitNotifications.quietEndHour, minute: habitNotifications.quietEndMinute)
                            }
                        }
                    }

                    Text(habitNotificationsStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Morning fires between 7–9am, evening between 6–8pm (local). Times adjust if they fall inside quiet hours.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Last Brief Opened: \(briefLastOpenedText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Push Sync: \(pushTokenManager.syncStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("My preferences") {
                    NavigationLink {
                        UserPreferencesEditorView()
                    } label: {
                        Label("Genres, streaming & teams", systemImage: "heart.text.square")
                    }
                    Text("Saved on this device. Boosts Watch rankings and surfaces your teams in Sports lists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Watch Alerts") {
                    Toggle("Watchlist episode alerts", isOn: Binding(
                        get: { vm.watchEpisodeAlertsEnabled },
                        set: { newValue in
                            Task { await vm.updateWatchPreferences(watchEpisodeAlerts: newValue) }
                        }
                    ))
                    .disabled(vm.watchPrefsSyncing)

                    Toggle("Upcoming release reminders", isOn: Binding(
                        get: { vm.upcomingReleaseRemindersEnabled },
                        set: { newValue in
                            Task { await vm.updateWatchPreferences(upcomingReleaseReminders: newValue) }
                        }
                    ))
                    .disabled(vm.watchPrefsSyncing)

                    if !vm.watchPrefsStatus.isEmpty {
                        Text(vm.watchPrefsStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Breaking News Alerts") {
                    Toggle("Breaking news alerts", isOn: Binding(
                        get: { breakingNewsManager.alertsEnabled },
                        set: { newValue in
                            Task { await breakingNewsManager.updateAlertsEnabled(newValue) }
                        }
                    ))

                    Text(breakingNewsStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Receive a push notification when a major story breaks. Requires notification permission.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section("Sports Provider") {
                    Picker("TV Provider", selection: $sportsProviderKey) {
                        ForEach(SportsProviderPreferences.options, id: \.key) { option in
                            Text(option.label).tag(option.key)
                        }
                    }
                    Toggle("Only show games on my provider", isOn: Binding(
                        get: { sportsAvailabilityOnly },
                        set: { newValue in
                            sportsAvailabilityOnly = newValue
                        }
                    ))
                    .disabled(sportsProviderKey == SportsProviderPreferences.allProviderKey)
                    Text(
                        sportsProviderKey == SportsProviderPreferences.allProviderKey
                            ? "Choose a provider to enable availability filtering in Sports."
                            : "Sports will prioritize games available on \(SportsProviderPreferences.label(for: sportsProviderKey))."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Sports Alerts") {
                    Toggle("Enable Sports Alerts", isOn: Binding(
                        get: { sportsAlertsManager.alertsEnabled },
                        set: { newValue in
                            Task { await sportsAlertsManager.updateAlertsEnabled(newValue) }
                        }
                    ))

                    Toggle("Game start alerts", isOn: Binding(
                        get: { sportsAlertsManager.startAlertsEnabled },
                        set: { newValue in
                            Task { await sportsAlertsManager.updateStartAlertsEnabled(newValue) }
                        }
                    ))
                    .disabled(!sportsAlertsManager.alertsEnabled)

                    Toggle("Close-game alerts", isOn: Binding(
                        get: { sportsAlertsManager.closeGameAlertsEnabled },
                        set: { newValue in
                            Task { await sportsAlertsManager.updateCloseGameAlertsEnabled(newValue) }
                        }
                    ))
                    .disabled(!sportsAlertsManager.alertsEnabled)

                    Toggle("Digest mode (fewer alerts)", isOn: Binding(
                        get: { sportsAlertsManager.digestModeEnabled },
                        set: { newValue in
                            Task { await sportsAlertsManager.updateDigestModeEnabled(newValue) }
                        }
                    ))
                    .disabled(!sportsAlertsManager.alertsEnabled)

                    Toggle("Quiet hours", isOn: Binding(
                        get: { sportsAlertsManager.quietHoursEnabled },
                        set: { newValue in
                            Task { await sportsAlertsManager.updateQuietHoursEnabled(newValue) }
                        }
                    ))
                    .disabled(!sportsAlertsManager.alertsEnabled)

                    if sportsAlertsManager.alertsEnabled && sportsAlertsManager.quietHoursEnabled {
                        DatePicker(
                            "Quiet hours start",
                            selection: $sportsQuietStartTime,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: sportsQuietStartTime) { _ in
                            Task {
                                await sportsAlertsManager.updateQuietHours(
                                    startHour: hourOf(sportsQuietStartTime),
                                    startMinute: minuteOf(sportsQuietStartTime),
                                    endHour: hourOf(sportsQuietEndTime),
                                    endMinute: minuteOf(sportsQuietEndTime)
                                )
                            }
                        }

                        DatePicker(
                            "Quiet hours end",
                            selection: $sportsQuietEndTime,
                            displayedComponents: .hourAndMinute
                        )
                        .onChange(of: sportsQuietEndTime) { _ in
                            Task {
                                await sportsAlertsManager.updateQuietHours(
                                    startHour: hourOf(sportsQuietStartTime),
                                    startMinute: minuteOf(sportsQuietStartTime),
                                    endHour: hourOf(sportsQuietEndTime),
                                    endMinute: minuteOf(sportsQuietEndTime)
                                )
                            }
                        }
                    }

                    Text(sportsAlertsStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Help") {
                    Button {
                        showHelp = true
                    } label: {
                        Label("Open Help & Feedback", systemImage: "questionmark.circle")
                    }

                    Button {
                        guard let url = AppHelpSupport.feedbackMailURL() else { return }
                        openURL(url)
                    } label: {
                        Label("Submit Feedback", systemImage: "envelope")
                    }

                    Text(AppHelpCopy.feedbackFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Onboarding") {
                    Button {
                        dismissSettings()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            PersonalizationOnboardingReplay.trigger()
                        }
                    } label: {
                        Label("Replay personalization onboarding", systemImage: "arrow.counterclockwise.circle")
                    }
                    Text(AppHelpCopy.onboardingFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy & Legal") {
                    Link(destination: URL(string: "https://big-daves-news-web.onrender.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Button {
                        openURL(URL(string: "mailto:support@bigdavesnews.com?subject=Data%20Deletion%20Request")!)
                    } label: {
                        Label("Request Data Deletion", systemImage: "trash")
                    }
                }

                Section("Build Info") {
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Environment: \(buildEnvironment)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showHelp) {
            AppHelpView()
        }
        .task {
            await habitNotifications.refreshAuthorizationStatus()
            await sportsAlertsManager.refreshAuthorizationStatus()
            await breakingNewsManager.refreshAuthorizationStatus()
            await vm.loadWatchPreferences()
            sportsProviderKey = SportsProviderPreferences.normalizedProviderKey(sportsProviderKey)
            if sportsProviderKey == SportsProviderPreferences.allProviderKey {
                sportsAvailabilityOnly = false
            }
            morningHabitTime = dateForTime(hour: habitNotifications.morningHour, minute: habitNotifications.morningMinute)
            eveningHabitTime = dateForTime(hour: habitNotifications.eveningHour, minute: habitNotifications.eveningMinute)
            habitQuietStartTime = dateForTime(hour: habitNotifications.quietStartHour, minute: habitNotifications.quietStartMinute)
            habitQuietEndTime = dateForTime(hour: habitNotifications.quietEndHour, minute: habitNotifications.quietEndMinute)
            sportsQuietStartTime = dateForTime(hour: sportsAlertsManager.quietHoursStartHour, minute: sportsAlertsManager.quietHoursStartMinute)
            sportsQuietEndTime = dateForTime(hour: sportsAlertsManager.quietHoursEndHour, minute: sportsAlertsManager.quietHoursEndMinute)
        }
        .onChange(of: sportsProviderKey) { newValue in
            sportsProviderKey = SportsProviderPreferences.normalizedProviderKey(newValue)
            if sportsProviderKey == SportsProviderPreferences.allProviderKey {
                sportsAvailabilityOnly = false
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    private var buildEnvironment: String {
        #if DEBUG
            return "Debug"
        #else
            return "Release"
        #endif
    }

    private var habitNotificationsStatusText: String {
        switch habitNotifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Notification access granted."
        case .denied:
            return "Notifications are disabled in iOS Settings."
        case .notDetermined:
            return "Notification permission not requested yet."
        @unknown default:
            return "Notification status unavailable."
        }
    }

    private var briefLastOpenedText: String {
        let key = "bdn-brief-last-opened-ios"
        guard let last = UserDefaults.standard.object(forKey: key) as? Date else {
            return "Never"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: last, relativeTo: Date())
    }

    private var breakingNewsStatusText: String {
        switch breakingNewsManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return breakingNewsManager.alertsEnabled
                ? "Breaking news alerts are on."
                : "Breaking news alerts are off."
        case .denied:
            return "Notifications are blocked in iOS Settings."
        case .notDetermined:
            return "Notification permission not yet requested."
        @unknown default:
            return "Notification status unavailable."
        }
    }

    private var sportsAlertsStatusText: String {
        switch sportsAlertsManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return sportsAlertsManager.digestModeEnabled
                ? "Sports alerts are enabled in digest mode."
                : "Sports alerts are enabled."
        case .denied:
            return "Sports alerts are blocked in iOS Settings."
        case .notDetermined:
            return "Sports alerts permission has not been requested."
        @unknown default:
            return "Sports alerts status unavailable."
        }
    }

    private func dateForTime(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func hourOf(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date)
    }

    private func minuteOf(_ date: Date) -> Int {
        Calendar.current.component(.minute, from: date)
    }
}
