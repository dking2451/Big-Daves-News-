import SwiftUI
import UserNotifications

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var subscribeStatus: String = ""
    @Published var isSubmitting = false
    @Published var subscriberCountLabel: String = ""
    @Published var watchEpisodeAlertsEnabled = false
    @Published var upcomingReleaseRemindersEnabled = false
    @Published var watchPrefsStatus = ""
    @Published var watchPrefsSyncing = false
    private let watchDeviceID = WatchDeviceIdentity.current

    func subscribe() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            subscribeStatus = "Enter an email first."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await APIClient.shared.subscribeEmail(trimmed)
            subscribeStatus = result.message
            subscriberCountLabel = "\(result.count)/\(result.max) subscribers"
            if result.success {
                UserDefaults.standard.set(trimmed, forKey: "bdn-subscriber-email-ios")
                await PushTokenManager.shared.registerWithBackendIfPossible()
                email = ""
            }
        } catch {
            subscribeStatus = error.localizedDescription
        }
    }

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
    @StateObject private var reminderManager = ReminderManager()
    @StateObject private var pushTokenManager = PushTokenManager.shared
    @State private var reminderTime = Date()
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Email Signup") {
                    TextField("name@email.com", text: $vm.email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    Button(vm.isSubmitting ? "Adding..." : "Add to Email List") {
                        Task { await vm.subscribe() }
                    }
                    .disabled(vm.isSubmitting)
                    if !vm.subscribeStatus.isEmpty {
                        Text(vm.subscribeStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !vm.subscriberCountLabel.isEmpty {
                        Text(vm.subscriberCountLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Daily Brief Reminder") {
                    Toggle("Enable Brief Reminder", isOn: Binding(
                        get: { reminderManager.remindersEnabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    try? await reminderManager.requestAndEnableReminder()
                                } else {
                                    await reminderManager.disableReminder()
                                }
                            }
                        }
                    ))

                    DatePicker(
                        "Brief Time",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: reminderTime) { newValue in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        let hour = comps.hour ?? 8
                        let minute = comps.minute ?? 0
                        Task { try? await reminderManager.updateReminderTime(hour: hour, minute: minute) }
                    }

                    Text(reminderStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Last Brief Opened: \(briefLastOpenedText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Push Sync: \(pushTokenManager.syncStatus)")
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

                Section("Help") {
                    Button {
                        showHelp = true
                    } label: {
                        Label("Open Help & Feedback", systemImage: "questionmark.circle")
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
            await reminderManager.refreshAuthorizationStatus()
            await vm.loadWatchPreferences()
            var components = DateComponents()
            components.hour = reminderManager.reminderHour
            components.minute = reminderManager.reminderMinute
            reminderTime = Calendar.current.date(from: components) ?? Date()
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

    private var reminderStatusText: String {
        switch reminderManager.authorizationStatus {
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
}
