import SwiftUI
import UserNotifications

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var subscribeStatus: String = ""
    @Published var isSubmitting = false
    @Published var subscriberCountLabel: String = ""

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
}

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @StateObject private var reminderManager = ReminderManager()
    @StateObject private var pushTokenManager = PushTokenManager.shared
    @State private var reminderTime = Date()

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

                Section("Morning Reminder") {
                    Toggle("Enable Daily Reminder", isOn: Binding(
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
                        "Reminder Time",
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
                    Text("Push Sync: \(pushTokenManager.syncStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .task {
            await reminderManager.refreshAuthorizationStatus()
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
}
